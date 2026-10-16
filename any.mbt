///|
/// Immutable lib0 values. Arrays and objects use read-only storage so values
/// cannot be changed behind the CRDT's back after insertion.
pub(all) enum Any {
  Undefined
  Null
  Bool(Bool)
  Integer(Int64)
  Float(Double)
  String(String)
  Array(ReadOnlyArray[Any])
  Object(ReadOnlyArray[(String, Any)])
  Buffer(Bytes)
} derive(Debug)

///|
pub impl Eq for Any with fn equal(self, other) {
  fn number(integer : Int64, floating : Double) -> Bool {
    let converted = integer.to_double()
    if converted != floating {
      return false
    }
    // Match Rust's lossless integer conversion check, including its saturating
    // float-to-i64 conversion at the upper endpoint.
    if converted == 9223372036854775808.0 {
      return integer == 9223372036854775807L
    }
    converted.to_int64() == integer
  }
  match (self, other) {
    (Undefined, Undefined) | (Null, Null) => true
    (Bool(a), Bool(b)) => a == b
    (Integer(a), Integer(b)) => a == b
    (Float(a), Float(b)) => a == b
    (Integer(a), Float(b)) | (Float(b), Integer(a)) => number(a, b)
    (String(a), String(b)) => a == b
    (Buffer(a), Buffer(b)) => a == b
    (Array(a), Array(b)) => a == b
    (Object(a), Object(b)) => {
      let left = Map::from_array(a.iter().to_array())
      let right = Map::from_array(b.iter().to_array())
      left.length() == right.length() &&
      left.iter().all(fn(pair) { right.get(pair.0) == Some(pair.1) })
    }
    _ => false
  }
}

///|
pub extend Any with Eq::{equal, not_equal}

///|
pub extend Any with Debug::{to_repr}

///|
fn Writer::signed(self : Writer, number : Int64) -> Unit {
  let negative = number < 0L
  let mut magnitude = if negative {
    0UL - number.reinterpret_as_uint64()
  } else {
    number.reinterpret_as_uint64()
  }
  self.byte(
    (magnitude & 63UL).to_int() |
    (if negative { 64 } else { 0 }) |
    (if magnitude > 63UL { 128 } else { 0 }),
  )
  magnitude = magnitude >> 6
  while magnitude > 0UL {
    self.byte(
      (magnitude & 127UL).to_int() | (if magnitude > 127UL { 128 } else { 0 }),
    )
    magnitude = magnitude >> 7
  }
}

///|
fn Reader::signed(self : Reader) -> Int64 raise DecodeError {
  let first = self.byte()
  let negative = (first & 64) != 0
  let mut bits = (first & 63).to_uint64()
  if first >= 128 {
    for shift = 6; shift < 70; shift = shift + 7 {
      let b = self.byte()
      guard shift < 62 || b <= 3 else {
        raise InvalidData("signed integer overflow")
      }
      bits = bits | ((b & 127).to_uint64() << shift)
      if b < 128 {
        break
      }
    }
  }
  guard bits <=
    (if negative { 0x8000_0000_0000_0000UL } else { 0x7fff_ffff_ffff_ffffUL }) else {
    raise InvalidData("signed integer overflow")
  }
  (if negative { 0UL - bits } else { bits }).reinterpret_as_int64()
}

///|
fn Writer::big(self : Writer, bits : UInt64, width : Int32) -> Unit {
  for i = width - 1; i >= 0; i = i - 1 {
    self.byte(((bits >> (i * 8)) & 255UL).to_int())
  }
}

///|
fn Reader::big(self : Reader, width : Int32) -> UInt64 raise DecodeError {
  let mut bits = 0UL
  for _ in 0..<width {
    bits = (bits << 8) | self.byte().to_uint64()
  }
  bits
}

