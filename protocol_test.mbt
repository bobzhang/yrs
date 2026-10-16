///|
struct AppProtocol {
  calls : Array[String]
}

///|
impl @yrs.Protocol for AppProtocol with fn handle_sync_step2(
  self,
  awareness,
  update,
) {
  self.calls.push("apply")
  awareness
  .doc()
  .transact(
    fn(_) raise { awareness.doc().apply_update(update) },
    origin=b"network",
  )
  None
}

///|
impl @yrs.Protocol for AppProtocol with fn handle_auth(self, _awareness, reason) {
  self.calls.push(reason.unwrap_or("allowed"))
  Some(Auth(None))
}

///|
impl @yrs.Protocol for AppProtocol with fn missing_handle(
  self,
  _awareness,
  tag,
  bytes,
) {
  self.calls.push("custom")
  Some(Custom(tag, bytes))
}

///|
test "custom protocols retain default dispatch and can override application behavior" {
  let source = @yrs.Doc(client_id=1UL)
  source.get_or_insert_text("text").insert(0, "hello")
  let doc = @yrs.Doc(client_id=2UL)
  let awareness : @yrs.Awareness = Awareness(doc, clock=fn() { 0UL })
  awareness.set_local_state({ "name": "peer" })
  let origins = []
  doc.observe_update_v1("origin", fn(_, tx) { origins.push(tx.origin()) })
  let protocol : AppProtocol = { calls: [], }
  let packet = @yrs.encode_messages([
    Auth(Some("application policy")),
    Sync(SyncStep2(source.encode_state_as_update_v1())),
    Custom(b'\x2a', b"payload"),
    AwarenessQuery,
  ])
  let replies = @yrs.Protocol::handle(protocol, awareness, packet)
  assert_eq(protocol.calls, ["application policy", "apply", "custom"])
  assert_eq(origins, [Some(b"network")])
  assert_eq(doc.get_or_insert_text("text").get_string(), "hello")
  assert_eq(replies.length(), 3)
  assert_eq(replies[0].encode_v1(), @yrs.Message::Auth(None).encode_v1())
  assert_eq(
    replies[1].encode_v1(),
    @yrs.Message::Custom(b'\x2a', b"payload").encode_v1(),
  )
  // The default continuous-update handler delegates to the overridden step 2.
  source.get_or_insert_text("text").push("!")
  @yrs.Protocol::handle_message(
    protocol,
    awareness,
    Sync(Update(source.encode_state_as_update_v1())),
  )
  |> ignore
  assert_eq(protocol.calls.last(), Some("apply"))
  assert_eq(doc.get_or_insert_text("text").get_string(), "hello!")
  assert_eq(@yrs.Protocol::start(protocol, awareness), awareness.start_sync())
  let reply = @yrs.Protocol::handle_message(
    protocol,
    awareness,
    Sync(SyncStep1(@yrs.StateVector())),
  ).unwrap()
  let recipient : @yrs.Awareness = Awareness(Doc(client_id=3UL), clock=fn() {
    0UL
  })
  @yrs.DefaultProtocol().handle_message(recipient, reply) |> ignore
  assert_eq(recipient.doc().get_or_insert_text("text").get_string(), "hello!")
}

///|
test "custom protocol processing preserves prior messages when a later message is invalid" {
  let source = @yrs.Doc(client_id=1UL)
  source.get_or_insert_text("text").insert(0, "retained")
  let awareness : @yrs.Awareness = Awareness(Doc(client_id=2UL), clock=fn() {
    0UL
  })
  let protocol : AppProtocol = { calls: [], }
  let packet = @yrs.encode_messages([
    Sync(Update(source.encode_state_as_update_v1())),
    Sync(Update(b"\xff")),
    Custom(b'\x2a', b"must not run"),
  ])
  try @yrs.Protocol::handle(protocol, awareness, packet) catch {
    _ => ()
  } noraise {
    _ => fail("invalid update accepted")
  }
  assert_eq(protocol.calls, ["apply"])
  assert_eq(awareness.doc().get_or_insert_text("text").get_string(), "retained")
  try
    @yrs.DefaultProtocol().handle_message(awareness, Auth(Some("denied")))
  catch {
    @yrs.PermissionDenied(reason) => assert_eq(reason, "denied")
    _ => fail("wrong error")
  } noraise {
    _ => fail("denied authorization accepted")
  }
}
