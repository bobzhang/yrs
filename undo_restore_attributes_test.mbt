///|
test "undo-restored XML attributes survive saving and remote integration" {
  let doc = @yrs.Doc(client_id=1UL)
  let xml = doc.get_or_insert_xml_fragment("xml")
  let element = xml.insert_element(0, "p")
  let text = element.as_fragment().insert_text(0)
  text.as_text().insert(0, "hello")
  text.insert_attribute("lang", String("en"))
  let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
  manager.expand_scope(XmlFragment(xml))
  // One capture group overwrites a map entry and then deletes its parent.
  text.insert_attribute("lang", String("fr"))
  xml.remove_range(0, 1)
  assert_true(manager.undo())
  guard xml.get(0) is Some(Element(restored_element)) else { fail("element") }
  guard restored_element.as_fragment().get(0) is Some(Text(restored)) else {
    fail("text")
  }
  assert_eq(restored.get_attribute("lang").unwrap().to_json(), Json("en"))
  for v2 in [false, true] {
    let peer = @yrs.Doc(client_id=2UL)
    if v2 {
      peer.apply_update_v2(doc.encode_state_as_update_v2())
    } else {
      peer.apply_update_v1(doc.encode_state_as_update_v1())
    }
    guard peer.get_or_insert_xml_fragment("xml").get(0) is Some(Element(parent)) else {
      fail("remote element")
    }
    guard parent.as_fragment().get(0) is Some(Text(child)) else {
      fail("remote text")
    }
    assert_eq(
      child.get_attribute("lang").map(@yrs.Out::to_json),
      Some(Json("en")),
    )
  }
}

///|
test "restored nested map entries keep their new parent through repeated undo and redo" {
  for skip_gc in [false, true] {
    let doc = @yrs.Doc(client_id=1UL, skip_gc~)
    let root = doc.get_or_insert_map("root")
    let child = root.insert_map("child")
    child.insert("name", String("original"))
    child.insert("count", Integer(10L))
    let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
    manager.expand_scope(Map(root))
    child.insert("name", String("changed"))
    child.insert("count", Integer(11L))
    child.insert("name", String("changed again"))
    root.remove("child") |> ignore
    for _ in 0..<3 {
      assert_true(manager.undo())
      assert_eq(root.to_json(), { "child": { "name": "original", "count": 10 } })
      for v2 in [false, true] {
        let peer = @yrs.Doc(client_id=2UL, skip_gc~)
        if v2 {
          peer.apply_update_v2(doc.encode_state_as_update_v2())
        } else {
          peer.apply_update_v1(doc.encode_state_as_update_v1())
        }
        assert_eq(peer.get_or_insert_map("root").to_json(), root.to_json())
      }
      assert_true(manager.redo())
      assert_eq(root.to_json(), {})
    }
  }
}
