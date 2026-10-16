///|
test "JSONPath yields live handles and preserves index union order" {
  let doc = @yrs.Doc(client_id=1UL)
  let users = doc.get_or_insert_array("users")
  users.push_back(Map([("name", Value(String("Alice")))])) |> ignore
  users.push_back(Map([("name", Value(String("Bob")))])) |> ignore
  let path = @yrs.JsonPath::parse("$.users[1,0,-1].name")
  assert_eq(doc.json_path(path).map(@yrs.Out::to_json).to_array(), [
    Json("Bob"),
    Json("Alice"),
    Json("Bob"),
  ])
  let matches = doc.json_path(@yrs.JsonPath::parse("$.users[0]")).to_array()
  guard matches[0] is Map(alice) else { fail("expected live map") }
  alice.insert("name", String("Alicia"))
  assert_eq(
    doc
    .json_path(@yrs.JsonPath::parse("$.users[0].name"))
    .map(@yrs.Out::to_json)
    .to_array(),
    [Json("Alicia")],
  )
}

///|
test "JSONPath recursive descent and Unicode names work on immutable and shared values" {
  let value = @yrs.Any::from_json({
    "名字": "MoonBit",
    "éclair": "cake",
    "𐐀letter": "Deseret",
    "list": [{ "children": [{ "name": "a" }, { "name": "b" }] }],
  })
  assert_eq(
    value
    .json_path(@yrs.JsonPath::parse("$.名字"))
    .map(@yrs.Any::to_json)
    .to_array(),
    [Json("MoonBit")],
  )
  assert_eq(
    value
    .json_path(@yrs.JsonPath::parse("$.𐐀letter"))
    .map(@yrs.Any::to_json)
    .to_array(),
    [Json("Deseret")],
  )
  assert_eq(
    value
    .json_path(@yrs.JsonPath::parse("$.list..name"))
    .map(@yrs.Any::to_json)
    .to_array(),
    [Json("a"), Json("b")],
  )
  let doc = @yrs.Doc(client_id=1UL)
  let mut map = doc.get_or_insert_map("root")
  for _ in 0..<1000 {
    map = map.insert_map("child")
  }
  map.insert("needle", Integer(42L))
  assert_eq(
    doc
    .json_path(@yrs.JsonPath::parse("$..needle"))
    .map(@yrs.Out::to_json)
    .to_array(),
    [Json(42)],
  )
}

///|
test "JSONPath handles XML attributes children and untyped imported roots" {
  let doc = @yrs.Doc(client_id=1UL)
  let xml = doc.get_or_insert_xml_fragment("xml")
  let element = xml.insert_element(0, "p")
  element.insert_attribute("class", String("lead"))
  element.as_fragment().insert_text(0).as_text().push("hello")
  assert_eq(
    doc
    .json_path(@yrs.JsonPath::parse("$.xml[0].class"))
    .map(@yrs.Out::to_json)
    .to_array(),
    [Json("lead")],
  )
  assert_eq(
    doc
    .json_path(@yrs.JsonPath::parse("$.xml[0][0]"))
    .map(@yrs.Out::to_json)
    .to_array(),
    [Json("hello")],
  )
  let root = doc.get_or_insert_map("root")
  root
  .insert_array("items")
  .insert_range(0, [Integer(1L), Integer(2L), Integer(3L)])
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(
    peer
    .json_path(@yrs.JsonPath::parse("$.root.items[0:3:2]"))
    .map(@yrs.Out::to_json)
    .to_array(),
    [Json(1), Json(3)],
  )
}

///|
test "JSONPath rejects unsafe slice steps and malformed expressions" {
  for path in ["$[::0]", "$[1", "$.", "$[?(@.x)]", "$['a',2]"] {
    try @yrs.JsonPath::parse(path) catch {
      @yrs.JsonPathError::InvalidJsonPath(_) => ()
    } noraise {
      _ => fail("invalid path accepted")
    }
  }
  let value = @yrs.Any::from_json({ "items": [1, 2] })
  assert_eq(
    value.json_path(@yrs.JsonPath::parse("$.items[100:101]")).count(),
    0,
  )
}
