///|
test "text events describe insertion removal and attribute-only changes" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  text.insert(0, "abcd")
  let events : Array[Json] = []
  text.observe("test", fn(event, _) {
    events.push(Json(event.delta().iter().map(@yrs.Delta::to_json).to_array()))
  })
  doc.transact(fn(_) {
    text.format(1, 2, [("bold", Bool(true))])
    text.remove_range(3, 1)
    text.insert_with_attributes(3, "!", [("bold", Bool(true))])
  })
  assert_eq(events.length(), 1)
  assert_eq(events[0], [
    { "retain": 1 },
    { "retain": 2, "attributes": { "bold": true } },
    { "insert": "!", "attributes": { "bold": true } },
    { "delete": 1 },
  ])
  assert_true(text.unobserve("test"))
}

///|
test "array events consolidate grouped operations and suppress transient inserts" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("items")
  array.insert_range(0, [Integer(1L), Integer(2L), Integer(3L)])
  let events : Array[Json] = []
  array.observe("test", fn(event, _) {
    events.push(Json(event.delta().iter().map(@yrs.Change::to_json).to_array()))
  })
  doc.transact(fn(_) {
    array.remove_range(1, 1)
    array.insert_range(1, [Integer(4L), Integer(5L)])
    array.remove_range(2, 1)
  })
  assert_eq(events, [[{ "retain": 1 }, { "delete": 1 }, { "insert": [4] }]])
  assert_true(array.unobserve("test"))
}
