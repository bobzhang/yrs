///|
test "event key maps are detached from retained map and XML event snapshots" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("map")
  let xml = doc.get_or_insert_xml_fragment("xml")
  let element = xml.insert_element(0, "p")
  let text = element.as_fragment().insert_text(0)
  let map_events : Array[@yrs.MapEvent] = []
  let element_events : Array[@yrs.XmlEvent] = []
  let text_events : Array[@yrs.XmlTextEvent] = []
  map.observe("keys", fn(event, _) { map_events.push(event) })
  element.observe("keys", fn(event, _) { element_events.push(event) })
  text.observe("keys", fn(event, _) { text_events.push(event) })
  doc.transact(fn(_) {
    map.insert("value", Integer(1L))
    element.insert_attribute("value", Integer(1L))
    text.insert_attribute("value", Integer(1L))
  })
  let first_map = map_events[0].keys()
  let first_element = element_events[0].keys()
  let first_text = text_events[0].keys()
  // Mutating the returned maps must not change the retained event snapshots.
  first_map.clear()
  first_element.clear()
  first_text.clear()
  doc.transact(fn(_) {
    map.insert("value", Integer(2L))
    element.insert_attribute("value", Integer(2L))
    text.insert_attribute("value", Integer(2L))
  })
  assert_eq(map_events.length(), 2)
  assert_eq(element_events.length(), 2)
  assert_eq(text_events.length(), 2)
  for
    keys in [
      map_events[0].keys(),
      element_events[0].keys(),
      text_events[0].keys(),
    ] {
    assert_eq(keys.length(), 1)
    assert_eq(keys["value"].to_json(), { "action": "add", "new_value": 1 })
  }
  for
    keys in [
      map_events[1].keys(),
      element_events[1].keys(),
      text_events[1].keys(),
    ] {
    assert_eq(keys.length(), 1)
    assert_eq(keys["value"].to_json(), {
      "action": "update",
      "old_value": 1,
      "new_value": 2,
    })
  }
  assert_true(first_map.is_empty())
  assert_true(first_element.is_empty())
  assert_true(first_text.is_empty())
}
