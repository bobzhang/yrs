///|
fn check_typed_v2(packet : Bytes, value : @yrs.Any) -> Unit raise {
  let target = @yrs.Doc(client_id=9UL)
  target.apply_update_v2(packet)
  let text = target.get_or_insert_text("text")
  assert_true(text.to_delta()[0].insert == @yrs.Out::Value(value))
  assert_eq(text.to_delta()[1].attributes, [("custom", value)])
}

///|
test "v2 typed rich-text values survive documents updates history and field codecs" {
  for
    value in [
      @yrs.Any::Buffer(b"\x01\x02"),
      Undefined,
      Integer(9007199254740993L),
    ] {
    let doc = @yrs.Doc(client_id=1UL)
    let packets = []
    let events : Array[@yrs.Transaction] = []
    doc.observe_update_v2("v2", fn(bytes, txn) {
      packets.push(bytes)
      events.push(txn)
    })
    let text = doc.get_or_insert_text("text")
    doc.transact(fn(_) {
      text.insert_embed(0, value)
      text.insert_with_attributes(1, "x", [("custom", value)])
    })
    let empty = @yrs.StateVector()
    let full = doc.encode_state_as_update_v2()
    let update = @yrs.Update::decode_v2(full)
    let merged : @yrs.Update = @yrs.Update()
    merged.merge(update)
    let generic = @yrs.EncoderV2()
    doc.encode_diff(empty, generic)
    doc.encode_state_as_update(empty, generic)
    doc.encode_state_from_snapshot(doc.snapshot(), generic)
    events[0].encode_update(generic)
    update.encode(generic)
    let decoder = @yrs.DecoderV2(generic.to_bytes())
    for _ in 0..<5 {
      check_typed_v2(@yrs.Update::decode(decoder).encode_v2(), value)
    }
    for
      packet in [
        full,
        doc.encode_diff_v2(empty),
        packets[0],
        events[0].encode_update_v2(),
        update.encode_v2(),
        update.encode_diff_v2(empty),
        merged.encode_v2(),
        @yrs.merge_updates_v2([full, full]),
        @yrs.diff_updates_v2(full, empty.encode_v1()),
        doc.encode_state_from_snapshot_v2(doc.snapshot()),
      ] {
      check_typed_v2(packet, value)
    }
    let direct = @yrs.Doc(client_id=3UL)
    direct.apply_update(update)
    check_typed_v2(direct.encode_state_as_update_v2(), value)
    // Retaining an event must preserve its typed v2 payload after further edits.
    text.push("later")
    check_typed_v2(events[0].encode_update_v2(), value)
  }
}

///|
test "Rust v2 buffer embed imports without JSON projection" {
  let doc = @yrs.Doc(client_id=2UL)
  doc.apply_update_v2(
    b"\x00\x00\x01\x01\x00\x00\x01\x05\x06\x04text\x04\x01\x01\x00\x00\x01\x01\x00\x74\x02\x01\x02\x00",
  )
  assert_true(
    doc.get_or_insert_text("text").to_delta()[0].insert ==
    @yrs.Out::Value(Buffer(b"\x01\x02")),
  )
}

///|
test "typed pending updates survive inspection pruning and dependency delivery" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.push("prefix")
  let prefix = doc.encode_state_as_update_v2()
  let cut = doc.state_vector()
  text.insert_embed(text.length(), Buffer(b"\x01\x02"))
  let suffix = doc.encode_diff_v2(cut)
  let pending = @yrs.Doc(client_id=2UL)
  pending.apply_update_v2(suffix)
  assert_true(pending.has_pending_updates())
  let inspected = pending.pending_update().unwrap()
  let pruned = pending.prune_pending().unwrap()
  assert_false(pending.has_pending_updates())
  for update in [inspected, pruned] {
    let target = @yrs.Doc(client_id=3UL)
    target.apply_update_v2(update.encode_v2())
    target.apply_update_v2(prefix)
    assert_true(
      target.get_or_insert_text("text").to_delta()[1].insert ==
      @yrs.Out::Value(Buffer(b"\x01\x02")),
    )
  }
}

///|
test "decoded subdocument updates retain wire options and create independent children" {
  let source = @yrs.Doc(client_id=1UL)
  source
  .get_or_insert_map("map")
  .insert_doc("child", @yrs.Doc(guid="child", client_id=7UL))
  |> ignore
  let bytes = source.encode_state_as_update_v2()
  let update = @yrs.Update::decode_v2(bytes)
  let before = update.encode_v2()
  let a = @yrs.Doc(client_id=2UL)
  let b = @yrs.Doc(client_id=3UL)
  a.apply_update(update)
  b.apply_update(update)
  assert_eq(update.encode_v2(), before)
  let ca = a.subdocs()[0]
  let cb = b.subdocs()[0]
  assert_false(ca.should_load())
  assert_false(cb.should_load())
  ca.get_or_insert_text("text").push("local child content")
  assert_eq(cb.get_or_insert_text("text").get_string(), "")
  assert_true(ca.parent_doc().unwrap() == a)
  assert_true(cb.parent_doc().unwrap() == b)
}
