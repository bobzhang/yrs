///|
test "v2 columns preserve nested documents and incremental deletions" {
  let a = @yrs.Doc(client_id=1234567890123UL)
  let map = a.get_or_insert_map("root")
  let text = map.insert_text("title")
  text.insert(0, "Moon🌍中文")
  let list = map.insert_array("list")
  list.insert_range(0, [Integer(1L), Bool(true), String("hi")])
  let bytes = a.encode_state_as_update_v2()
  let b = @yrs.Doc(client_id=2UL)
  b.apply_update_v2(bytes)
  assert_eq(map.to_json(), b.get_or_insert_map("root").to_json())
  text.remove_range(0, 4)
  list.remove_range(1, 1)
  b.apply_update_v2(a.encode_state_as_update_v2(remote=b.state_vector()))
  assert_eq(map.to_json(), b.get_or_insert_map("root").to_json())
  for len in 0..<bytes.length() {
    try @yrs.convert_update_v2_to_v1(bytes[:len].to_owned()) catch {
      _ => ()
    } noraise {
      _ => fail("accepted truncated v2 update")
    }
  }
  try @yrs.convert_update_v2_to_v1(bytes, max_items=2) catch {
    _ => ()
  } noraise {
    _ => fail("ignored expansion budget")
  }
}
