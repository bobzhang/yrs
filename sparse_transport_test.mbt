///|
test "sparse integrated items relay through transaction and state-vector updates" {
  for prefix in [0, 2] {
    for v2 in [false, true] {
      for skip_gc in [false, true] {
        let source = @yrs.Doc(client_id=1UL, skip_gc~)
        if prefix > 0 {
          source.get_or_insert_text("base").insert(0, "ab")
        }
        let base = source.encode_state_as_update_v1()
        source.get_or_insert_text("unrelated").insert(0, "x")
        let missing = source.encode_state_as_update_v1()
        let cut = source.state_vector()
        source.get_or_insert_text("ready").insert(0, "abc")
        source.get_or_insert_map("root").insert_text("child").insert(0, "def")
        let peer = @yrs.Doc(client_id=2UL, skip_gc~)
        peer.apply_update_v1(base)
        let packets = []
        if v2 {
          peer.observe_update_v2("relay", fn(bytes, _) { packets.push(bytes) })
        } else {
          peer.observe_update_v1("relay", fn(bytes, _) { packets.push(bytes) })
        }
        if v2 {
          peer.apply_update_v2(source.encode_diff_v2(cut))
        } else {
          peer.apply_update_v1(source.encode_diff_v1(cut))
        }
        assert_eq(peer.get_or_insert_text("ready").get_string(), "abc")
        assert_eq(peer.state_vector().get(1UL), prefix.reinterpret_as_uint())
        let remote = @yrs.StateVector(entries=[
          (1UL, prefix.reinterpret_as_uint()),
        ])
        let diff = if v2 {
          peer.encode_diff_v2(remote)
        } else {
          peer.encode_diff_v1(remote)
        }
        let state = if v2 {
          peer.encode_state_as_update_v2(remote~)
        } else {
          peer.encode_state_as_update_v1(remote~)
        }
        assert_eq(packets.length(), 1)
        for packet in [packets[0], diff, state] {
          let target = @yrs.Doc(client_id=3UL, skip_gc~)
          target.apply_update_v1(base)
          if v2 {
            target.apply_update_v2(packet)
          } else {
            target.apply_update_v1(packet)
          }
          assert_eq(target.get_or_insert_text("ready").get_string(), "abc")
          guard target.get_or_insert_map("root").get("child")
            is Some(Text(child)) else {
            fail("lost nested sparse content")
          }
          assert_eq(child.get_string(), "def")
          target.apply_update_v1(missing)
          assert_eq(target.get_or_insert_text("ready").get_string(), "abc")
        }
        if v2 {
          peer.apply_update_v2(source.encode_diff_v2(cut))
        } else {
          peer.apply_update_v1(source.encode_diff_v1(cut))
        }
        assert_eq(packets.length(), 1)
      }
    }
  }
}

///|
test "relative and nested cursors resolve integrated anchors beyond clock gaps" {
  for v2 in [false, true] {
    let source = @yrs.Doc(client_id=1UL)
    source.get_or_insert_text("missing").insert(0, "x")
    let prefix = source.encode_state_as_update_v1()
    let cut = source.state_vector()
    source.get_or_insert_text("ready").insert(0, "abc")
    source.get_or_insert_map("root").insert_text("child").insert(0, "def")
    let peer = @yrs.Doc(client_id=2UL)
    if v2 {
      peer.apply_update_v2(source.encode_diff_v2(cut))
    } else {
      peer.apply_update_v1(source.encode_diff_v1(cut))
    }
    let cursor = peer.get_or_insert_text("ready").sticky_index(1).unwrap()
    guard peer.get_or_insert_map("root").get("child") is Some(Text(child)) else {
      fail("missing child")
    }
    let boundary = child.sticky_boundary()
    let unknown = @yrs.StickyIndex(scope=Relative({ client: 1UL, clock: 0U, }))
    assert_true(unknown.get_offset(peer) is None)
    assert_eq(cursor.get_offset(peer).unwrap().index, 1)
    assert_eq(boundary.get_offset(peer).unwrap().index, 3)
    peer.apply_update_v1(prefix)
    assert_eq(cursor.get_offset(peer).unwrap().index, 1)
    assert_eq(boundary.get_offset(peer).unwrap().index, 3)
  }
}
