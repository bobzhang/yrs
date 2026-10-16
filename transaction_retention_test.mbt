///|
test "subdocument-only observers retain frozen transaction metadata and packets" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("files")
  let events : Array[@yrs.Transaction] = []
  doc.observe_subdocs("save", fn(_, txn) { events.push(txn) })
  map.insert_doc("child", @yrs.Doc(client_id=2UL, guid="child")) |> ignore
  let saved = events[0]
  let expected = doc.state_vector().entries()
  let v1 = saved.encode_update_v1()
  let v2 = saved.encode_update_v2()
  map.insert("later", Integer(42L))
  assert_eq(saved.after_state().entries(), expected)
  assert_eq(saved.encode_update_v1(), v1)
  assert_eq(saved.encode_update_v2(), v2)
  let replay = @yrs.Doc(client_id=3UL)
  replay.apply_update_v2(saved.encode_update_v2())
  assert_true(replay.get_or_insert_map("files").get("later") is None)
  assert_true(replay.get_or_insert_map("files").get("child") is Some(Subdoc(_)))
}

///|
test "weak-only observers retain frozen transaction metadata and packets" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abc")
  guard doc
    .get_or_insert_map("links")
    .insert_input("quote", WeakLink(text.quote(Unbounded, Unbounded)))
    is WeakLink(link) else {
    fail("missing weak link")
  }
  let events : Array[@yrs.Transaction] = []
  link.observe("save", fn(_, txn) { events.push(txn) })
  text.insert(0, "x")
  let saved = events[0]
  let expected = doc.state_vector().entries()
  let v1 = saved.encode_update_v1()
  let v2 = saved.encode_update_v2()
  text.insert(0, "y")
  assert_eq(saved.after_state().entries(), expected)
  assert_eq(saved.encode_update_v1(), v1)
  assert_eq(saved.encode_update_v2(), v2)
}
