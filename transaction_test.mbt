///|
test "grouped transaction emits one replayable update and stable metadata" {
  let doc = @yrs.Doc(client_id=1UL)
  let peer = @yrs.Doc(client_id=2UL)
  let peer_v2 = @yrs.Doc(client_id=3UL)
  let events : Array[@yrs.Transaction] = []
  let phases : Array[String] = []
  doc.observe_before_observer_calls("test", fn(_) { phases.push("before") })
  doc.observe_after_transaction("test", fn(_) { phases.push("after") })
  doc.observe_transaction_cleanup("test", fn(_) { phases.push("cleanup") })
  doc.observe_update_v1("test", fn(bytes, transaction) {
    phases.push("v1")
    events.push(transaction)
    try! peer.apply_update_v1(bytes)
  })
  doc.observe_update_v2("test", fn(bytes, _) {
    phases.push("v2")
    try! peer_v2.apply_update_v2(bytes)
  })
  let text = doc.get_or_insert_text("note")
  let value = doc.transact(
    fn(txn) raise {
      assert_eq(txn.origin(), Some(b"user"))
      text.insert(0, "ab")
      text.insert(1, "X")
      text.remove_range(0, 1)
      doc.get_or_insert_map("settings").insert("version", Integer(1L))
      42
    },
    origin=b"user",
  )
  assert_eq(value, 42)
  assert_eq(events.length(), 1)
  assert_eq(phases, ["before", "after", "cleanup", "v1", "v2"])
  assert_eq(peer.get_or_insert_text("note").get_string(), "Xb")
  assert_eq(peer_v2.get_or_insert_text("note").get_string(), "Xb")
  let event = events[0]
  let update = event.encode_update_v1()
  let state = event.after_state().entries()
  assert_true(event.is_local())
  assert_eq(event.before_state().entries(), [(1UL, 0U)])
  assert_eq(event.deletions(), [(1UL, 0U, 1U)])
  text.insert(0, "next")
  assert_eq(event.encode_update_v1(), update)
  assert_eq(event.after_state().entries(), state)
  assert_true(doc.unobserve_update_v1("test"))
  assert_true(!doc.unobserve_update_v1("test"))
}

///|
priv suberror TestTransactionError {
  StopAction
}

///|
test "transaction scope commits partial edits when the action raises" {
  let doc = @yrs.Doc(client_id=1UL)
  let updates : Array[Bytes] = []
  let cleanup : Array[Bool] = []
  doc.observe_update_v1("test", fn(bytes, _) { updates.push(bytes) })
  doc.observe_transaction_cleanup("test", fn(txn) {
    cleanup.push(txn.is_local())
  })
  doc.transact(fn(_) { () })
  assert_eq(updates.length(), 0)
  assert_eq(cleanup.length(), 1)
  try
    doc.transact(fn(_) -> Unit raise {
      doc.get_or_insert_text("note").insert(0, "retained")
      raise StopAction
    })
  catch {
    StopAction => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("missing error")
  }
  assert_eq(updates.length(), 1)
  assert_eq(cleanup.length(), 2)
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(updates[0])
  assert_eq(peer.get_or_insert_text("note").get_string(), "retained")
  doc.get_or_insert_text("note").insert(8, "!")
  assert_eq(updates.length(), 2)
}

///|
test "remote update transactions identify source and suppress duplicate update events" {
  let source = @yrs.Doc(client_id=1UL)
  source
  .get_or_insert_text("note")
  .insert_with_attributes(0, "hello", [("bold", Bool(true))])
  let target = @yrs.Doc(client_id=2UL)
  let transactions : Array[@yrs.Transaction] = []
  let updates : Array[Bytes] = []
  target.observe_transaction_cleanup("test", fn(txn) { transactions.push(txn) })
  target.observe_update_v1("test", fn(bytes, _) { updates.push(bytes) })
  let bytes = source.encode_state_as_update_v1()
  target.transact(fn(_) raise { target.apply_update_v1(bytes) }, origin=b"peer")
  assert_eq(transactions.length(), 1)
  assert_true(!transactions[0].is_local())
  assert_eq(transactions[0].origin(), Some(b"peer"))
  assert_eq(updates.length(), 1)
  target.apply_update_v1(bytes)
  assert_eq(transactions.length(), 2)
  assert_true(!transactions[1].is_local())
  assert_eq(updates.length(), 1)
  let observer = @yrs.Doc(client_id=3UL)
  observer.apply_update_v1(updates[0])
  assert_eq(
    observer.get_or_insert_text("note").to_delta().map(fn(c) { c.to_json() }),
    target.get_or_insert_text("note").to_delta().map(fn(c) { c.to_json() }),
  )
}

///|
test "after-transaction hook may add edits to the same emitted update" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  let updates : Array[Bytes] = []
  let phases : Array[String] = []
  doc.observe_after_transaction("append", fn(_) {
    phases.push("after")
    text.insert(text.length(), "!")
  })
  doc.observe_update_v1("test", fn(bytes, _) { updates.push(bytes) })
  text.insert(0, "hello")
  assert_eq(updates.length(), 1)
  assert_eq(phases, ["after"])
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(updates[0])
  assert_eq(peer.get_or_insert_text("note").get_string(), "hello!")
}
