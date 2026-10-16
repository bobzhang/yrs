///|
fn run_protocol_async(work : async () -> Unit noraise) -> Unit = "%async.run"

///|
async fn suspend_protocol(
  register : ((Unit) -> Unit) -> Unit,
) -> Unit noraise + nocancel = "%async.suspend"

///|
struct DeferredAuth {
  continuations : Array[() -> Unit]
  calls : Array[String]
}

///|
impl @yrs.AsyncProtocol for DeferredAuth with fn handle_auth(
  self,
  _awareness,
  reason,
) {
  self.calls.push("waiting")
  suspend_protocol(fn(continue_) {
    self.continuations.push(fn() { continue_(()) })
  })
  self.calls.push("authorized")
  match reason {
    Some(reason) => raise @yrs.PermissionDenied(reason)
    None => None
  }
}

///|
impl @yrs.AsyncProtocol for DeferredAuth with fn handle_update(
  self,
  awareness,
  update,
) {
  self.calls.push("apply")
  @yrs.AsyncProtocol::handle_sync_step2(
    @yrs.DefaultProtocol(),
    awareness,
    update,
  )
}

///|
test "asynchronous protocol waits for authorization before applying later messages" {
  for denied in [false, true] {
    let source = @yrs.Doc(client_id=1UL)
    source.get_or_insert_text("text").insert(0, "accepted")
    let doc = @yrs.Doc(client_id=2UL)
    let awareness : @yrs.Awareness = Awareness(doc, clock=fn() { 0UL })
    let protocol : DeferredAuth = { continuations: [], calls: [], }
    let completed = Ref(false)
    let outcome = Ref(false)
    let packet = @yrs.encode_messages([
      Auth(if denied { Some("denied") } else { None }),
      Sync(Update(source.encode_state_as_update_v1())),
    ])
    run_protocol_async(async fn() noraise {
      try @yrs.AsyncProtocol::handle(protocol, awareness, packet) catch {
        _ => outcome.val = false
      } noraise {
        _ => outcome.val = true
      }
      completed.val = true
    })
    assert_false(completed.val)
    assert_eq(protocol.calls, ["waiting"])
    assert_true(doc.state_vector().is_empty())
    protocol.continuations[0]()
    assert_true(completed.val)
    assert_eq(outcome.val, !denied)
    if denied {
      assert_eq(protocol.calls, ["waiting", "authorized"])
      assert_true(doc.state_vector().is_empty())
    } else {
      assert_eq(protocol.calls, ["waiting", "authorized", "apply"])
      assert_eq(doc.get_or_insert_text("text").get_string(), "accepted")
    }
  }
}

///|
test "default asynchronous protocol produces the same handshake and responses" {
  let awareness : @yrs.Awareness = Awareness(Doc(client_id=1UL), clock=fn() {
    0UL
  })
  awareness.set_local_state({ "name": "peer" })
  let result = Ref(None)
  run_protocol_async(async fn() noraise {
    try {
      let protocol = @yrs.DefaultProtocol()
      let start = @yrs.AsyncProtocol::start(protocol, awareness)
      let responses = @yrs.AsyncProtocol::handle(
        protocol,
        awareness,
        @yrs.Message::AwarenessQuery.encode_v1(),
      )
      result.val = Some((start, @yrs.encode_messages(responses)))
    } catch {
      _ => ()
    }
  })
  assert_eq(
    result.val,
    Some(
      (
        awareness.start_sync(),
        @yrs.encode_messages(
          awareness.handle_sync(@yrs.Message::AwarenessQuery.encode_v1()),
        ),
      ),
    ),
  )
}
