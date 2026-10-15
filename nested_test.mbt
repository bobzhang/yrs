///|
test "nested shared handles retain identity after concurrent child edits" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let root = a.get_or_insert_map("doc")
  let tasks = root.insert_array("tasks")
  let task = tasks.insert_map(0)
  let title = task.insert_text("title")
  title.insert(0, "Ship")
  b.apply_update_v1(a.encode_state_as_update_v1())
  guard b.get_or_insert_map("doc").get("tasks") is Some(Array(other_tasks)) else {
    fail("missing array")
  }
  guard other_tasks.to_array()[0] is Map(other_task) else {
    fail("missing map")
  }
  guard other_task.get("title") is Some(Text(other_title)) else {
    fail("missing text")
  }
  title.insert(4, " Moon")
  other_title.insert(4, " Rust")
  a.apply_update_v1(b.encode_state_as_update_v1())
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(title.get_string(), "Ship Moon Rust")
  assert_eq(root.to_json(), b.get_or_insert_map("doc").to_json())
  root.remove("tasks")
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(other_title.get_string(), "")
  other_title.insert(0, "cannot revive a removed parent")
  assert_eq(other_title.get_string(), "")
  a.apply_update_v1(b.encode_state_as_update_v1())
  assert_true(root.get("tasks") is None)
}
