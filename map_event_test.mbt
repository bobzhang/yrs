///|
test "map events report transaction-level old and new entries" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("settings")
  map.insert("count", Integer(1L))
  let changes : Array[Json] = []
  map.observe("test", fn(event, _) { changes.push(event.to_json()) })
  doc.transact(fn(_) {
    map.insert("count", Integer(2L))
    map.insert("count", Integer(3L))
    map.insert("temporary", Bool(true))
    map.remove("temporary")
    map.insert("name", String("Moon"))
  })
  assert_eq(changes.length(), 1)
  assert_eq(changes[0], {
    "count": { "action": "update", "old_value": 1, "new_value": 3 },
    "name": { "action": "add", "new_value": "Moon" },
  })
  map.remove("name")
  assert_eq(changes[1], { "name": { "action": "delete", "old_value": "Moon" } })
  map.remove("missing")
  assert_eq(changes.length(), 2)
  assert_true(map.unobserve("test"))
  // Yrs drains cancelled entries at the next dispatch or subscription.
  assert_true(map.unobserve("test"))
}

///|
test "new and deleted nested maps suppress their own observers" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("settings")
  let events : Array[Json] = []
  let nested = doc.transact(fn(_) {
    let nested = root.insert_map("child")
    nested.observe("test", fn(e, _) { events.push(e.to_json()) })
    nested.insert("value", Integer(1L))
    nested
  })
  assert_eq(events.length(), 0)
  nested.insert("value", Integer(2L))
  assert_eq(events, [
    { "value": { "action": "update", "old_value": 1, "new_value": 2 } },
  ])
  root.remove("child")
  assert_eq(events.length(), 1)
  nested.insert("value", Integer(3L))
  assert_eq(events.length(), 1)
}
