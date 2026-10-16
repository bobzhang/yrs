///|
test "typed logical handles resolve across replicas and reject deleted children" {
  let root : @yrs.Root[@yrs.MapRef] = Root("root")
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  assert_true(root.get(a) is None)
  let map = root.get_or_create(a)
  assert_eq(map.hook(), root.hook())
  let text = map.insert_text("note")
  text.insert(0, "Moon🌙")
  let handle = text.hook()
  let nested = handle.into_nested().unwrap()
  assert_true(handle.into_root() is None)
  assert_true(root.hook().into_nested() is None)
  assert_eq(root.hook().into_root().unwrap(), root)
  assert_true(handle.get(b) is None)
  b.apply_update_v2(a.encode_state_as_update_v2())
  assert_eq(handle.get(b).unwrap().get_string(), "Moon🌙")
  assert_eq(nested.get(b).unwrap().get_string(), "Moon🌙")
  assert_eq(@yrs.Nested::Nested(nested.id), nested)
  assert_eq(@yrs.Hook::Hook(handle.id()), handle)
  // Handles track an identity, not the map key that once contained it.
  map.remove("note")
  let replacement = map.insert_text("note")
  replacement.insert(0, "new")
  assert_true(handle.get(a) is None)
  assert_true(nested.get(a) is None)
  assert_true(replacement.hook() != handle)
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_true(handle.get(b) is None)
  assert_eq(replacement.hook().get(b).unwrap().get_string(), "new")
  a.gc()
  assert_true(handle.get(a) is None)
}

///|
test "logical handles cover arrays XML weak links and undeclared roots" {
  let doc = @yrs.Doc(client_id=1UL)
  let array_root : @yrs.Root[@yrs.ArrayRef] = Root("array")
  let array = array_root.get_or_create(doc)
  array.insert_range(0, [Integer(7L)])
  assert_eq(array.hook().get(doc).unwrap().to_json(), Json([7]))
  let text_root : @yrs.Root[@yrs.Text] = Root("text")
  let text = text_root.get_or_create(doc)
  text.insert(0, "abc")
  let xml_root : @yrs.Root[@yrs.XmlFragment] = Root("xml")
  let xml = xml_root.get_or_create(doc)
  let element = xml.insert_element(0, "p")
  let child = element.as_fragment().insert_text(0)
  child.as_text().insert(0, "hello")
  let nested = xml.insert_fragment(1)
  let link = weak(
    doc
    .get_or_insert_map("links")
    .insert_input("link", WeakLink(text.quote(Unbounded, Unbounded))),
  )
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(text_root.get(peer).unwrap().get_string(), "abc")
  assert_eq(xml_root.get(peer).unwrap().get_string(), "<p>hello</p>")
  assert_eq(element.hook().get(peer).unwrap().tag(), "p")
  assert_eq(child.hook().get(peer).unwrap().get_string(), "hello")
  assert_eq(nested.hook().get(peer).unwrap().get_string(), "")
  assert_eq(link.hook().get(peer).unwrap().get_string(), "abc")
  xml.remove_range(0, 2)
  assert_true(element.hook().get(doc) is None)
  assert_true(child.hook().get(doc) is None)
  assert_true(nested.hook().get(doc) is None)
}

///|
test "logical handle JSON preserves identities and matches Rust phantom tags" {
  let root : @yrs.Hook[@yrs.MapRef] = Hook(Root("notes🌙"))
  assert_eq(root.to_json(), {
    "id": { "Root": "notes🌙" },
    "_tag": Json::null(),
  })
  let id : @yrs.Id = { client: 9007199254740991UL, clock: 0xffffffffU, }
  let nested : @yrs.Hook[@yrs.Text] = Hook(Nested(id))
  let decoded : @yrs.Hook[@yrs.Text] = @yrs.Hook::from_json(nested.to_json())
  assert_eq(decoded, nested)
  let table : Map[@yrs.Hook[@yrs.Text], Int32] = Map([])
  table[nested] = 42
  assert_eq(table.get(decoded), Some(42))
  let largest : @yrs.Id = { client: 0xffffffffffffffffUL, clock: 0xffffffffU, }
  assert_eq(
    @yrs.Id::from_json(@json.parse(largest.to_json().stringify())),
    largest,
  )
  for
    value in [
      Json::null(),
      { "id": { "Root": "x" } },
      { "id": { "Root": "x" }, "_tag": 1 },
      { "id": { "Root": 1 }, "_tag": Json::null() },
      {
        "id": { "Root": "x", "Nested": { "client": 1, "clock": 0 } },
        "_tag": Json::null(),
      },
      { "id": { "Nested": { "client": -1, "clock": 0 } }, "_tag": Json::null() },
      {
        "id": { "Nested": { "client": 1, "clock": 4294967296.0 } },
        "_tag": Json::null(),
      },
    ] {
    try {
      let _ : @yrs.Hook[@yrs.Text] = @yrs.Hook::from_json(value)
    } catch {
      _ => ()
    } noraise {
      _ => fail("invalid handle accepted")
    }
  }
}
