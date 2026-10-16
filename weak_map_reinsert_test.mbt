///|
test "map link observers survive deletion reinsertion and reload" {
  for skip_gc in [false, true] {
    for v2 in [false, true] {
      let doc = @yrs.Doc(client_id=1UL, skip_gc~)
      let map = doc.get_or_insert_map("map")
      map.insert("key", Integer(1L))
      let link = weak(
        map.insert_input("link", WeakLink(map.link("key").unwrap())),
      )
      map.remove("key")
      let peer = @yrs.Doc(client_id=2UL, skip_gc~)
      if v2 {
        peer.apply_update_v2(doc.encode_state_as_update_v2())
      } else {
        peer.apply_update_v1(doc.encode_state_as_update_v1())
      }
      let remote_map = peer.get_or_insert_map("map")
      let remote = weak(remote_map.get("link").unwrap())
      let changes = []
      remote.observe("watch", fn(_, _) {
        changes.push(remote.try_deref_value().map(@yrs.Out::to_json))
      })
      for n in 0..<3 {
        map.insert("key", Integer(n.to_int64()))
        if v2 {
          peer.apply_update_v2(doc.encode_diff_v2(peer.state_vector()))
        } else {
          peer.apply_update_v1(doc.encode_diff_v1(peer.state_vector()))
        }
        assert_eq(remote.try_deref_value().unwrap().to_json(), Json(n))
        remote_map.remove("key")
        doc.apply_update_v1(peer.encode_state_as_update_v1())
      }
      assert_eq(changes, [
        Some(Json(0)),
        None,
        Some(Json(1)),
        None,
        Some(Json(2)),
        None,
      ])
      assert_true(link.try_deref_value() is None)
      remote_map.remove("link")
      remote_map.insert("key", Integer(9L))
      assert_eq(changes.length(), 6)
    }
  }
}

///|
test "reinserted map links reconnect deep events without observing other keys" {
  let doc = @yrs.Doc(client_id=1UL, skip_gc=false)
  let map = doc.get_or_insert_map("map")
  map.insert_map("key") |> ignore
  let link = weak(map.insert_input("link", WeakLink(map.link("key").unwrap())))
  let events = Ref(0)
  link.observe_deep("deep", fn(_, _) { events.val += 1 })
  map.remove("key")
  let child = map.insert_map("key")
  let before = events.val
  child.insert("nested", Bool(true))
  assert_eq(events.val, before + 1)
  map.insert_map("other").insert("nested", Bool(false))
  assert_eq(events.val, before + 1)
}
