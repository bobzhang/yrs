///|
test "adjacent appends compact without changing CRDT clocks or cursor offsets" {
  let doc = Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abc")
  let cursor = text.sticky_index(1).unwrap()
  for _ in 0..<1000 {
    text.insert(text.length(), "x")
  }
  assert_eq(doc.clients[1UL].length(), 1)
  assert_eq(doc.items.length(), 1)
  assert_eq(doc.state_vector().get(1UL), 1003U)
  assert_eq(cursor.get_offset(doc).unwrap().index, 1)
  text.remove_range(1, 2)
  let replica = Doc(client_id=2UL)
  replica.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(replica.get_or_insert_text("text").get_string(), text.get_string())
}

///|
test "compaction preserves origin-based integration after a block splits" {
  let a = Doc(client_id=1UL)
  let b = Doc(client_id=2UL)
  let text = a.get_or_insert_text("text")
  text.insert(0, "a")
  b.apply_update_v1(a.encode_state_as_update_v1())
  text.insert(1, "b")
  text.insert(2, "c")
  b.get_or_insert_text("text").insert(1, "!")
  a.apply_update_v1(b.encode_state_as_update_v1())
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(text.get_string(), b.get_or_insert_text("text").get_string())
  assert_eq(text.get_string(), "abc!")
}
