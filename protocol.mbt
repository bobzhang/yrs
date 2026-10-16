///|
/// Extensible y-sync dispatch. Override individual handlers while retaining the
/// default handshake, ordered packet processing and update application.
pub(open) trait Protocol {
  fn start(Self, Awareness) -> Bytes raise = _
  fn handle(Self, Awareness, Bytes) -> Array[Message] raise = _
  fn handle_message(Self, Awareness, Message) -> Message? raise = _
  fn handle_sync_step1(Self, Awareness, StateVector) -> Message? raise = _
  fn handle_sync_step2(Self, Awareness, Update) -> Message? raise = _
  fn handle_update(Self, Awareness, Update) -> Message? raise = _
  fn handle_auth(Self, Awareness, String?) -> Message? raise = _
  fn handle_awareness_query(Self, Awareness) -> Message? raise = _
  fn handle_awareness_update(Self, Awareness, AwarenessUpdate) -> Message? raise = _
  fn missing_handle(Self, Awareness, Byte, Bytes) -> Message? raise = _
}

///|
impl Protocol with fn start(_self, awareness) {
  awareness.start_sync()
}

///|
impl Protocol with fn handle(self, awareness, bytes) {
  let reader : Reader = { bytes, offset: 0, }
  let replies = []
  while reader.offset < bytes.length() {
    if self.handle_message(awareness, reader.message()) is Some(reply) {
      replies.push(reply)
    }
  }
  replies
}

///|
impl Protocol with fn handle_message(self, awareness, message) {
  match message {
    Sync(SyncStep1(state)) => self.handle_sync_step1(awareness, state)
    Sync(SyncStep2(bytes)) =>
      self.handle_sync_step2(awareness, Update::decode_v1(bytes))
    Sync(Update(bytes)) =>
      self.handle_update(awareness, Update::decode_v1(bytes))
    Auth(reason) => self.handle_auth(awareness, reason)
    AwarenessQuery => self.handle_awareness_query(awareness)
    Awareness(update) => self.handle_awareness_update(awareness, update)
    Custom(tag, bytes) => self.missing_handle(awareness, tag, bytes)
  }
}

///|
impl Protocol with fn handle_sync_step1(_self, awareness, remote) {
  Some(Sync(SyncStep2(awareness.doc().encode_state_as_update_v1(remote~))))
}

///|
impl Protocol with fn handle_sync_step2(_self, awareness, update) {
  awareness.doc().apply_update(update)
  None
}

///|
impl Protocol with fn handle_update(self, awareness, update) {
  self.handle_sync_step2(awareness, update)
}

///|
impl Protocol with fn handle_auth(_self, _awareness, reason) {
  match reason {
    Some(reason) => raise PermissionDenied(reason)
    None => None
  }
}

///|
impl Protocol with fn handle_awareness_query(_self, awareness) {
  Some(Awareness(awareness.update()))
}

///|
impl Protocol with fn handle_awareness_update(_self, awareness, update) {
  awareness.apply_update(update) |> ignore
  None
}

///|
impl Protocol with fn missing_handle(_self, _awareness, tag, _bytes) {
  raise UnsupportedMessage(tag)
}

///|
pub struct DefaultProtocol {}

///|
pub fn DefaultProtocol::DefaultProtocol() -> DefaultProtocol {
  DefaultProtocol::{ }
}

///|
pub impl Protocol for DefaultProtocol with fn missing_handle(
  _self,
  _awareness,
  tag,
  _bytes,
) {
  raise UnsupportedMessage(tag)
}

///|
pub extend DefaultProtocol with Protocol::{
  start,
  handle,
  handle_message,
  handle_sync_step1,
  handle_sync_step2,
  handle_update,
  handle_auth,
  handle_awareness_query,
  handle_awareness_update,
  missing_handle,
}
