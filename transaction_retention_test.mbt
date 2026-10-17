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

///|
test "first encoding of a retained transaction stays frozen after later GC and edits" {
  let doc = @yrs.Doc(client_id=1UL, skip_gc=false)
  let text = doc.get_or_insert_text("text")
  let saved = doc.transact(tx => {
    text.insert(0, "original")
    doc
    .get_or_insert_map("root")
    .insert_doc(
      "child",
      @yrs.Doc(client_id=2UL, guid="child", should_load=false),
    )
    |> ignore
    tx
  })
  // Neither format has been requested yet. Later edits split and collect the
  // original blocks and mutate the live child's descriptor.
  doc.subdocs()[0].load()
  doc.subdocs()[0].destroy()
  text.remove_range(1, 5)
  text.push("later")
  doc.get_or_insert_map("root").remove("child") |> ignore
  doc.gc()
  for v2 in [false, true] {
    let replay = @yrs.Doc(client_id=9UL)
    if v2 {
      replay.apply_update_v2(saved.encode_update_v2())
    } else {
      replay.apply_update_v1(saved.encode_update_v1())
    }
    assert_eq(replay.get_or_insert_text("text").get_string(), "original")
    assert_eq(replay.subdocs().length(), 1)
    assert_false(replay.subdocs()[0].should_load())
  }
}

///|
test "live transaction encoding does not cache an incomplete update" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  let saved = doc.transact(tx => {
    text.push("a")
    tx.encode_update_v1() |> ignore
    tx.encode_update_v2() |> ignore
    text.push("b")
    tx
  })
  text.push("c")
  let replay = @yrs.Doc(client_id=2UL)
  replay.apply_update_v2(saved.encode_update_v2())
  assert_eq(replay.get_or_insert_text("text").get_string(), "ab")
}

///|
test "lazy v2 transaction encoding retains typed values after their deletion" {
  let doc = @yrs.Doc(client_id=1UL, skip_gc=false)
  let text = doc.get_or_insert_text("text")
  let saved = doc.transact(tx => {
    text.insert_embed(0, Buffer(b"\x01\x02"))
    text.insert_with_attributes(1, "x", [("custom", Integer(9007199254740993L))])
    tx
  })
  text.remove_range(0, 2)
  let replay = @yrs.Doc(client_id=2UL)
  replay.apply_update_v2(saved.encode_update_v2())
  let delta = replay.get_or_insert_text("text").to_delta()
  assert_true(delta[0].insert == @yrs.Out::Value(Buffer(b"\x01\x02")))
  assert_eq(delta[1].attributes, [("custom", Integer(9007199254740993L))])
}
