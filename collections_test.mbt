///|
test "arrays split value runs and exchange concurrent updates" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let x = a.get_or_insert_array("items")
  let y = b.get_or_insert_array("items")
  x.insert_range(0, [Integer(1L), Integer(2L), Integer(3L)])
  b.apply_update_v1(a.encode_state_as_update_v1())
  x.insert_range(1, [String("moon")])
  y.remove_range(0, 2)
  a.apply_update_v1(b.encode_state_as_update_v1())
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(x.to_json(), Json::array([Json("moon"), Json(3)]))
  assert_eq(x.to_json(), y.to_json())
}

///|
test "concurrent maps converge and deletion does not revive overwritten values" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let x = a.get_or_insert_map("settings")
  let y = b.get_or_insert_map("settings")
  x.insert("theme", String("light"))
  y.insert("theme", String("dark"))
  a.apply_update_v1(b.encode_state_as_update_v1())
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(x.get("theme").unwrap().to_json(), Json("dark"))
  assert_eq(x.to_json(), y.to_json())
  x.remove("theme")
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_true(y.get("theme") is None)
  y.insert("theme", String("blue"))
  a.apply_update_v1(b.encode_state_as_update_v1())
  assert_eq(x.get("theme").unwrap().to_json(), Json("blue"))
}
