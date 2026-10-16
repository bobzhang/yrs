///|
test "generic update codecs round-trip full mixed documents and concatenated messages" {
  let doc = @yrs.Doc(client_id=42UL, guid="codec-doc")
  let text = doc.get_or_insert_text("text")
  text.insert(0, "Moon🌙")
  text.format(0, 4, [("bold", Bool(true))])
  text.insert_embed(4, Buffer(b"\x00\xff"))
  let map = doc.get_or_insert_map("map")
  let nested = map.insert_text("nested")
  nested.insert(0, "value")
  map.insert_array("list").insert_range(0, [Integer(1L), Null, Buffer(b"data")])
  doc
  .get_or_insert_xml_fragment("xml")
  .insert_element(0, "p")
  .as_fragment()
  .insert_text(0)
  .as_text()
  .insert(0, "hello")
  map.insert_input("link", WeakLink(text.quote(Included(0), Included(1))))
  |> ignore
  map.insert_doc("child", @yrs.Doc(client_id=8UL, guid="child-doc")) |> ignore
  map.insert_input("root-range", WeakLink(text.quote(Unbounded, Unbounded)))
  |> ignore
  map.insert_input("nested-range", WeakLink(nested.quote(Unbounded, Unbounded)))
  |> ignore
  text.remove_range(0, 1)
  let update = @yrs.Update::decode_v1(doc.encode_state_as_update_v1())
  for v2 in [false, true] {
    let encoder : &@yrs.Encoder = if v2 {
      (@yrs.EncoderV2() : &@yrs.Encoder)
    } else {
      (@yrs.EncoderV1() : &@yrs.Encoder)
    }
    update.encode(encoder)
    doc.state_vector().encode(encoder)
    @yrs.Write::write_u8(encoder, 238)
    let packet = encoder.to_bytes()
    let decoder : &@yrs.Decoder = if v2 {
      (@yrs.DecoderV2(packet) : &@yrs.Decoder)
    } else {
      (@yrs.DecoderV1(packet) : &@yrs.Decoder)
    }
    let restored = @yrs.Update::decode(decoder)
    assert_eq(restored.encode_v1(), update.encode_v1())
    assert_eq(@yrs.StateVector::decode(decoder), doc.state_vector())
    assert_eq(@yrs.Read::read_u8(decoder), 238)
    assert_eq(decoder.read_to_end(), b"")
    let peer = @yrs.Doc(client_id=7UL)
    peer.apply_update(restored)
    assert_eq(peer.get_or_insert_text("text").get_string(), text.get_string())
    assert_eq(peer.state_vector(), doc.state_vector())
    assert_eq(@yrs.Encode::encode_v2(update), update.encode_v2())
  }
}

///|
test "generic update decoding rejects expanded counts before iteration" {
  let writer = @yrs.EncoderV2()
  writer.write_var_uint(1000001UL)
  let decoder = @yrs.DecoderV2(writer.to_bytes())
  try @yrs.Update::decode(decoder) catch {
    _ => ()
  } noraise {
    _ => fail("unbounded update expansion")
  }
}
