///|
/// Extensible lib0 byte input. Implement `read_exact`; other methods have defaults.
/// Fixed u16/u32 are little endian, other fixed numbers are big endian.
/// Variable integers use explicit signed/unsigned methods rather than Rust generics.
pub(open) trait Read {
  fn read_exact(Self, Int32) -> Bytes raise DecodeError
  fn read_u8(Self) -> Byte raise DecodeError = _
  fn read_u16(Self) -> UInt16 raise DecodeError = _
  fn read_u32(Self) -> UInt32 raise DecodeError = _
  fn read_u32_be(Self) -> UInt32 raise DecodeError = _
  fn read_u64(Self) -> UInt64 raise DecodeError = _
  fn read_i64(Self) -> Int64 raise DecodeError = _
  fn read_f32(Self) -> Float raise DecodeError = _
  fn read_f64(Self) -> Double raise DecodeError = _
  fn read_var_uint(Self) -> UInt64 raise DecodeError = _
  fn read_var_int(Self) -> Int64 raise DecodeError = _
  fn read_var_signed(Self) -> (Int64, Bool) raise DecodeError = _
  fn read_buf(Self) -> Bytes raise DecodeError = _
  fn read_string(Self) -> String raise DecodeError = _
}

///|
/// Extensible lib0 byte output. Implement `write_all`; defaults build on it.
/// `write_var_signed` accepts (value, negative), preserving negative zero.
pub(open) trait Write {
  fn write_all(Self, Bytes) -> Unit
  fn write_u8(Self, Byte) -> Unit = _
  fn write_u16(Self, UInt16) -> Unit = _
  fn write_u32(Self, UInt32) -> Unit = _
  fn write_u32_be(Self, UInt32) -> Unit = _
  fn write_u64(Self, UInt64) -> Unit = _
  fn write_i64(Self, Int64) -> Unit = _
  fn write_f32(Self, Float) -> Unit = _
  fn write_f64(Self, Double) -> Unit = _
  fn write_var_uint(Self, UInt64) -> Unit = _
  fn write_var_int(Self, Int64) -> Unit = _
  fn write_var_signed(Self, (Int64, Bool)) -> Unit = _
  fn write_buf(Self, Bytes) -> Unit = _
  fn write_string(Self, String) -> Unit = _
}
