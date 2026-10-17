///|
fn position_boundaries(text : Text) -> Array[Int32] {
  if text.doc.offset_kind() == Utf16 {
    return Array::makei(text.length() + 1, fn(i) { i })
  }
  let result = [0]
  let mut index = 0
  for c in text.get_string() {
    index += utf8_width(c)
    result.push(index)
  }
  result
}

///|
fn check_position_hint(text : Text) -> Unit raise {
  let branch = text.doc.branch(text.name)
  let mut expected = 0
  let mut scan = branch.head
  while scan is Some(id) {
    let item = text.doc.items[id]
    if !item.deleted {
      expected += item.content.offset_length(text.doc)
    }
    scan = item.right
  }
  assert_eq(text.length(), expected)
  guard branch.position_hint is Some((hint, offset)) else { return }
  assert_false(hint.deleted)
  assert_eq(text.doc.items[hint.id].id, hint.id)
  let mut cursor = branch.head
  let mut index = 0
  while cursor is Some(id) {
    let item = text.doc.items[id]
    if id == hint.id {
      assert_eq(offset, index)
      return
    }
    if !item.deleted {
      index += item.content.offset_length(text.doc)
    }
    cursor = item.right
  }
  fail("position hint is detached from its sequence")
}

///|
test "cached positions match uncached histories across offsets GC and remote edits" {
  for offset_kind in [Utf16, Bytes] {
    for skip_gc in [false, true] {
      let cached = Doc(client_id=1UL, offset_kind~, skip_gc~)
      let uncached = Doc(client_id=1UL, offset_kind~, skip_gc~)
      let remote = Doc(client_id=2UL, offset_kind~, skip_gc~)
      let text = cached.get_or_insert_text("text")
      let control = uncached.get_or_insert_text("text")
      let peer = remote.get_or_insert_text("text")
      let packets : Array[Bytes] = []
      let expected_packets : Array[Bytes] = []
      cached.observe_update_v1("packets", fn(bytes, _) { packets.push(bytes) })
      uncached.observe_update_v1("packets", fn(bytes, _) {
        expected_packets.push(bytes)
      })
      let mut random = 941U
      fn choose(n : Int32) -> Int32 {
        random = random * 1664525U + 1013904223U
        ((random >> 8) % n.reinterpret_as_uint()).reinterpret_as_int()
      }
      for step in 0..<1600 {
        let boundaries = position_boundaries(text)
        let at = choose(boundaries.length())
        let index = boundaries[at]
        let end = boundaries[at + choose(boundaries.length() - at)]
        uncached.branch(control.name).position_hint = None
        match step % 11 {
          0 => {
            remote.apply_update_v1(cached.encode_state_as_update_v1())
            peer.insert(index, "R")
            let update = remote.encode_state_as_update_v1(
              remote=cached.state_vector(),
            )
            cached.apply_update_v1(update)
            uncached.apply_update_v1(update)
          }
          3 | 5 | 9 => {
            text.remove_range(index, end - index)
            control.remove_range(index, end - index)
          }
          _ => {
            let value = ["a", "xy", "世", "🌙", "é"][choose(5)]
            text.insert(index, value)
            control.insert(index, value)
          }
        }
        check_position_hint(text)
        assert_eq(text.get_string(), control.get_string())
        assert_eq(
          cached.encode_state_as_update_v1(),
          uncached.encode_state_as_update_v1(),
        )
        assert_eq(packets, expected_packets)
        packets.clear()
        expected_packets.clear()
      }
      assert_eq(
        cached.encode_state_as_update_v2(),
        uncached.encode_state_as_update_v2(),
      )
    }
  }
}

///|
test "cached exact boundaries preserve tombstones and formatted fallback" {
  let cached = Doc(client_id=1UL)
  let uncached = Doc(client_id=1UL)
  for doc in [cached, uncached] {
    let text = doc.get_or_insert_text("text")
    text.insert(0, "abcdef")
    text.remove_range(1, 3)
    text.insert(1, "X")
  }
  let text = cached.get_or_insert_text("text")
  let control = uncached.get_or_insert_text("text")
  check_position_hint(text)
  uncached.branch(control.name).position_hint = None
  text.remove_range(1, 1)
  control.remove_range(1, 1)
  assert_eq(
    cached.encode_state_as_update_v1(),
    uncached.encode_state_as_update_v1(),
  )
  for doc in [cached, uncached] {
    let body = doc.get_or_insert_text("text")
    body.insert(1, "Q")
    if doc.identity == uncached.identity {
      doc.branch(body.name).position_hint = None
    }
    body.format(0, 2, [("bold", Bool(true))])
    body.insert_with_attributes(2, "z", [("italic", Bool(true))])
    body.insert(1, "!")
    body.remove_range(1, 2)
  }
  assert_eq(
    cached.encode_state_as_update_v1(),
    uncached.encode_state_as_update_v1(),
  )
  assert_eq(
    text.to_delta().map(TextChunk::to_json),
    control.to_delta().map(TextChunk::to_json),
  )
}
