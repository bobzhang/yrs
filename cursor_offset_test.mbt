///|
test "Unicode cursors preserve wire identities across byte and UTF16 modes" {
  for value in ["A🦀中文Z", "ééé", "👩‍💻 café", "A\u{feff}B"] {
    let utf = @yrs.Doc(client_id=1UL)
    let bytes = @yrs.Doc(client_id=2UL, offset_kind=Bytes)
    let left = utf.get_or_insert_text("text")
    let right = bytes.get_or_insert_text("text")
    left.insert(0, value)
    bytes.apply_update_v1(utf.encode_state_as_update_v1())
    let positions = [(0, 0)]
    let mut u = 0
    let mut b = 0
    for c in value {
      let n = c.to_int()
      u += if n > 0xffff { 2 } else { 1 }
      b += if n < 128 {
        1
      } else if n < 2048 {
        2
      } else if n < 65536 {
        3
      } else {
        4
      }
      positions.push((u, b))
    }
    let marks = []
    for (u, b) in positions {
      for assoc in [@yrs.Assoc::Before, After] {
        let a = left.sticky_index(u, assoc~)
        let c = right.sticky_index(b, assoc~)
        assert_eq(a, c)
        if a is Some(mark) {
          assert_eq(mark.get_offset(utf).unwrap().index, u)
          assert_eq(mark.get_offset(bytes).unwrap().index, b)
          marks.push((mark, u, b))
        }
      }
    }
    // Split an existing block before every character, then replay it. Cursor
    // resolution must not depend on whether Unicode text is compacted or split.
    for (at, _) in positions.rev() {
      if at < left.length() {
        left.insert(at, "!")
      }
    }
    bytes.apply_update_v2(utf.encode_state_as_update_v2())
    for (mark, _, _) in marks {
      let at = mark.get_offset(utf).unwrap().index
      let prefix = left.get_string()[:at]
      let mut expected = 0
      for c in prefix {
        let n = c.to_int()
        expected += if n < 128 {
          1
        } else if n < 2048 {
          2
        } else if n < 65536 {
          3
        } else {
          4
        }
      }
      assert_eq(mark.get_offset(bytes).unwrap().index, expected)
    }
  }
}

///|
test "byte cursors reject non-boundaries and unrepresentable surrogate positions" {
  let utf = @yrs.Doc(client_id=1UL)
  let bytes = @yrs.Doc(client_id=2UL, offset_kind=Bytes)
  let left = utf.get_or_insert_text("text")
  let right = bytes.get_or_insert_text("text")
  left.insert(0, "🦀")
  bytes.apply_update_v1(utf.encode_state_as_update_v1())
  for at in 1..<4 {
    assert_true(right.sticky_index(at) is None)
    assert_true(right.sticky_index(at, assoc=Before) is None)
  }
  assert_true(left.sticky_index(1).unwrap().get_offset(bytes) is None)
  assert_true(
    left.sticky_index(1, assoc=Before).unwrap().get_offset(bytes) is None,
  )
  assert_eq(
    right.sticky_index(4, assoc=Before).unwrap().get_offset(bytes).unwrap().index,
    4,
  )
}
