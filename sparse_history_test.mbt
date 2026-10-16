///|
test "sparse snapshots preserve visible history across later gap filling" {
  for v2 in [false, true] {
    let source = @yrs.Doc(client_id=1UL)
    source.get_or_insert_text("missing").insert(0, "hidden")
    let prefix = source.encode_state_as_update_v1()
    let cut = source.state_vector()
    source.get_or_insert_text("ready").insert(0, "abc")
    let peer = @yrs.Doc(client_id=2UL)
    if v2 {
      peer.apply_update_v2(source.encode_diff_v2(cut))
    } else {
      peer.apply_update_v1(source.encode_diff_v1(cut))
    }
    let saved = peer.snapshot()
    let saved = if v2 {
      @yrs.Snapshot::decode_v2(saved.encode_v2())
    } else {
      @yrs.Snapshot::decode_v1(saved.encode_v1())
    }
    assert_eq(peer.state_vector().get(1UL), 0U)
    assert_true(saved.is_visible({ client: 1UL, clock: 6U, }))
    assert_true(!saved.is_visible({ client: 1UL, clock: 0U, }))
    for after_prefix in [false, true] {
      if after_prefix {
        peer.apply_update_v1(prefix)
        peer.get_or_insert_text("ready").insert(0, "later")
      }
      let restored = @yrs.Doc(client_id=3UL)
      if v2 {
        restored.apply_update_v2(peer.encode_state_from_snapshot_v2(saved))
      } else {
        restored.apply_update_v1(peer.encode_state_from_snapshot_v1(saved))
      }
      assert_eq(restored.get_or_insert_text("ready").get_string(), "abc")
      assert_eq(restored.get_or_insert_text("missing").get_string(), "")
      let chunks = peer
        .get_or_insert_text("ready")
        .diff_range(@yrs.YChange::identity, hi=saved)
      assert_eq(chunks.length(), 1)
      assert_eq(chunks[0].insert.to_json(), Json("abc"))
      // Snapshot exclusions must never become ordinary replication deletions.
      let current = @yrs.Doc(client_id=4UL)
      current.apply_update_v1(peer.encode_diff_v1(@yrs.StateVector()))
      current.apply_update_v1(prefix)
      assert_eq(current.get_or_insert_text("missing").get_string(), "hidden")
    }
  }
}
