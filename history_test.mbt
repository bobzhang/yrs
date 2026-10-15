///|
test "sticky positions survive edits and remote updates" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("note")
  text.insert(0, "abc")
  let before = text.sticky_index(1, assoc=Before).unwrap()
  let after = text.sticky_index(1).unwrap()
  text.insert(1, "XYZ")
  assert_eq(before.get_offset(a).unwrap().index, 1)
  assert_eq(after.get_offset(a).unwrap().index, 4)
  text.remove_range(4, 1)
  assert_eq(after.get_offset(a).unwrap().index, 4)
  let b = @yrs.Doc(client_id=2UL)
  b.apply_update_v2(a.encode_state_as_update_v2())
  let decoded = @yrs.StickyIndex::decode_v1(after.encode_v1())
  assert_eq(decoded.get_offset(b), after.get_offset(a))
  assert_eq(@yrs.StickyIndex::from_json(after.to_json()), after)
  assert_true(text.sticky_index(text.length()) is None)
  let end = @yrs.StickyIndex(scope=Root("note"))
  assert_eq(end.get_offset(a).unwrap().index, text.length())
  assert_true(end.get_offset(Doc(client_id=3UL)) is None)
}

///|
test "sticky cursor JSON preserves wide client identities and Yjs field precedence" {
  let position = @yrs.StickyIndex(
    scope=Relative({ client: 0xffff_ffff_ffff_ffffUL, clock: 0xffff_ffffU, }),
    assoc=Before,
  )
  assert_eq(@yrs.StickyIndex::from_json(position.to_json()), position)
  assert_eq(@yrs.StickyIndex::decode_v1(position.encode_v1()), position)
  let selected = @yrs.StickyIndex::from_json({
    "item": { "client": 7, "clock": 3 },
    "type": { "client": 8, "clock": 2 },
    "tname": null,
    "assoc": -1,
  })
  assert_eq(selected.id(), Some({ client: 7UL, clock: 3U, }))
  for
    invalid in [
      ({ "item": { "client": -1, "clock": 0 } } : Json),
      { "tname": "note", "assoc": 2 },
      { "tname": "note", "unknown": 0 },
    ] {
    try @yrs.StickyIndex::from_json(invalid) catch {
      InvalidData(_) => ()
    } noraise {
      _ => fail("invalid cursor accepted")
    }
  }
}

///|
test "snapshots retain historical content after deletion and nested replacement" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("note")
  text.insert(0, "before")
  let map = a.get_or_insert_map("settings")
  map.insert_text("title").insert(0, "old")
  let snapshot = a.snapshot()
  text.remove_range(0, 3)
  text.insert(0, "after")
  map.insert_text("title").insert(0, "new")
  let current = a.snapshot()
  for v2 in [false, true] {
    let copy = if v2 {
      @yrs.Snapshot::decode_v2(snapshot.encode_v2())
    } else {
      @yrs.Snapshot::decode_v1(snapshot.encode_v1())
    }
    assert_eq(copy.state_vector().entries(), snapshot.state_vector().entries())
    assert_eq(copy.deletions(), snapshot.deletions())
    let restored = @yrs.Doc(client_id=2UL)
    if v2 {
      restored.apply_update_v2(a.encode_state_from_snapshot_v2(copy))
    } else {
      restored.apply_update_v1(a.encode_state_from_snapshot_v1(copy))
    }
    assert_eq(restored.get_or_insert_text("note").get_string(), "before")
    assert_eq(restored.get_or_insert_map("settings").to_json(), {
      "title": "old",
    })
  }
  assert_eq(snapshot.deletions(), [])
  assert_true(!current.deletions().is_empty())
  let metadata = snapshot.state_vector()
  metadata.set_max(1UL, 999U)
  assert_true(snapshot.state_vector().get(1UL) < 999U)
  let partial = @yrs.Snapshot(state=StateVector(entries=[(1UL, 3U)]))
  let restored = @yrs.Doc(client_id=3UL)
  restored.apply_update_v1(a.encode_state_from_snapshot_v1(partial))
  assert_eq(restored.get_or_insert_text("note").get_string(), "bef")
}

///|
test "snapshot clipping retains the right-origin identity" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  text.insert(0, "ab")
  text.insert(1, "X")
  let snapshot = doc.snapshot()
  text.insert(2, "Y")
  let copy = @yrs.Doc(client_id=2UL)
  copy.apply_update_v1(doc.encode_state_from_snapshot_v1(snapshot))
  assert_eq(copy.get_or_insert_text("note").get_string(), "aXb")
  let nested = doc.get_or_insert_map("settings").insert_text("title")
  let end = nested.sticky_boundary()
  nested.insert(0, "title")
  assert_eq(end.get_offset(doc).unwrap().index, 5)
  doc.get_or_insert_map("settings").remove("title")
  assert_eq(end.get_offset(doc).unwrap().index, 0)
}
