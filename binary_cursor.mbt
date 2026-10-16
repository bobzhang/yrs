///|
/// Owned, bounds-checked lib0 input cursor. Failed fixed-width reads do not advance.
pub struct Cursor {
  priv reader : Reader
}

///|
pub fn Cursor::Cursor(bytes : Bytes) -> Cursor {
  { reader: { bytes, offset: 0, }, }
}

///|
pub fn Cursor::position(self : Cursor) -> Int32 {
  self.reader.offset
}

///|
pub fn Cursor::remaining(self : Cursor) -> Int32 {
  self.reader.bytes.length() - self.reader.offset
}

///|
pub fn Cursor::has_content(self : Cursor) -> Bool {
  self.remaining() > 0
}

///|
pub impl Read for Cursor with fn read_exact(self, length) {
  guard length >= 0 && length <= self.remaining() else {
    raise InvalidData("truncated binary")
  }
  let start = self.reader.offset
  self.reader.offset += length
  self.reader.bytes[start:self.reader.offset].to_owned()
}

///|
pub impl Read for Cursor with fn read_u8(self) {
  self.reader.byte().to_byte()
}

///|
/// Growable lib0 output. `to_bytes` returns an owned snapshot without consuming it.
pub struct ByteWriter {
  priv writer : Writer
}

///|
pub fn ByteWriter::ByteWriter() -> ByteWriter {
  { writer: { bytes: [], }, }
}

///|
pub fn ByteWriter::to_bytes(self : ByteWriter) -> Bytes {
  self.writer.finish()
}

///|
pub impl Write for ByteWriter with fn write_all(self, bytes) {
  for byte in bytes {
    self.writer.bytes.push(byte)
  }
}

///|
pub impl Write for ByteWriter with fn write_u8(self, byte) {
  self.writer.bytes.push(byte)
}

///|
pub extend Cursor with Read::{
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
pub extend ByteWriter with Write::{
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
