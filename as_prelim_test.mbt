///|
struct CopyableParagraph {
  text : @yrs.Text
}

///|
impl @yrs.AsPrelim for CopyableParagraph with fn to_input(self) {
  self.text.to_input()
}

///|
fn[T : @yrs.AsPrelim] detached(value : T) -> @yrs.In {
  value.to_input()
}

///|
test "generic preliminary copies retain rich text and nested values independently" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("body")
  text.insert_with_attributes(0, "hello", [("bold", Bool(true))])
  let embed = text.insert_embed_input(
    5,
    Map([("answer", Value(Integer(9223372036854775807L)))]),
    attributes=[],
  )
  let paragraph = CopyableParagraph::{ text, }
  let frozen = detached(paragraph)
  text.insert(0, "changed ")
  guard embed is Map(original) else { fail("embed") }
  original.insert("answer", Integer(0L))
  let target = @yrs.Doc(client_id=2UL)
  let root = target.get_or_insert_map("copies")
  guard root.insert_input("body", frozen) is Text(copy) else { fail("copy") }
  assert_eq(copy.get_string(), "hello")
  let delta = copy.to_delta()
  assert_eq(delta[0].attributes.iter().to_array(), [
    ("bold", @yrs.Any::Bool(true)),
  ])
  guard delta[1].insert is Map(map) else { fail("copied embed") }
  let answer : Int64 = map.get_as("answer")
  assert_eq(answer, 9223372036854775807L)
  let nested = source.get_or_insert_array("nested")
  nested.insert_map(0).insert("buffer", Buffer(b"\x00\xff"))
  let map_copy = detached(original)
  let array_copy = detached(nested)
  root.insert_input("map", map_copy) |> ignore
  root.insert_input("array", array_copy) |> ignore
  nested.remove(0)
  original.insert("answer", Integer(1L))
  for v2 in [false, true] {
    let received = @yrs.Doc(client_id=3UL)
    if v2 {
      received.apply_update_v2(target.encode_state_as_update_v2())
    } else {
      received.apply_update_v1(target.encode_state_as_update_v1())
    }
    assert_eq(received.get_or_insert_map("copies").to_json(), root.to_json())
  }
}

///|
test "generic XML copies preserve attributes and weak inputs preserve source identities" {
  let doc = @yrs.Doc(client_id=1UL)
  let xml = doc.get_or_insert_xml_fragment("xml")
  let element = xml.insert_element(0, "p")
  element.insert_attribute("class", String("entry"))
  let text = element.as_fragment().insert_text(0)
  text.as_text().insert_with_attributes(0, "hello", [("bold", Bool(true))])
  text.insert_attribute("lang", String("en"))
  let values = doc.get_or_insert_array("copies")
  values.push_back(detached(xml)) |> ignore
  values.push_back(detached(element)) |> ignore
  values.push_back(detached(text)) |> ignore
  values.push_back(detached(@yrs.XmlNode::Element(element))) |> ignore
  element.insert_attribute("class", String("changed"))
  text.insert_attribute("lang", String("fr"))
  guard values.get(0) is Some(XmlFragment(fragment)) &&
    values.get(1) is Some(XmlElement(copied_element)) &&
    values.get(2) is Some(XmlText(copied_text)) &&
    values.get(3) is Some(XmlElement(copied_node)) else {
    fail("copied types")
  }
  assert_eq(
    copied_element.get_attribute("class").map(@yrs.Out::to_json),
    Some(Json("entry")),
  )
  assert_eq(
    copied_text.get_attribute("lang").map(@yrs.Out::to_json),
    Some(Json("en")),
  )
  assert_eq(copied_element.get_string(), copied_node.get_string())
  assert_eq(fragment.get_string(), copied_element.get_string())
  let source = doc.get_or_insert_text("source")
  source.insert(0, "quoted")
  let links = doc.get_or_insert_map("links")
  guard links.insert_input("a", WeakLink(source.quote(Unbounded, Unbounded)))
    is WeakLink(link) else {
    fail("weak link")
  }
  guard links.insert_input("b", detached(link)) is WeakLink(copy) else {
    fail("copied link")
  }
  assert_eq(copy.source(), link.source())
  source.insert(0, "still ")
  assert_eq(copy.get_string(), link.get_string())
  values.push_back(detached(@yrs.Any::Bool(true))) |> ignore
  assert_eq(values.get(4).unwrap().to_json(), Json(true))
}
