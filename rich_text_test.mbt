///|
test "rich text marks, embeds and removals survive both update versions" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("rich")
  text.insert(0, "hello world")
  text.format(0, 5, [("bold", Bool(true))])
  text.insert_with_attributes(5, "!", [("italic", Bool(true))])
  text.insert_embed(6, Object([("image", String("moon.png"))]))
  assert_eq(text.length(), 13)
  assert_eq(text.get_string(), "hello! world")
  let expected : Json = [
    { "insert": "hello", "attributes": { "bold": true } },
    { "insert": "!", "attributes": { "italic": true } },
    { "insert": { "image": "moon.png" }, "attributes": { "italic": true } },
    { "insert": " world" },
  ]
  assert_eq(Json(text.to_delta().map(@yrs.TextChunk::to_json)), expected)
  let b = @yrs.Doc(client_id=2UL)
  b.apply_update_v2(a.encode_state_as_update_v2())
  assert_eq(
    Json(b.get_or_insert_text("rich").to_delta().map(@yrs.TextChunk::to_json)),
    expected,
  )
  text.remove_range(1, 7)
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(text.get_string(), "hworld")
  assert_eq(
    Json(text.to_delta().map(@yrs.TextChunk::to_json)),
    Json(b.get_or_insert_text("rich").to_delta().map(@yrs.TextChunk::to_json)),
  )
}

///|
test "zero length deletion without active attributes preserves format markers" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  text.format(0, 0, [("color", String("red"))])
  text.remove_range(0, 0)
  text.format(0, 0, [("color", String("red"))])
  assert_eq(doc.state_vector().get(1UL), 2U)
  assert_eq(text.get_string(), "")
}

///|
test "unrelated remote update does not clean local formatting gaps" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  text.insert(0, "yz")
  text.format(1, 0, [("bold", Bool(true))])
  let delta = Json(text.to_delta().map(@yrs.TextChunk::to_json))
  let update = doc.encode_state_as_update_v1()
  doc.apply_update_v1(b"\x00\x00")
  assert_eq(Json(text.to_delta().map(@yrs.TextChunk::to_json)), delta)
  assert_eq(doc.encode_state_as_update_v1(), update)
}
