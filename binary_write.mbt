///|
impl Write with fn write_u8(self, value) {
  self.write_all(Bytes::from_array([value]))
}

///|
fn[W : Write] write_fixed(
  writer : W,
  value : UInt64,
  width : Int32,
  big_endian : Bool,
) -> Unit {
  let bytes = Bytes::makei(width, fn(i) {
    let shift = if big_endian { width - i - 1 } else { i }
    ((value >> (shift * 8)) & 255UL).to_int().to_byte()
  })
  writer.write_all(bytes)
}

///|
impl Write with fn write_u16(self, value) {
  write_fixed(self, value.to_uint().to_uint64(), 2, false)
}

///|
impl Write with fn write_u32(self, value) {
  write_fixed(self, value.to_uint64(), 4, false)
}

///|
impl Write with fn write_u32_be(self, value) {
  write_fixed(self, value.to_uint64(), 4, true)
}

///|
impl Write with fn write_u64(self, value) {
  write_fixed(self, value, 8, true)
}

///|
impl Write with fn write_i64(self, value) {
  self.write_u64(value.reinterpret_as_uint64())
}

///|
impl Write with fn write_f32(self, value) {
  self.write_u32_be(value.reinterpret_as_uint())
}

///|
impl Write with fn write_f64(self, value) {
  self.write_u64(value.reinterpret_as_uint64())
}

///|
impl Write with fn write_var_uint(self, number) {
  let mut value = number
  while value > 127UL {
    self.write_u8(((value & 127UL).to_int() | 128).to_byte())
    value = value >> 7
  }
  self.write_u8(value.to_int().to_byte())
}

///|
impl Write with fn write_var_int(self, value) {
  self.write_var_signed((value, value < 0L))
}

///|
impl Write with fn write_var_signed(self, signed) {
  let (number, negative) = signed
  guard number == 0L || negative == (number < 0L) else {
    abort("inconsistent integer sign")
  }
  let mut magnitude = if negative {
    0UL - number.reinterpret_as_uint64()
  } else {
    number.reinterpret_as_uint64()
  }
  self.write_u8(
    ((magnitude & 63UL).to_int() |
    (if negative { 64 } else { 0 }) |
    (if magnitude > 63UL { 128 } else { 0 })).to_byte(),
  )
  magnitude = magnitude >> 6
  while magnitude > 0UL {
    self.write_u8(
      ((magnitude & 127UL).to_int() | (if magnitude > 127UL { 128 } else { 0 })).to_byte(),
    )
    magnitude = magnitude >> 7
  }
}

///|
impl Write with fn write_buf(self, bytes) {
  self.write_var_uint(bytes.length().to_uint64())
  self.write_all(bytes)
}

///|
impl Write with fn write_string(self, text) {
  self.write_buf(@utf8.encode(text))
}
