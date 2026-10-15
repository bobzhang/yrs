///|
test "awareness renewals events removal protection and origins" {
  let mut time = 10UL
  let a : @yrs.Awareness = Awareness(Doc(client_id=1UL), clock=fn() { time })
  let changes : Array[@yrs.AwarenessSummary] = []
  let updates : Array[@yrs.AwarenessSummary] = []
  let origins : Array[Bytes?] = []
  a.on_change("test", fn(_, e, _) { changes.push(e) })
  a.on_update("test", fn(_, e, origin) {
    updates.push(e)
    origins.push(origin)
  })
  a.set_local_state_raw("{}")
  a.set_local_state_raw("{}")
  assert_eq(changes.length(), 1)
  assert_eq(updates.length(), 2)
  time = 20UL
  a.apply_update(AwarenessUpdate(entries=[(1UL, { clock: 2U, json: "null", })]))
  |> ignore
  assert_eq(a.local_state_raw(), Some("{}"))
  assert_eq(a.meta(1UL), Some((3U, 20UL)))
  assert_eq(updates.length(), 2)
  a.apply_update(
    AwarenessUpdate(entries=[(2UL, { clock: 0U, json: "{}", })]),
    origin=b"peer",
  )
  |> ignore
  assert_eq(origins.last(), Some(Some(b"peer")))
  assert_eq(changes.last().unwrap().all_changes(), [2UL])
  a.remove_state(2UL)
  assert_true(a.state(2UL) is None)
  let tombstone = a.update_with_clients([2UL])
  assert_eq(tombstone.entries()[0].1.json, "null")
  assert_eq(a.update().entries().length(), 1)
  assert_true(a.unobserve_change("test"))
  assert_true(!a.unobserve_change("test"))
  assert_true(a.unobserve_update("test"))
  try a.update_with_clients([99UL]) catch {
    ClientNotFound(99UL) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("missing client accepted")
  }
}

///|
test "sync handshake exchanges documents and awareness across replicas" {
  let a : @yrs.Awareness = Awareness(Doc(client_id=1UL), clock=fn() { 0UL })
  let b : @yrs.Awareness = Awareness(Doc(client_id=2UL), clock=fn() { 0UL })
  a.doc().get_or_insert_text("note").insert(0, "Moon")
  b.doc().get_or_insert_text("note").insert(0, "Bit")
  a.set_local_state({ "name": "left" })
  b.set_local_state({ "name": "right" })
  for (source, target) in [(a, b), (b, a)] {
    let responses = target.handle_sync(source.start_sync())
    source.handle_sync(@yrs.encode_messages(responses)) |> ignore
  }
  assert_eq(a.doc().get_or_insert_text("note").get_string(), "MoonBit")
  assert_eq(b.doc().get_or_insert_text("note").get_string(), "MoonBit")
  assert_eq(a.state(2UL), b.local_state())
  assert_eq(b.state(1UL), a.local_state())
  assert_eq(a.handle_sync(b"\x02\x01").length(), 0)
  try a.handle_sync(@yrs.Message::Auth(Some("denied")).encode_v1()) catch {
    @yrs.PermissionDenied(reason) => assert_eq(reason, "denied")
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("authorization denial ignored")
  }
}

///|
test "protocol codec handles concatenated messages and rejects truncation" {
  let messages : Array[@yrs.Message] = [
    Sync(SyncStep1(StateVector())),
    Auth(None),
    Auth(Some("no")),
    AwarenessQuery,
    Custom(b'Z', b"data"),
  ]
  let bytes = @yrs.encode_messages(messages)
  assert_eq(bytes, b"\x00\x00\x01\x00\x02\x01\x02\x00\x02no\x03Z\x04data")
  assert_eq(@yrs.encode_messages(@yrs.decode_messages(bytes)), bytes)
  for input in [b"\x00", b"\x00\x03", b"\x01\xff", b"\x02\x00\x02x"] {
    try @yrs.decode_messages(input) catch {
      InvalidData(_) => ()
    } noraise {
      _ => fail("malformed message accepted")
    }
  }
  let a : @yrs.Awareness = Awareness(Doc(client_id=1UL), clock=fn() { 0UL })
  try a.handle_sync(@yrs.Message::Custom(b'Z', b"").encode_v1()) catch {
    @yrs.UnsupportedMessage(b'Z') => ()
    _ => fail("wrong custom error")
  } noraise {
    _ => fail("unsupported message accepted")
  }
}
