///|
test "indexed reads cross compacted values deleted gaps and shared children" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("array")
  array.insert_range(0, [Integer(1L), Integer(2L), Integer(3L)])
  array.remove(1)
  array.push_front(Map([("value", Value(String("front")))])) |> ignore
  array.push_back(Text([Inserted(Value(String("back")), [])])) |> ignore
  assert_true(array.get(-1) is None)
  assert_true(array.get(4) is None)
  assert_eq(array.get(0).unwrap().to_json(), { "value": "front" })
  assert_eq(array.get(1).unwrap().to_json(), Json(1))
  assert_eq(array.get(2).unwrap().to_json(), Json(3))
  assert_eq(array.get(3).unwrap().to_json(), Json("back"))
  assert_eq(
    array.iter().map(@yrs.Out::to_json).to_array(),
    array.to_array().map(@yrs.Out::to_json),
  )
}

///|
test "map conveniences preserve identities avoid redundant ops and group clear" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("root")
  assert_true(
    map.try_update("value", Object([("a", Integer(1L)), ("b", Bool(true))])),
  )
  let before = doc.state_vector().encode_v1()
  assert_false(
    map.try_update("value", Object([("b", Bool(true)), ("a", Float(1.0))])),
  )
  assert_eq(doc.state_vector().encode_v1(), before)
  let nested = map.get_or_init_array("nested")
  nested.push_back(Value(String("retained"))) |> ignore
  assert_eq(map.get_or_init_array("nested").to_json(), Json([Json("retained")]))
  let replaced = map.get_or_init_map("nested")
  replaced.insert("x", Integer(7L))
  assert_eq(nested.length(), 0)
  assert_true(map.contains_key("nested"))
  let removed = map.remove_entry("nested").unwrap()
  assert_true(removed.is_deleted())
  assert_eq(removed.to_json(), ({} : Json))
  assert_true(map.remove_entry("nested") is None)
  map.get_or_init_text("text").insert(0, "abc")
  assert_eq(map.length(), 2)
  let events = []
  map.observe("clear", fn(event, _) { events.push(event.keys().length()) })
  map.clear()
  assert_eq(events, [2])
  assert_eq(map.length(), 0)
  assert_eq(map.keys().count(), 0)
  assert_eq(map.values().count(), 0)
}
