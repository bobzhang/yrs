///|
pub(all) enum SyncMessage {
  SyncStep1(StateVector)
  SyncStep2(Bytes)
  Update(Bytes)
}

///|
pub(all) enum Message {
  Sync(SyncMessage)
  Auth(String?)
  AwarenessQuery
  Awareness(AwarenessUpdate)
  Custom(Byte, Bytes)
}

///|
fn Message::write(self : Message, writer : Writer) -> Unit {
  match self {
    Sync(message) => {
      writer.uint(0UL)
      match message {
        SyncStep1(state) => {
          writer.uint(0UL)
          writer.buffer(state.encode_v1())
        }
        SyncStep2(bytes) => {
          writer.uint(1UL)
          writer.buffer(bytes)
        }
        Update(bytes) => {
          writer.uint(2UL)
          writer.buffer(bytes)
        }
      }
    }
    Auth(reason) => {
      writer.uint(2UL)
      match reason {
        None => writer.uint(1UL)
        Some(reason) => {
          writer.uint(0UL)
          writer.string(reason)
        }
      }
    }
    AwarenessQuery => writer.uint(3UL)
    Awareness(update) => {
      writer.uint(1UL)
      writer.buffer(update.encode_v1())
    }
    Custom(tag, bytes) => {
      writer.byte(tag.to_int())
      writer.buffer(bytes)
    }
  }
}

///|
pub fn Message::encode_v1(self : Message) -> Bytes {
  encode_messages([self])
}

///|
pub fn encode_messages(messages : Array[Message]) -> Bytes {
  let writer : Writer = { bytes: [], }
  for message in messages {
    message.write(writer)
  }
  writer.finish()
}

///|
fn Reader::message(self : Reader) -> Message raise DecodeError {
  let tag = self.uint()
  guard tag <= 255UL else { raise InvalidData("message tag overflow") }
  match tag {
    0UL =>
      Sync(
        match self.uint() {
          0UL => SyncStep1(StateVector::decode_v1(self.buffer()))
          1UL => SyncStep2(self.buffer())
          2UL => Update(self.buffer())
          _ => raise InvalidData("unknown sync message")
        },
      )
    1UL => Awareness(AwarenessUpdate::decode_v1(self.buffer()))
    2UL => {
      let permission = self.uint()
      guard permission <= 255UL else {
        raise InvalidData("permission tag overflow")
      }
      Auth(if permission == 0UL { Some(self.string()) } else { None })
    }
    3UL => AwarenessQuery
    _ => Custom(tag.to_int().to_byte(), self.buffer())
  }
}

///|
pub fn Message::decode_v1(bytes : Bytes) -> Message raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let result = reader.message()
  reader.finish()
  result
}

///|
pub fn decode_messages(bytes : Bytes) -> Array[Message] raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let result = []
  while reader.offset < bytes.length() {
    result.push(reader.message())
  }
  result
}

///|
pub(all) suberror ProtocolError {
  PermissionDenied(String)
  UnsupportedMessage(Byte)
} derive(Debug)

///|
pub extend ProtocolError with Debug::{to_repr}

///|
/// Encode the default y-sync handshake (state vector and live awareness).
pub fn Awareness::start_sync(self : Awareness) -> Bytes {
  encode_messages([
    Sync(SyncStep1(self.document.state_vector())),
    Awareness(self.update()),
  ])
}

///|
pub fn Awareness::handle_message(
  self : Awareness,
  message : Message,
) -> Message? raise {
  DefaultProtocol().handle_message(self, message)
}

///|
/// Process concatenated protocol messages in order. As upstream does, a later
/// invalid message does not roll back messages already applied from the packet.
pub fn Awareness::handle_sync(
  self : Awareness,
  bytes : Bytes,
) -> Array[Message] raise {
  DefaultProtocol().handle(self, bytes)
}
