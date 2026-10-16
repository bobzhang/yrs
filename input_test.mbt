///|
test "nested input trees create independent shared collections in one transaction" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let updates : Array[Bytes] = []
  doc.observe_update_v1("updates", fn(u, _) { updates.push(u) })
  let value = root.insert_input(
    "row",
    Map([
      ("title", Text([Inserted(Value(String("hello")), [])])),
      (
        "list",
        Array([Value(Integer(42L)), Map([("done", Value(Bool(false)))])]),
      ),
    ]),
  )
  assert_eq(updates.length(), 1)
  let copy = root.insert_input("copy", value.to_input())
  guard value is Map(original) && original.get("title") is Some(Text(title)) else {
    abort("title")
  }
  title.insert(5, "!")
  guard copy is Map(copied) && copied.get("title") is Some(Text(title)) else {
    abort("copy")
  }
  assert_eq(title.get_string(), "hello")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(doc.encode_state_as_update_v2())
  assert_eq(peer.get_or_insert_map("root").to_json(), root.to_json())
}

///|
test "apply delta combines formatting, replacement and shared embeds" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.apply_delta([
    Inserted(Value(String("hello world")), [("bold", Bool(true))]),
  ])
  text.apply_delta([
    Retain(6, [("bold", Null)]),
    Deleted(5),
    Inserted(Value(String("MoonBit")), []),
    Inserted(Map([("kind", Value(String("mention")))]), []),
  ])
  assert_eq(text.get_string(), "hello MoonBit")
  assert_eq(text.length(), 14)
  guard text.to_delta().last() is Some({ insert: Map(embed), .. }) else {
    abort("shared embed")
  }
  assert_eq(embed.to_json().stringify(), "{\"kind\":\"mention\"}")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(peer.get_or_insert_text("text").length(), 14)
}

///|
test "input delta applies byte offsets and preserves independent XML copies" {
  let doc = @yrs.Doc(client_id=1UL, offset_kind=Bytes)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "世🦀z")
  text.apply_delta([
    Retain(3, []),
    Deleted(4),
    Inserted(Value(String("界")), []),
  ])
  assert_eq(text.get_string(), "世界z")
  let nodes = doc.get_or_insert_array("nodes")
  let xml = nodes.insert(
    0,
    XmlElement("p", [("class", Value(String("entry")))], [
      XmlText([Inserted(Value(String("hello")), [])], []),
    ]),
  )
  nodes.insert(1, xml.to_input()) |> ignore
  guard xml is XmlElement(element) else { abort("element") }
  element.insert_attribute("class", String("changed"))
  guard nodes.to_array()[1] is XmlElement(copy) else { abort("copy") }
  assert_eq(copy.get_string(), "<p class=\"entry\">hello</p>")
}

///|
test "delta deletion cleans formatting even with empty starting attributes" {
  let doc = @yrs.Doc(client_id=2UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "ab")
  text.format(1, 1, [("bold", Bool(true))])
  let changes : Array[Json] = []
  text.observe("event", fn(e, _) {
    changes.push(Json(e.delta().iter().map(@yrs.Delta::to_json).to_array()))
  })
  text.apply_delta([
    Retain(0, []),
    Deleted(1),
    Inserted(Value(String("界🦀")), [("bold", Bool(false))]),
  ])
  assert_eq(doc.state_vector().get(2UL), 8U)
  assert_eq(
    changes[0].stringify(),
    "[{\"delete\":1},{\"insert\":\"界🦀\",\"attributes\":{\"bold\":false}},{\"retain\":1,\"attributes\":{\"bold\":true}}]",
  )
}

///|
test "shared text embeds return live handles and distinguish inherited attributes" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert_with_attributes(0, "ab", [("bold", Bool(true))])
  let embedded = text.insert_embed_input(
    1,
    Map([("answer", Value(Integer(42L)))]),
  )
  guard embedded is Map(map) else { fail("expected shared embed") }
  map.insert("answer", Integer(43L))
  assert_eq(text.length(), 3)
  assert_eq(text.get_string(), "ab")
  assert_eq(text.to_delta()[1].attributes.iter().to_array(), [
    ("bold", @yrs.Any::Bool(true)),
  ])
  text.insert_embed(2, String("one atom"), attributes=[])
  assert_eq(text.length(), 4)
  assert_eq(text.get_string(), "ab")
  assert_eq(text.to_delta()[2].attributes.iter().to_array(), [])
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(doc.encode_state_as_update_v2())
  let received = peer.get_or_insert_text("text")
  assert_eq(received.length(), 4)
  assert_eq(
    received.to_delta().map(@yrs.TextChunk::to_json),
    text.to_delta().map(@yrs.TextChunk::to_json),
  )
  text.remove_range(1, 1)
  assert_true(embedded.is_deleted())
}

///|
test "output strings preserve quoted text and nested integer and binary values" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "hello MoonBit")
  let map = doc.get_or_insert_map("root")
  let quote = map.insert_input(
    "quote",
    WeakLink(text.quote(Included(6), Unbounded)),
  )
  assert_eq(quote.to_string(), "MoonBit")
  let array = doc.get_or_insert_array("values")
  array.push_back(Value(Integer(9223372036854775807L))) |> ignore
  array.push_back(Value(Buffer(b"\x00\xff"))) |> ignore
  assert_eq(@yrs.Out::Array(array).to_string(), "[9223372036854775807, 0x00ff]")
}
