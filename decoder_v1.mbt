///|
/// lib0 v1 update decoder. Inputs are owned; returned buffers are snapshots.
pub struct DecoderV1 {
  priv reader : UpdateReader
}

///|
pub fn DecoderV1::DecoderV1(bytes : Bytes) -> DecoderV1 {
  { reader: try! UpdateReader::make(bytes, false, 0x7fff_ffff), }
}

///|
pub impl Read for DecoderV1 with fn read_exact(self, length) {
  let cursor = Cursor::{ reader: self.reader.raw, }
  cursor.read_exact(length)
}

///|
pub impl Read for DecoderV1 with fn read_u8(self) {
  self.reader.raw.byte().to_byte()
}

///|
pub impl Read for DecoderV1 with fn read_string(self) {
  self.reader.string()
}

///|
pub impl Decoder for DecoderV1 with fn reset_ds_cur_val(_self) {
  ()
}

///|
pub impl Decoder for DecoderV1 with fn read_to_end(self) {
  self.reader.raw.bytes[self.reader.raw.offset:].to_owned()
}

///|
pub impl Decoder for DecoderV1 with fn read_ds_clock(self) {
  self.reader.raw.clock()
}

///|
pub impl Decoder for DecoderV1 with fn read_ds_len(self) {
  self.reader.raw.clock()
}

///|
pub impl Decoder for DecoderV1 with fn read_left_id(self) {
  { client: self.reader.field(1), clock: codec_clock(self.reader.field(2)), }
}

///|
pub impl Decoder for DecoderV1 with fn read_right_id(self) {
  { client: self.reader.field(1), clock: codec_clock(self.reader.field(3)), }
}

///|
pub impl Decoder for DecoderV1 with fn read_client(self) {
  self.reader.field(1)
}

///|
pub impl Decoder for DecoderV1 with fn read_info(self) {
  codec_byte(self.reader.field(4))
}

///|
pub impl Decoder for DecoderV1 with fn read_parent_info(self) {
  self.reader.field(6) == 1UL
}

///|
pub impl Decoder for DecoderV1 with fn read_type_ref(self) {
  codec_byte(self.reader.field(7))
}

///|
pub impl Decoder for DecoderV1 with fn read_len(self) {
  codec_clock(self.reader.field(8))
}

///|
pub impl Decoder for DecoderV1 with fn read_any(self) {
  self.reader.raw.any()
}

///|
pub impl Decoder for DecoderV1 with fn read_json(self) {
  self.reader.json()
}

///|
pub impl Decoder for DecoderV1 with fn read_key(self) {
  self.reader.key()
}

///|
pub extend DecoderV1 with Read::{
  read_exact,
  read_u8,
  read_u16,
  read_u32,
  read_u32_be,
  read_u64,
  read_i64,
  read_f32,
  read_f64,
  read_var_uint,
  read_var_int,
  read_var_signed,
  read_buf,
  read_string,
}

///|
pub extend DecoderV1 with Decoder::{
  reset_ds_cur_val,
  read_to_end,
  read_ds_clock,
  read_ds_len,
  read_left_id,
  read_right_id,
  read_client,
  read_info,
  read_parent_info,
  read_type_ref,
  read_len,
  read_any,
  read_json,
  read_key,
}
