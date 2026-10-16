///|
test "document field codecs compose history, deltas and transaction updates" {
  for v2 in [false, true] {
    let doc = @yrs.Doc(client_id=1UL)
    let text = doc.get_or_insert_text("text")
    text.insert(0, "first")
    let snapshot = doc.snapshot()
    let before = doc.encode_state_as_update_v1()
    let encoder : &@yrs.Encoder = if v2 {
      (@yrs.EncoderV2() : &@yrs.Encoder)
    } else {
      (@yrs.EncoderV1() : &@yrs.Encoder)
    }
    doc.transact(fn(txn) {
      text.remove_range(0, 2)
      text.push("!")
      txn.encode_update(encoder)
    })
    doc.encode_state_from_snapshot(snapshot, encoder)
    doc.encode_diff(snapshot.state_vector(), encoder)
    doc.encode_state_as_update(@yrs.StateVector(), encoder)
    @yrs.Write::write_u8(encoder, 99)
    let packet = encoder.to_bytes()
    let decoder : &@yrs.Decoder = if v2 {
      (@yrs.DecoderV2(packet) : &@yrs.Decoder)
    } else {
      (@yrs.DecoderV1(packet) : &@yrs.Decoder)
    }
    let txn_update = @yrs.Update::decode(decoder)
    let history = @yrs.Update::decode(decoder)
    let delta = @yrs.Update::decode(decoder)
    let full = @yrs.Update::decode(decoder)
    assert_eq(@yrs.Read::read_u8(decoder), 99)
    assert_eq(decoder.read_to_end(), b"")
    let restored = @yrs.Doc(client_id=2UL)
    restored.apply_update(history)
    assert_eq(restored.get_or_insert_text("text").get_string(), "first")
    restored.apply_update(delta)
    assert_eq(restored.get_or_insert_text("text").get_string(), "rst!")
    let peer = @yrs.Doc(client_id=3UL)
    peer.apply_update_v1(before)
    peer.apply_update(txn_update)
    assert_eq(peer.get_or_insert_text("text").get_string(), "rst!")
    let fresh = @yrs.Doc(client_id=4UL)
    fresh.apply_update(full)
    assert_eq(fresh.get_or_insert_text("text").get_string(), "rst!")
  }
}

///|
test "generic document encoding excludes unresolved dependency packets" {
  let author = @yrs.Doc(client_id=1UL)
  let text = author.get_or_insert_text("text")
  text.insert(0, "first")
  let state = author.state_vector()
  text.push("second")
  let receiver = @yrs.Doc(client_id=2UL)
  receiver.apply_update_v1(author.encode_state_as_update_v1(remote=state))
  assert_true(receiver.has_pending_updates())
  let encoder = @yrs.EncoderV1()
  receiver.encode_state_as_update(@yrs.StateVector(), encoder)
  assert_true(@yrs.Update::decode_v1(encoder.to_bytes()).is_empty())
  assert_false(
    @yrs.Update::decode_v1(receiver.encode_state_as_update_v1()).is_empty(),
  )
}
