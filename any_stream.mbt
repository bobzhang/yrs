///|
/// Encode one lib0 value through an application-supplied byte writer.
/// Large integers retain exact bits, as with Any.encode, rather than selecting
/// Rust's potentially lossy floating representation at the Int64 endpoints.
pub fn Any::encode_to(self : Any, writer : &Write) -> Unit {
  match self {
    Undefined => writer.write_u8(127)
    Null => writer.write_u8(126)
    Bool(value) => writer.write_u8(if value { 120 } else { 121 })
    Integer(value) =>
      if value >= -2147483647L && value <= 2147483647L {
        writer.write_u8(125)
        writer.write_var_int(value)
      } else {
        writer.write_u8(122)
        writer.write_i64(value)
      }
    Float(value) =>
      if Float::from_double(value).to_double() == value {
        writer.write_u8(124)
        writer.write_f32(Float::from_double(value))
      } else {
        writer.write_u8(123)
        writer.write_f64(value)
      }
    String(value) => {
      writer.write_u8(119)
      writer.write_string(value)
    }
    Buffer(value) => {
      writer.write_u8(116)
      writer.write_buf(value)
    }
    Array(values) => {
      writer.write_u8(117)
      writer.write_var_uint(values.length().to_uint64())
      for value in values {
        value.encode_to(writer)
      }
    }
    Object(entries) => {
      writer.write_u8(118)
      writer.write_var_uint(entries.length().to_uint64())
      for (key, value) in entries {
        writer.write_string(key)
        value.encode_to(writer)
      }
    }
  }
}

///|
/// Decode one value and leave the following bytes available to the reader.
/// The value budget bounds compressed container expansion before iteration.
pub fn Any::decode_from(
  reader : &Read,
  max_values~ : Int32 = 1000000,
) -> Any raise DecodeError {
  guard max_values >= 0 else { raise InvalidData("negative value budget") }
  let mut remaining = max_values
  fn count() -> Int32 raise DecodeError {
    let n = reader.read_var_uint()
    guard n <= remaining.to_uint64() else {
      raise InvalidData("lib0 value exceeds decode budget")
    }
    n.to_int()
  }
  fn decode(depth : Int32) -> Any raise DecodeError {
    guard depth <= 256 else {
      raise InvalidData("lib0 value nesting exceeds 256")
    }
    guard remaining > 0 else {
      raise InvalidData("lib0 value exceeds decode budget")
    }
    remaining -= 1
    match reader.read_u8().to_int() {
      127 => Undefined
      126 => Null
      125 => Integer(reader.read_var_int())
      124 => Float(reader.read_f32().to_double())
      123 => Float(reader.read_f64())
      122 => Integer(reader.read_i64())
      121 => Bool(false)
      120 => Bool(true)
      119 => String(reader.read_string())
      116 => Buffer(reader.read_buf())
      117 => {
        let values = []
        for _ in 0..<count() {
          values.push(decode(depth + 1))
        }
        Array(ReadOnlyArray::from_array(values[:]))
      }
      118 => {
        let values : Map[String, Any] = Map([])
        for _ in 0..<count() {
          let key = reader.read_string()
          values[key] = decode(depth + 1)
        }
        Object(ReadOnlyArray::from_array(values.to_array()[:]))
      }
      _ => raise InvalidData("unknown lib0 value tag")
    }
  }
  decode(0)
}
