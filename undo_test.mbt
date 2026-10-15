///|
test "selective undo preserves remote edits and follows repeated restoration" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let text = a.get_or_insert_text("text")
  let remote = b.get_or_insert_text("text")
  let undo : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  undo.expand_scope(Text(text))
  text.insert(0, "abc")
  undo.reset()
  remote.insert(0, "xyz")
  a.transact(
    fn(_) raise { a.apply_update_v1(b.encode_state_as_update_v1()) },
    origin=b"remote",
  )
  assert_eq(text.get_string(), "abcxyz")
  assert_true(undo.undo())
  assert_eq(text.get_string(), "xyz")
  assert_true(undo.redo())
  assert_eq(text.get_string(), "abcxyz")
  assert_true(undo.undo())
  assert_eq(text.get_string(), "xyz")
  assert_true(undo.redo())
  assert_eq(text.get_string(), "abcxyz")
}

///|
test "undo restores nested types and persistent positions" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let child = root.insert_map("child")
  let text = child.insert_text("text")
  text.insert(0, "hello")
  let position = text.sticky_index(3).unwrap()
  let boundary = text.sticky_boundary(assoc=Before)
  let undo : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  undo.expand_scope(Map(root))
  root.remove("child") |> ignore
  assert_true(undo.undo())
  assert_eq(root.to_json(), { "child": { "text": "hello" } })
  assert_eq(position.get_offset(doc).unwrap().index, 3)
  assert_eq(boundary.get_offset(doc).unwrap().index, 0)
  assert_true(undo.redo())
  assert_eq(root.to_json(), {})
  assert_true(undo.undo())
  assert_eq(root.to_json(), { "child": { "text": "hello" } })
}

///|
test "capture intervals origins metadata and redo invalidation" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  let undo : @yrs.UndoManager[Int32] = UndoManager(clock=fn() { 100UL })
  let events : Array[String] = []
  undo.expand_scope(Text(text))
  undo.observe_item_added("meta", fn(event, _) {
    event.set_meta(7)
    events.push("add")
  })
  undo.observe_item_updated("meta", fn(event, _) {
    event.set_meta(event.meta + 1)
    events.push("update")
  })
  text.insert(0, "a")
  text.insert(1, "b")
  assert_eq(undo.undo_stack().length(), 1)
  assert_eq(undo.undo_stack()[0].meta, 8)
  undo.reset()
  text.insert(2, "c")
  assert_eq(events, ["add", "update", "add"])
  assert_true(undo.undo())
  assert_eq(text.get_string(), "ab")
  undo.include_origin(b"user")
  text.insert(2, "outside")
  assert_true(undo.can_redo())
  doc.transact(fn(_) { text.insert(0, "tracked") }, origin=b"user")
  assert_false(undo.can_redo())
  undo.destroy()
  assert_false(undo.can_undo())
}

///|
test "repeated nested undo preserves overwritten child map entries" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let child = root.insert_map("child")
  child.insert("done", Bool(false))
  let undo : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  undo.expand_scope(Map(root))
  doc.transact(fn(_) {
    child.insert("done", Bool(true))
    root.remove("child") |> ignore
  })
  assert_true(undo.undo())
  assert_eq(root.to_json(), { "child": { "done": false } })
  doc.transact(fn(_) {
    root.remove("child") |> ignore
    root.insert_map("child").insert("replacement", Bool(true))
  })
  assert_true(undo.undo())
  assert_eq(root.to_json(), { "child": { "done": false } })
  let replica = @yrs.Doc(client_id=2UL)
  replica.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(replica.get_or_insert_map("root").to_json(), root.to_json())
}

///|
test "undo scope supports multiple documents and invalidates redo only for the edited document" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let left = a.get_or_insert_text("note")
  let right = b.get_or_insert_text("note")
  let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  manager.expand_scope(Text(left))
  manager.expand_scope(Text(right))
  left.insert(0, "a")
  right.insert(0, "b")
  assert_eq(manager.undo_stack().length(), 2)
  assert_true(manager.undo())
  assert_true(manager.undo())
  assert_eq(left.get_string(), "")
  assert_eq(right.get_string(), "")
  assert_true(manager.redo())
  assert_eq(left.get_string(), "a")
  left.insert(1, "x")
  assert_true(manager.can_redo())
  assert_true(manager.redo())
  assert_eq(left.get_string(), "ax")
  assert_eq(right.get_string(), "b")
}
