///|
test "XML trees attributes formatting and parents roundtrip in both wire formats" {
  let a = @yrs.Doc(client_id=1UL)
  let root = a.get_or_insert_xml_fragment("article")
  let element = root.insert_element(0, "p")
  element.insert_attribute("class", String("intro"))
  let fragment = element.as_fragment().insert_fragment(0)
  let text = fragment.insert_text(0)
  text.as_text().insert_with_attributes(0, "Moon", [("bold", Bool(true))])
  assert_eq(root.get_string(), "<p class=\"intro\"><bold>Moon</bold></p>")
  assert_true(element.parent() is Some(Fragment(_)))
  assert_true(fragment.parent() is Some(Element(_)))
  assert_true(text.parent() is Some(Fragment(_)))
  assert_true(root.parent() is None)
  for v2 in [false, true] {
    let b = @yrs.Doc(client_id=2UL)
    if v2 {
      b.apply_update_v2(a.encode_state_as_update_v2())
    } else {
      b.apply_update_v1(a.encode_state_as_update_v1())
    }
    assert_eq(
      root.get_string(),
      b.get_or_insert_xml_fragment("article").get_string(),
    )
  }
  element.remove_attribute("class")
  assert_true(element.get_attribute("class") is None)
  root.remove_range(0, 1)
  text.as_text().insert(0, "deleted parent")
  assert_eq(text.get_string(), "")
  assert_eq(root.get_string(), "")
}

///|
test "XML insertion precedes tombstones at the selected boundary" {
  let a = @yrs.Doc(client_id=1UL)
  let root = a.get_or_insert_xml_fragment("article")
  root.insert_element(0, "old") |> ignore
  root.remove_range(0, 1)
  root.insert_element(0, "new") |> ignore
  // The new element has no origin and points right at the deleted old node.
  let expected : Bytes = [
    1, 2, 1, 0, 7, 1, 7, 97, 114, 116, 105, 99, 108, 101, 3, 3, 111, 108, 100, 71,
    1, 0, 3, 3, 110, 101, 119, 1, 1, 1, 0, 1,
  ]
  assert_eq(a.encode_state_as_update_v1(), expected)
}
