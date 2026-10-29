///|
test "array added runs keep ordering and frozen values across later commits" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("items")
  let events : Array[ReadOnlyArray[@yrs.Change]] = []
  array.observe("snapshot", fn(event, _) { events.push(event.delta()) })
  doc.transact(fn(_) {
    for i in 0..<64 {
      array.insert_range(0, [Integer(i.to_int64())])
    }
  })
  assert_eq(events.length(), 1)
  let expected : Array[Json] = [ for i in 0..<64 => Json(63 - i) ]
  assert_eq(Json(events[0].iter().map(@yrs.Change::to_json).to_array()), [
    { "insert": Json(expected) },
  ])
  array.remove_range(0, 64)
  array.insert_range(0, [Integer(1000L)])
  assert_eq(Json(events[0].iter().map(@yrs.Change::to_json).to_array()), [
    { "insert": Json(expected) },
  ])
}

///|
test "array added runs flush at retained and removed boundaries" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("items")
  array.insert_range(0, [Integer(10L), Integer(20L), Integer(30L), Integer(40L)])
  let events : Array[ReadOnlyArray[@yrs.Change]] = []
  array.observe("snapshot", fn(event, _) { events.push(event.delta()) })
  doc.transact(fn(_) {
    array.insert_range(0, [Integer(0L)])
    array.insert_range(1, [Integer(1L)])
    array.remove_range(3, 1)
    array.insert_range(3, [Integer(2L)])
    array.insert_range(4, [Integer(3L)])
    array.remove_range(5, 1)
    array.insert_range(5, [Integer(4L)])
    array.insert_range(6, [Integer(5L)])
  })
  assert_eq(events.length(), 1)
  assert_eq(Json(events[0].iter().map(@yrs.Change::to_json).to_array()), [
    { "insert": [0, 1] },
    { "retain": 1 },
    { "delete": 1 },
    { "insert": [2, 3] },
    { "delete": 1 },
    { "insert": [4, 5] },
  ])
}

///|
test "array events preserve empty added runs for character wire content" {
  let source = @yrs.Doc(client_id=1UL)
  source.get_or_insert_text("shared").insert(0, "text")
  let doc = @yrs.Doc(client_id=2UL)
  let array = doc.get_or_insert_array("shared")
  let events : Array[Json] = []
  array.observe("wire", fn(event, _) {
    events.push(Json(event.delta().iter().map(@yrs.Change::to_json).to_array()))
  })
  doc.apply_update_v1(source.encode_state_as_update_v1())
  assert_eq(events, [[{ "insert": [] }]])
}
