///|
test "XML traversal follows live siblings and skips removed nested subtrees" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_xml_fragment("xml")
  let p = root.push_back(
    XmlElement("p", [], [
      XmlText([Inserted(Value(String("Hello ")), [])], []),
      XmlElement("b", [], [XmlText([Inserted(Value(String("world")), [])], [])]),
    ]),
  )
  root.push_back(XmlText([Inserted(Value(String("again")), [])], [])) |> ignore
  let mut visited = root.successors().map(@yrs.XmlNode::get_string).to_array()
  assert_eq(visited, [
    "<p>Hello <b>world</b></p>", "Hello ", "<b>world</b>", "world", "again",
  ])
  assert_eq(p.next_sibling().unwrap().get_string(), "again")
  assert_eq(
    p.next_sibling().unwrap().prev_sibling().unwrap().branch_id(),
    p.branch_id(),
  )
  assert_eq(p.siblings().count(), 1)
  assert_eq(p.siblings(backwards=true).count(), 0)
  assert_eq(root.first_child().unwrap().branch_id(), p.branch_id())
  assert_true(root.get(2) is None)
  root.remove(0)
  assert_true(p.is_deleted())
  visited = root.successors().map(@yrs.XmlNode::get_string).to_array()
  assert_eq(visited, ["again"])
  // Deleted handles still retain a position in the linked sequence until GC.
  assert_eq(p.next_sibling().unwrap().get_string(), "again")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(
    peer
    .get_or_insert_xml_fragment("xml")
    .successors()
    .map(@yrs.XmlNode::get_string)
    .to_array(),
    visited,
  )
}
