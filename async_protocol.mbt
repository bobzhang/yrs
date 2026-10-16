///|
/// Asynchronous y-sync dispatch. Host callbacks may suspend for authentication
/// or transport work; document mutations remain synchronous within each handler.
pub(open) trait AsyncProtocol {
  async fn start(Self, Awareness) -> Bytes = _
  async fn handle(Self, Awareness, Bytes) -> Array[Message] = _
  async fn handle_message(Self, Awareness, Message) -> Message? = _
  async fn handle_sync_step1(Self, Awareness, StateVector) -> Message? = _
  async fn handle_sync_step2(Self, Awareness, Update) -> Message? = _
  async fn handle_update(Self, Awareness, Update) -> Message? = _
  async fn handle_auth(Self, Awareness, String?) -> Message? = _
  async fn handle_awareness_query(Self, Awareness) -> Message? = _
  async fn handle_awareness_update(Self, Awareness, AwarenessUpdate) -> Message? = _
  async fn missing_handle(Self, Awareness, Byte, Bytes) -> Message? = _
}

///|
impl AsyncProtocol with fn start(_self, awareness) {
  awareness.start_sync()
}

///|
impl AsyncProtocol with fn handle(self, awareness, bytes) {
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
impl AsyncProtocol with fn handle_message(self, awareness, message) {
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
impl AsyncProtocol with fn handle_sync_step1(_self, awareness, remote) {
  Some(Sync(SyncStep2(awareness.doc().encode_state_as_update_v1(remote~))))
}

///|
impl AsyncProtocol with fn handle_sync_step2(_self, awareness, update) {
  awareness.doc().apply_update(update)
  None
}

///|
impl AsyncProtocol with fn handle_update(self, awareness, update) {
  self.handle_sync_step2(awareness, update)
}

///|
impl AsyncProtocol with fn handle_auth(_self, _awareness, reason) {
  match reason {
    Some(reason) => raise PermissionDenied(reason)
    None => None
  }
}

///|
impl AsyncProtocol with fn handle_awareness_query(_self, awareness) {
  Some(Awareness(awareness.update()))
}

///|
impl AsyncProtocol with fn handle_awareness_update(_self, awareness, update) {
  awareness.apply_update(update) |> ignore
  None
}

///|
impl AsyncProtocol with fn missing_handle(_self, _awareness, tag, _bytes) {
  raise UnsupportedMessage(tag)
}

///|
pub impl AsyncProtocol for DefaultProtocol with fn missing_handle(
  _self,
  _awareness,
  tag,
  _bytes,
) {
  raise UnsupportedMessage(tag)
}
