///|
test "destroy removes only the destroyed document undo history" {
  let a = @yrs.Doc(client_id=1UL, guid="A")
  let b = @yrs.Doc(client_id=2UL, guid="B")
  let ta = a.get_or_insert_text("text")
  let tb = b.get_or_insert_text("text")
  let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  manager.expand_scope(Text(ta))
  manager.expand_scope(Text(tb))
  ta.insert(0, "a")
  tb.insert(0, "b")
  assert_eq(manager.docs().length(), 2)
  b.destroy()
  assert_eq(manager.docs().map(@yrs.Doc::guid), ["A"])
  assert_eq(manager.undo_stack().length(), 1)
  assert_true(manager.undo())
  assert_eq(ta.get_string(), "")
  assert_eq(tb.get_string(), "b")
  assert_true(manager.redo())
  assert_eq(ta.get_string(), "a")
  manager.destroy()
  a.destroy()
}

///|
test "undo event ancestors use document identity and stable branch IDs" {
  let doc = @yrs.Doc(client_id=1UL)
  let other = @yrs.Doc(client_id=2UL)
  let root = doc.get_or_insert_map("root")
  let text = root.insert_text("text")
  let unrelated = other.get_or_insert_map("root")
  let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  manager.expand_scope(Map(root))
  let results = []
  manager.observe_item_added("check", fn(event, transaction) {
    results.push(
      (
        event.has_changed(Map(root)),
        event.has_changed(Text(text)),
        event.has_changed(Map(unrelated)),
        event.changed_parent_types().length(),
        transaction.changed_parent_types().length(),
      ),
    )
  })
  text.insert(0, "hello")
  assert_eq(results, [(true, true, false, 2, 2)])
  let value : @yrs.Out = Text(text)
  let id = value.branch_id().unwrap()
  other.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(id.get(other).unwrap().to_json(), Json("hello"))
  root.remove("text")
  assert_true(value.is_deleted())
  assert_true(id.get(doc).unwrap().is_deleted())
  manager.destroy()
  doc.gc()
  assert_true(id.get(doc) is None)
}

///|
test "saved undo metadata survives reload and initial stack entries are owned" {
  let doc = @yrs.Doc(client_id=1UL, guid="saved")
  let text = doc.get_or_insert_text("text")
  let manager : @yrs.UndoManager[Int32] = UndoManager(clock=fn() { 100UL })
  manager.expand_scope(Text(text))
  manager.observe_item_added("meta", fn(e, _) { e.set_meta(42) })
  text.insert(0, "hello")
  let saved = manager.undo_stack()[0].to_json(fn(n) { Json(n) })
  let peer = @yrs.Doc(client_id=2UL, guid="saved")
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  let entry = @yrs.StackItem::from_json(saved, peer, fn(v) {
    guard v is Number(n, ..) else { abort("metadata") }
    n.to_int()
  })
  let loaded : @yrs.UndoManager[Int32] = UndoManager(clock=fn() { 100UL }, init_undo_stack=[
    entry,
  ])
  let restored = peer.get_or_insert_text("text")
  loaded.expand_scope(Text(restored))
  entry.set_meta(99)
  assert_eq(loaded.undo_stack()[0].meta, 42)
  assert_true(loaded.undo())
  assert_eq(restored.get_string(), "")
  assert_true(loaded.redo())
  assert_eq(restored.get_string(), "hello")
  try
    @yrs.StackItem::from_json(saved, @yrs.Doc(client_id=3UL, guid="wrong"), fn(
      _,
    ) {
      0
    })
  catch {
    @yrs.DecodeError::InvalidData(_) => ()
  } noraise {
    _ => fail("wrong GUID accepted")
  }
}