///|
fn Writer::any(self : Writer, value : Any) -> Unit {
  match value {
    Undefined => self.byte(127)
    Null => self.byte(126)
    Bool(b) => self.byte(if b { 120 } else { 121 })
    Integer(n) =>
      if n >= -2147483647L && n <= 2147483647L {
        self.byte(125)
        self.signed(n)
      } else {
        // BigInt preserves every bit of an Int64, including values outside the
        // exact floating-point range. This is a valid lib0 encoding even when a
        // producer might choose a shorter floating-point representation.
        self.byte(122)
        self.big(n.reinterpret_as_uint64(), 8)
      }
    Float(n) =>
      if Float::from_double(n).to_double() == n {
        self.byte(124)
        self.big(Float::from_double(n).reinterpret_as_uint().to_uint64(), 4)
      } else {
        self.byte(123)
        self.big(n.reinterpret_as_uint64(), 8)
      }
    String(s) => {
      self.byte(119)
      self.string(s)
    }
    Buffer(b) => {
      self.byte(116)
      self.buffer(b)
    }
    Array(values) => {
      self.byte(117)
      self.uint(values.length().to_uint64())
      for value in values {
        self.any(value)
      }
    }
    Object(entries) => {
      self.byte(118)
      self.uint(entries.length().to_uint64())
      for (key, value) in entries {
        self.string(key)
        self.any(value)
      }
    }
  }
}

///|
fn Reader::any(self : Reader, depth~ : Int32 = 0) -> Any raise DecodeError {
  guard depth <= 256 else {
    raise InvalidData("lib0 value nesting exceeds 256")
  }
  match self.byte() {
    127 => Undefined
    126 => Null
    125 => Integer(self.signed())
    124 =>
      Float(Float::reinterpret_from_uint(self.big(4).to_uint()).to_double())
    123 => Float(self.big(8).reinterpret_as_double())
    122 => Integer(self.big(8).reinterpret_as_int64())
    121 => Bool(false)
    120 => Bool(true)
    119 => String(self.string())
    116 => Buffer(self.buffer())
    117 => {
      let values = []
      let count = self.count()
      for _ in 0..<count {
        values.push(self.any(depth=depth + 1))
      }
      Array(ReadOnlyArray::from_array(values[:]))
    }
    118 => {
      let values : Map[String, Any] = Map([])
      let count = self.count()
      for _ in 0..<count {
        let key = self.string()
        values[key] = self.any(depth=depth + 1)
      }
      Object(ReadOnlyArray::from_array(values.to_array()[:]))
    }
    _ => raise InvalidData("unknown lib0 value tag")
  }
}

///|
pub fn Any::encode(self : Any) -> Bytes {
  let writer : Writer = { bytes: [], }
  writer.any(self)
  writer.finish()
}

///|
pub fn Any::decode(bytes : Bytes) -> Any raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let value = reader.any()
  reader.finish()
  value
}

///|
pub fn Any::from_json(value : Json) -> Any {
  match value {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) =>
      if n >= -9007199254740991.0 &&
        n <= 9007199254740991.0 &&
        n.to_int64().to_double() == n {
        Integer(n.to_int64())
      } else {
        Float(n)
      }
    String(s) => String(s)
    Array(values) =>
      Array(ReadOnlyArray::from_array(values.map(Any::from_json)[:]))
    Object(values) =>
      Object(
        ReadOnlyArray::from_array(
          values.to_array().map(fn(pair) { (pair.0, Any::from_json(pair.1)) })[:],
        ),
      )
  }
}

///|
/// JSON projection. Undefined becomes null and buffers become byte arrays.
/// Use the binary codec to preserve these distinctions and exact wide integers.
pub fn Any::to_json(self : Any) -> Json {
  match self {
    Undefined | Null => Json::null()
    Bool(b) => Json(b)
    Integer(n) => Json::number(n.to_double(), repr=n.to_string())
    Float(n) => Json(n)
    String(s) => Json(s)
    Buffer(b) => Json(b.to_array().map(fn(b) { b.to_int() }))
    Array(values) => Json(values.iter().map(Any::to_json).to_array())
    Object(entries) => {
      let values : Map[String, Json] = Map([])
      for (key, value) in entries {
        values[key] = value.to_json()
      }
      Json(values)
    }
  }
}
