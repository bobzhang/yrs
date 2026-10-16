///|
/// Update-format output, including v2 compression columns. Implementations can
/// customize field encoding without changing application `Encode` instances.
pub(open) trait Encoder: Write {
  fn to_bytes(Self) -> Bytes raise DecodeError
  fn reset_ds_cur_val(Self) -> Unit
  fn write_ds_clock(Self, UInt32) -> Unit
  fn write_ds_len(Self, UInt32) -> Unit
  fn write_left_id(Self, Id) -> Unit
  fn write_right_id(Self, Id) -> Unit
  fn write_client(Self, UInt64) -> Unit
  fn write_info(Self, Byte) -> Unit
  fn write_parent_info(Self, Bool) -> Unit
  fn write_type_ref(Self, Byte) -> Unit
  fn write_len(Self, UInt32) -> Unit
  fn write_any(Self, Any) -> Unit
  fn write_json(Self, Any) -> Unit
  fn write_key(Self, String) -> Unit
}

///|
/// Update-format input. `read_to_end` snapshots the remaining raw stream without
/// advancing it, matching the pinned Yrs implementation.
pub(open) trait Decoder: Read {
  fn reset_ds_cur_val(Self) -> Unit
  fn read_to_end(Self) -> Bytes
  fn read_ds_clock(Self) -> UInt32 raise DecodeError
  fn read_ds_len(Self) -> UInt32 raise DecodeError
  fn read_left_id(Self) -> Id raise DecodeError
  fn read_right_id(Self) -> Id raise DecodeError
  fn read_client(Self) -> UInt64 raise DecodeError
  fn read_info(Self) -> Byte raise DecodeError
  fn read_parent_info(Self) -> Bool raise DecodeError
  fn read_type_ref(Self) -> Byte raise DecodeError
  fn read_len(Self) -> UInt32 raise DecodeError
  fn read_any(Self) -> Any raise DecodeError
  fn read_json(Self) -> Any raise DecodeError
  fn read_key(Self) -> String raise DecodeError
}

///|
/// Application-defined values composed from update codec fields.
pub(open) trait Encode {
  fn encode(Self, &Encoder) -> Unit
  fn encode_v1(Self) -> Bytes raise DecodeError = _
  fn encode_v2(Self) -> Bytes raise DecodeError = _
}

///|
pub(open) trait Decode {
  fn decode(&Decoder) -> Self raise DecodeError
  fn decode_v1(Bytes) -> Self raise DecodeError = _
  fn decode_v2(Bytes) -> Self raise DecodeError = _
}

///|
impl Encode with fn encode_v1(self) {
  let encoder = EncoderV1()
  self.encode(encoder)
  encoder.to_bytes()
}

///|
impl Encode with fn encode_v2(self) {
  let encoder = EncoderV2()
  self.encode(encoder)
  encoder.to_bytes()
}

///|
impl Decode with fn decode_v1(bytes) {
  Self::decode(DecoderV1(bytes))
}

///|
impl Decode with fn decode_v2(bytes) {
  Self::decode(DecoderV2(bytes))
}

///|
fn codec_byte(value : UInt64) -> Byte raise DecodeError {
  guard value <= 255UL else { raise InvalidData("byte overflow") }
  value.to_int().to_byte()
}

///|
fn codec_clock(value : UInt64) -> UInt32 raise DecodeError {
  guard value <= 0xffff_ffffUL else { raise InvalidData("clock overflow") }
  value.to_uint()
}
