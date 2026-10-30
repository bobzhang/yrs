///|
pub(all) suberror DecodeError {
  InvalidData(String)
} derive(Debug)

///|
pub extend DecodeError with Debug::{to_repr}

///|
priv struct Reader {
  bytes : Bytes
  mut offset : Int32
}

///|
fn Reader::byte(self : Reader) -> Int32 raise DecodeError {
  guard self.offset < self.bytes.length() else {
    raise InvalidData("truncated binary")
  }
  let result = self.bytes[self.offset].to_int()
  self.offset += 1
  result
}

///|
fn Reader::uint(self : Reader) -> UInt64 raise DecodeError {
  let mut value = 0UL
  for shift = 0; shift < 70; shift = shift + 7 {
    let b = self.byte()
    guard shift != 63 || b <= 1 else { raise InvalidData("integer overflow") }
    value = value | ((b & 127).to_uint64() << shift)
    if b < 128 {
      return value
    }
  }
  raise InvalidData("integer overflow")
}

///|
fn Reader::clock(self : Reader) -> UInt32 raise DecodeError {
  let value = self.uint()
  guard value <= 0xffff_ffffUL else { raise InvalidData("clock overflow") }
  value.to_uint()
}

///|
fn Reader::count(self : Reader) -> Int32 raise DecodeError {
  let value = self.uint()
  // Each element must consume at least one byte. Never preallocate from an
  // untrusted length; this also bounds loops over malformed nested values.
  guard value <= (self.bytes.length() - self.offset).to_uint64() else {
    raise InvalidData("length exceeds remaining bytes")
  }
  value.to_int()
}

///|
fn Reader::buffer_view(self : Reader) -> BytesView raise DecodeError {
  let len = self.count()
  let result = self.bytes[self.offset:self.offset + len]
  self.offset += len
  result
}

///|
fn Reader::buffer(self : Reader) -> Bytes raise DecodeError {
  self.buffer_view().to_owned()
}

///|
fn Reader::string(self : Reader) -> String raise DecodeError {
  @utf8.decode(self.buffer_view(), ignore_bom=false) catch {
    _ => raise InvalidData("invalid UTF-8")
  }
}

///|
fn Reader::id(self : Reader) -> Id raise DecodeError {
  { client: self.uint(), clock: self.clock(), }
}

///|
fn Reader::finish(self : Reader) -> Unit raise DecodeError {
  guard self.offset == self.bytes.length() else {
    raise InvalidData("trailing bytes")
  }
}

///|
priv struct Writer {
  bytes : Array[Byte]
}

///|
fn Writer::byte(self : Writer, value : Int32) -> Unit {
  self.bytes.push(value.to_byte())
}

///|
fn Writer::uint(self : Writer, value : UInt64) -> Unit {
  let mut value = value
  while value > 127UL {
    self.byte((value & 127UL).to_int() | 128)
    value = value >> 7
  }
  self.byte(value.to_int())
}

///|
fn Writer::buffer(self : Writer, bytes : Bytes) -> Unit {
  self.uint(bytes.length().to_uint64())
  for b in bytes {
    self.bytes.push(b)
  }
}

///|
fn Writer::string(self : Writer, value : String) -> Unit {
  self.buffer(@utf8.encode(value))
}

///|
fn Writer::id(self : Writer, id : Id) -> Unit {
  self.uint(id.client)
  self.uint(id.clock.to_uint64())
}

///|
fn Writer::finish(self : Writer) -> Bytes {
  Bytes::from_array(self.bytes[:])
}
