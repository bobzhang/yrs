///|
test "missing sequence dependency does not block an independent later map item" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("text")
  text.insert(0, "a")
  let prefix = source.encode_state_as_update_v1()
  let cut = source.state_vector()
  text.insert(1, "b")
  source.get_or_insert_map("map").insert("ready", Bool(true))
  for v2 in [false, true] {
    for skip_gc in [false, true] {
      let peer = @yrs.Doc(client_id=2UL, skip_gc~)
      let observed = []
      let map = peer.get_or_insert_map("map")
      map.observe("ready", fn(_, _) {
        observed.push(map.get("ready").unwrap().to_json())
      })
      let packet = if v2 {
        source.encode_diff_v2(cut)
      } else {
        source.encode_diff_v1(cut)
      }
      if v2 {
        peer.apply_update_v2(packet)
      } else {
        peer.apply_update_v1(packet)
      }
      assert_eq(map.get("ready").unwrap().to_json(), Json(true))
      assert_eq(observed, [Json(true)])
      assert_true(peer.has_pending_updates())
      assert_eq(peer.state_vector().get(1UL), 0U)
      // Duplicate delivery neither stalls nor repeats the completed map event.
      if v2 {
        peer.apply_update_v2(packet)
      } else {
        peer.apply_update_v1(packet)
      }
      assert_eq(observed.length(), 1)
      peer.apply_update_v1(prefix)
      assert_false(peer.has_pending_updates())
      assert_eq(peer.get_or_insert_text("text").get_string(), "ab")
      assert_eq(peer.state_vector(), source.state_vector())
      let restored = @yrs.Doc(client_id=3UL, skip_gc~)
      restored.apply_update_v2(peer.encode_state_as_update_v2())
      assert_eq(
        restored.get_or_insert_map("map").get("ready").unwrap().to_json(),
        Json(true),
      )
      assert_eq(restored.get_or_insert_text("text").get_string(), "ab")
    }
  }
}
