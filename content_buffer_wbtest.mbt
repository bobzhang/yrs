///|
test "content appends reuse storage but never extend saved views" {
  let seed = ContentBuffer([0])
  let mut current = seed
  let saved = []
  for i in 1..<10001 {
    if i % 1000 == 0 {
      saved.push(current)
    }
    current = current.joined(ContentBuffer([i]))
  }
  // This would stay at one if each merge copied the growing prefix.
  assert_eq(seed.data.length(), 10001)
  assert_eq(seed.length(), 1)
  assert_eq(seed.iter().to_array(), [0])
  for view in saved {
    assert_eq(view.iter().count(), view.count)
    assert_eq(view[view.count - 1], view.count - 1)
  }
  let fork = seed.joined(ContentBuffer([99]))
  assert_eq(fork.iter().to_array(), [0, 99])
  assert_eq(current[1], 1)
  let doubled = current.joined(current)
  assert_eq(doubled.length(), 20002)
  assert_eq(current.length(), 10001)
  assert_eq(doubled[10002], 1)
  let tiny = doubled.slice(10000, 10002)
  assert_eq(tiny.data.length(), 2)
  assert_eq(tiny.iter().to_array(), [10000, 0])
}

///|
// Independent character-walking oracle, including orphaned UTF-16 halves.
fn slice_reference(text : String, start : Int32, end : Int32) -> String {
  if start == end {
    return ""
  }
  let builder = StringBuilder()
  let mut clock = 0
  for c in text {
    let width = if c.to_int() > 0xffff { 2 } else { 1 }
    if clock >= start && clock + width <= end {
      builder.write_char(c)
    } else if clock < end && clock + width > start {
      builder.write_char('\ufffd')
    }
    clock += width
  }
  builder.to_string()
}

///|
test "text buffers preserve surrogate cuts and immutable rendered snapshots" {
  let seed = TextContent("a😀")
  let mut current = seed
  let mut expected = "a😀"
  for s in ["界", "🦀", "é", "z", "😀"] {
    current = current.joined(TextContent(s))
    expected += s
  }
  assert_eq(seed.text(), "a😀")
  assert_eq(seed.units.data.length(), expected.length())
  for start in 0..<(expected.length() + 1) {
    for end in start..<(expected.length() + 1) {
      let slice = current.slice(start, end)
      let reference = slice_reference(expected, start, end)
      assert_eq(slice.text(), reference)
      assert_eq(slice.length(), end - start)
      assert_eq(slice.utf8_length, @utf8.encode(reference).length())
    }
  }
  let left = current.slice(0, 2)
  let right = current.slice(2, current.length())
  assert_eq(left.joined(right).text(), "a��界🦀éz😀")
  assert_eq(current.text(), expected)
  assert_eq(seed.joined(TextContent("!")).text(), "a😀!")
}

///|
test "retained array and text updates own bounded content after future appends" {
  let doc = Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  let array = doc.get_or_insert_array("array")
  let retained = []
  doc.observe_after_transaction("retain", fn(txn) { retained.push(txn) })
  text.insert(0, "😀")
  array.insert_range(0, [Integer(7L)])
  for i in 0..<100 {
    text.insert(text.length(), "x")
    array.insert_range(array.length(), [Integer(i.to_int64())])
  }
  for v2 in [false, true] {
    let peer = Doc(client_id=2UL)
    for i in 0..<2 {
      if v2 {
        peer.apply_update_v2(retained[i].encode_update_v2())
      } else {
        peer.apply_update_v1(retained[i].encode_update_v1())
      }
    }
    assert_eq(peer.get_or_insert_text("text").get_string(), "😀")
    assert_eq(peer.get_or_insert_array("array").length(), 1)
  }
}

///|
test "owned content snapshots do not pin future append allocations" {
  let saved = TextContent("old")
  Characters(saved).freeze_storage()
  let mut current = saved
  for _ in 0..<1000 {
    current = current.joined(TextContent("x"))
  }
  assert_eq(saved.units.data.length(), 3)
  assert_eq(saved.text(), "old")
  assert_eq(current.length(), 1003)
  let values = ContentBuffer([Any::Integer(1L)])
  Values(values).freeze_storage()
  let appended = values.joined(ContentBuffer([Any::Integer(2L)]))
  assert_eq(values.data.length(), 1)
  assert_eq(appended.length(), 2)
}

///|
test "indexed reads address a packed array block without materializing its contents" {
  let doc = Doc(client_id=1UL)
  let array = doc.get_or_insert_array("array")
  let size = 50000
  array.insert_range(0, Array::makei(size, fn(i) { Integer(i.to_int64()) }))
  assert_eq(doc.clients[1UL].length(), 1)
  for i in 0..<size {
    let index = i * 7919 % size
    assert_true(array.get(index) == Some(Value(Integer(index.to_int64()))))
  }
  assert_true(array.get(-1) is None)
  assert_true(array.get(size) is None)
  array.remove_range(5, size - 10)
  assert_true(array.get(4) == Some(Value(Integer(4L))))
  assert_true(array.get(5) == Some(Value(Integer((size - 5).to_int64()))))
}
