///|
/// lib0 v1 update encoder. `to_bytes` snapshots without consuming the encoder.
pub struct EncoderV1 {
  priv writer : UpdateWriter
}

///|
pub fn EncoderV1::EncoderV1() -> EncoderV1 {
  { writer: UpdateWriter::make(false), }
}

///|
pub impl Write for EncoderV1 with fn write_all(self, bytes) {
  for byte in bytes {
    self.writer.raw.bytes.push(byte)
  }
}

///|
pub impl Write for EncoderV1 with fn write_u8(self, value) {
  self.writer.raw.byte(value.to_int())
}

///|
pub impl Write for EncoderV1 with fn write_string(self, value) {
  self.writer.string(value)
}

///|
pub impl Encoder for EncoderV1 with fn to_bytes(self) {
  self.writer.finish()
}

///|
pub impl Encoder for EncoderV1 with fn reset_ds_cur_val(_self) {
  ()
}

///|
pub impl Encoder for EncoderV1 with fn write_ds_clock(self, value) {
  self.writer.raw.uint(value.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_ds_len(self, value) {
  self.writer.raw.uint(value.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_left_id(self, value) {
  self.writer.field(1, value.client)
  self.writer.field(2, value.clock.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_right_id(self, value) {
  self.writer.field(1, value.client)
  self.writer.field(3, value.clock.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_client(self, value) {
  self.writer.field(1, value)
}

///|
pub impl Encoder for EncoderV1 with fn write_info(self, value) {
  self.writer.field(4, value.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_parent_info(self, value) {
  self.writer.field(6, if value { 1UL } else { 0UL })
}

///|
pub impl Encoder for EncoderV1 with fn write_type_ref(self, value) {
  self.writer.field(7, value.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_len(self, value) {
  self.writer.field(8, value.to_uint64())
}

///|
pub impl Encoder for EncoderV1 with fn write_any(self, value) {
  self.writer.raw.any(value)
}

///|
pub impl Encoder for EncoderV1 with fn write_json(self, value) {
  self.writer.json(value)
}

///|
pub impl Encoder for EncoderV1 with fn write_key(self, value) {
  self.writer.key(value)
}

///|
pub extend EncoderV1 with Write::{
  write_all,
  write_u8,
  write_u16,
  write_u32,
  write_u32_be,
  write_u64,
  write_i64,
  write_f32,
  write_f64,
  write_var_uint,
  write_var_int,
  write_var_signed,
  write_buf,
  write_string,
}

///|
pub extend EncoderV1 with Encoder::{
  to_bytes,
  reset_ds_cur_val,
  write_ds_clock,
  write_ds_len,
  write_left_id,
  write_right_id,
  write_client,
  write_info,
  write_parent_info,
  write_type_ref,
  write_len,
  write_any,
  write_json,
  write_key,
}
