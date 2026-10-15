///|
test "automatic GC drops content but preserves clocks and remote insertion anchors" {
  let a = Doc(client_id=1UL, skip_gc=false)
  let b = Doc(client_id=2UL)
  let text = a.get_or_insert_text("text")
  text.insert(0, "obsolete")
  b.apply_update_v1(a.encode_state_as_update_v1())
  b.get_or_insert_text("text").insert(4, "kept")
  text.remove_range(0, 8)
  assert_true(a.clients[1UL][0].content is Deleted(8))
  a.apply_update_v1(b.encode_state_as_update_v1())
  assert_eq(text.get_string(), "kept")
  b.apply_update_v2(a.encode_state_as_update_v2())
  assert_eq(b.get_or_insert_text("text").get_string(), "kept")
  assert_eq(a.state_vector().get(1UL), 8U)
}

///|
test "nested GC releases values and explicit collection respects undo retention" {
  let doc = Doc(client_id=1UL, skip_gc=false)
  let root = doc.get_or_insert_map("root")
  let nested = root.insert_map("child")
  nested.insert_text("body").insert(0, "deleted payload")
  root.remove("child")
  assert_true(doc.clients[1UL].any(fn(item) { item.content is Garbage(_) }))
  assert_eq(root.entries().length(), 0)
  let text = doc.get_or_insert_text("text")
  let undo : UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  undo.expand_scope(Text(text))
  text.insert(0, "retained for undo")
  undo.reset()
  text.remove_range(0, text.length())
  doc.gc()
  assert_true(undo.undo())
  assert_eq(text.get_string(), "retained for undo")
  assert_true(undo.redo())
  undo.clear_all()
  doc.gc()
  assert_false(doc.clients[1UL].any(fn(item) { item.content is Characters(_) }))
}

///|
test "clearing one undo manager preserves another manager's history" {
  let doc = Doc(client_id=1UL, skip_gc=false)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "shared retention")
  let a : UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  let b : UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  a.expand_scope(Text(text))
  b.expand_scope(Text(text))
  text.remove_range(0, text.length())
  a.clear_all()
  doc.gc()
  assert_true(b.undo())
  assert_eq(text.get_string(), "shared retention")
}

///|
test "snapshot encoder rejects automatic GC documents" {
  let doc = Doc(client_id=1UL, skip_gc=false)
  try doc.encode_state_from_snapshot_v1(doc.snapshot()) catch {
    InvalidData(_) => ()
  } noraise {
    _ => fail("snapshot encoding should reject GC")
  }
}
