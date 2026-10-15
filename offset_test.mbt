///|
test "UTF8 editing uses byte offsets and UTF16 replica clocks" {
  let bytes = @yrs.Doc(client_id=1UL, offset_kind=Bytes)
  let text = bytes.get_or_insert_text("body")
  text.insert(0, "a🦀世z")
  assert_eq(text.length(), 9)
  assert_eq(bytes.state_vector().get(1UL), 5U)
  text.insert(5, "界")
  text.remove_range(1, 4)
  assert_eq(text.get_string(), "a界世z")
  assert_eq(text.length(), 8)
  text.format(1, 6, [("bold", Bool(true))])
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(bytes.encode_state_as_update_v2())
  let remote = peer.get_or_insert_text("body")
  assert_eq(remote.length(), 4)
  assert_eq(remote.get_string(), text.get_string())
  remote.insert(2, "😀")
  bytes.apply_update_v1(peer.encode_state_as_update_v1())
  assert_eq(text.length(), 12)
  assert_eq(text.get_string(), "a界😀世z")
}

///|
test "UTF8 text event lengths and child offset mode survive wire roundtrip" {
  let doc = @yrs.Doc(client_id=1UL, offset_kind=Bytes)
  let text = doc.get_or_insert_text("body")
  text.insert(0, "世🦀z")
  let changes : Array[Json] = []
  text.observe("delta", fn(e, _) {
    changes.push(Json(e.delta().iter().map(@yrs.Delta::to_json).to_array()))
  })
  text.remove_range(3, 4)
  assert_eq(changes[0].stringify(), "[{\"retain\":3},{\"delete\":4}]")
  let child = @yrs.Doc(client_id=2UL, guid="bytes", offset_kind=Bytes)
  doc.get_or_insert_array("children").insert_doc(0, child) |> ignore
  let peer = @yrs.Doc(client_id=3UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  let received = peer.subdocs()[0]
  assert_eq(received.offset_kind(), Bytes)
  received.get_or_insert_text("body").insert(0, "🦀")
  assert_eq(received.get_or_insert_text("body").length(), 4)
}
