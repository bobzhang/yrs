///|
impl Read with fn read_u8(self) {
  self.read_exact(1)[0]
}

///|
fn[R : Read] read_fixed(
  reader : R,
  width : Int32,
  big_endian : Bool,
) -> UInt64 raise DecodeError {
  let bytes = reader.read_exact(width)
  let mut value = 0UL
  for i in 0..<width {
    let shift = if big_endian { width - i - 1 } else { i }
    value = value | (bytes[i].to_uint64() << (shift * 8))
  }
  value
}

///|
impl Read with fn read_u16(self) {
  let bytes = self.read_exact(2)
  (bytes[0].to_uint() | (bytes[1].to_uint() << 8)).to_uint16()
}

///|
impl Read with fn read_u32(self) {
  let bytes = self.read_exact(4)
  bytes[0].to_uint() |
  (bytes[1].to_uint() << 8) |
  (bytes[2].to_uint() << 16) |
  (bytes[3].to_uint() << 24)
}

///|
impl Read with fn read_u32_be(self) {
  let bytes = self.read_exact(4)
  (bytes[0].to_uint() << 24) |
  (bytes[1].to_uint() << 16) |
  (bytes[2].to_uint() << 8) |
  bytes[3].to_uint()
}

///|
impl Read with fn read_u64(self) {
  read_fixed(self, 8, true)
}

///|
impl Read with fn read_i64(self) {
  self.read_u64().reinterpret_as_int64()
}

///|
impl Read with fn read_f32(self) {
  Float::reinterpret_from_uint(self.read_u32_be())
}

///|
impl Read with fn read_f64(self) {
  self.read_u64().reinterpret_as_double()
}

///|
impl Read with fn read_var_uint(self) {
  let mut value = 0UL
  for shift = 0; shift < 70; shift = shift + 7 {
    let byte = self.read_u8().to_int()
    guard shift != 63 || byte <= 1 else {
      raise InvalidData("integer overflow")
    }
    value = value | ((byte & 127).to_uint64() << shift)
    if byte < 128 {
      return value
    }
  }
  raise InvalidData("integer overflow")
}

///|
impl Read with fn read_var_signed(self) {
  let first = self.read_u8().to_int()
  let negative = (first & 64) != 0
  let mut bits = (first & 63).to_uint64()
  if first >= 128 {
    for shift = 6; shift < 70; shift = shift + 7 {
      let byte = self.read_u8().to_int()
      guard shift < 62 || byte <= 3 else {
        raise InvalidData("signed integer overflow")
      }
      bits = bits | ((byte & 127).to_uint64() << shift)
      if byte < 128 {
        break
      }
    }
  }
  guard bits <=
    (if negative { 0x8000_0000_0000_0000UL } else { 0x7fff_ffff_ffff_ffffUL }) else {
    raise InvalidData("signed integer overflow")
  }
  ((if negative { 0UL - bits } else { bits }).reinterpret_as_int64(), negative)
}

///|
impl Read with fn read_var_int(self) {
  self.read_var_signed().0
}

///|
impl Read with fn read_buf(self) {
  let length = self.read_var_uint()
  guard length <= 0x7fff_ffffUL else {
    raise InvalidData("buffer length overflow")
  }
  self.read_exact(length.to_int())
}

///|
impl Read with fn read_string(self) {
  @utf8.decode(self.read_buf(), ignore_bom=false) catch {
    _ => raise InvalidData("invalid UTF-8")
  }
}
