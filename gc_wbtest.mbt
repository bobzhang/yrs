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

///|
test "GC refreshes undo retention after insertion-only transactions and history release" {
  let doc = Doc(client_id=1UL, skip_gc=false)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "prefix")
  let undo : UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  undo.expand_scope(Text(text))
  text.remove_range(0, 6)
  // An insertion-only transaction does not need GC. Retained old characters
  // must still be released when a later collection sees the cleared history.
  undo.reset()
  text.insert(0, "tail")
  undo.clear_all()
  doc.gc()
  assert_false(
    doc.clients[1UL].any(fn(item) {
      item.deleted && item.content is Characters(_)
    }),
  )
  undo.reset()
  text.remove_range(1, 2)
  doc.gc()
  assert_true(undo.undo())
  assert_eq(text.get_string(), "tail")
  let copy = Doc(client_id=2UL)
  copy.apply_update_v2(doc.encode_state_as_update_v2())
  assert_eq(copy.get_or_insert_text("text").get_string(), "tail")
}

///|
test "GC range search includes overlapping blocks and skips unrelated clients" {
  let doc = Doc(client_id=1UL, skip_gc=true)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abcdefghij")
  text.remove_range(2, 6)
  // Interior range must include its containing deleted block, even though its
  // start clock precedes the range. Automatic GC uses the same range lookup.
  doc.collect_garbage([(1UL, 4U, 5U), (77UL, 0U, 10U)])
  assert_true(
    doc.find({ client: 1UL, clock: 4U, }).unwrap().content is Deleted(6),
  )
  assert_eq(text.get_string(), "abij")
}

///|
test "received GC blocks advertise deletions even when the receiver already knows their clocks" {
  // One client, one GC block at client 7 clock 0, length 1, empty delete set.
  let collected = b"\x01\x01\x07\x00\x00\x01\x00"
  for gc in [false, true] {
    let source = Doc(client_id=8UL, skip_gc=!gc)
    source.apply_update_v1(collected)
    assert_true(
      source.snapshot().delete_set().contains({ client: 7UL, clock: 0U, }),
    )
    for v2 in [false, true] {
      let peer = Doc(client_id=7UL)
      peer.get_or_insert_text("text").insert(0, "x")
      let remote = peer.state_vector()
      if v2 {
        peer.apply_update_v2(source.encode_state_as_update_v2(remote~))
      } else {
        peer.apply_update_v1(source.encode_state_as_update_v1(remote~))
      }
      assert_eq(peer.get_or_insert_text("text").get_string(), "")
    }
  }
}
