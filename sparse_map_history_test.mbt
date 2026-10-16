///|
fn check_sparse_map_snapshot(v2 : Bool, fill_gap : Bool) -> Unit raise {
  let source = @yrs.Doc(client_id=1UL)
  let source_map = source.get_or_insert_map("map")
  source_map.insert("key", String("old"))
  let base = source.encode_state_as_update_v1()
  source_map.insert("key", String("new"))
  let missing = source.encode_state_as_update_v1()
  let packets = []
  source.observe_update_v2("packet", fn(bytes, _) { packets.push(bytes) })
  source.get_or_insert_text("ready").push("suffix")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(base)
  peer.apply_update_v2(packets[0])
  assert_eq(
    peer.get_or_insert_map("map").get("key").unwrap().to_json(),
    Json("old"),
  )
  let saved = peer.snapshot()
  let saved = if v2 {
    @yrs.Snapshot::decode_v2(saved.encode_v2())
  } else {
    @yrs.Snapshot::decode_v1(saved.encode_v1())
  }
  if fill_gap {
    peer.apply_update_v1(missing)
  }
  let restored = @yrs.Doc(client_id=3UL)
  if v2 {
    restored.apply_update_v2(peer.encode_state_from_snapshot_v2(saved))
  } else {
    restored.apply_update_v1(peer.encode_state_from_snapshot_v1(saved))
  }
  assert_eq(restored.get_or_insert_text("ready").get_string(), "suffix")
  assert_eq(
    restored.get_or_insert_map("map").get("key").map(fn(x) { x.to_json() }),
    Some(Json("old")),
  )
}

///|
test "sparse snapshot map v1 before gap fill" {
  check_sparse_map_snapshot(false, false)
}

///|
test "sparse snapshot map v1 after gap fill" {
  check_sparse_map_snapshot(false, true)
}

///|
test "sparse snapshot map v2 before gap fill" {
  check_sparse_map_snapshot(true, false)
}

///|
test "sparse snapshot map v2 after gap fill" {
  check_sparse_map_snapshot(true, true)
}

///|
test "sparse snapshot restores overwritten shared map values and their children" {
  for v2 in [false, true] {
    let source = @yrs.Doc(client_id=1UL)
    let map = source.get_or_insert_map("map")
    map.insert_text("key").push("old child")
    let before = source.encode_state_as_update_v1()
    map.insert_array("key").insert_range(0, [String("new child")])
    let missing = source.encode_state_as_update_v1()
    let packets = []
    source.observe_update_v2("packet", fn(packet, _) { packets.push(packet) })
    source.get_or_insert_text("ready").push("suffix")
    let peer = @yrs.Doc(client_id=2UL)
    peer.apply_update_v1(before)
    peer.apply_update_v2(packets[0])
    let saved = peer.snapshot()
    let saved = @yrs.Snapshot::decode_v2(saved.encode_v2())
    peer.apply_update_v1(missing)
    let restored = @yrs.Doc(client_id=3UL)
    if v2 {
      restored.apply_update_v2(peer.encode_state_from_snapshot_v2(saved))
    } else {
      restored.apply_update_v1(peer.encode_state_from_snapshot_v1(saved))
    }
    assert_eq(
      restored.get_or_insert_map("map").get("key").unwrap().to_json(),
      Json("old child"),
    )
    assert_eq(restored.get_or_insert_text("ready").get_string(), "suffix")
    assert_false(restored.has_pending_updates())
  }
}
