///|
/// Type conversion failures for the lossless CRDT value decoder.
pub(all) suberror ValueDecodeError {
  TypeMismatch(String)
  OutOfRange(String)
} derive(Debug)

///|
pub extend ValueDecodeError with Debug::{to_repr}

///|
/// Application-defined deserialization from lib0 values, without an intermediate
/// JSON conversion. Implement this for structured application types.
pub(open) trait FromAny {
  fn from_any(Any) -> Self raise ValueDecodeError
}

///|
pub fn[T : FromAny] from_any(value : Any) -> T raise ValueDecodeError {
  T::from_any(value)
}

///|
pub impl FromAny for Any with fn from_any(value) {
  value
}

///|
pub impl FromAny for Bool with fn from_any(value) {
  guard value is Bool(value) else { raise TypeMismatch("Bool") }
  value
}

///|
pub impl FromAny for String with fn from_any(value) {
  guard value is String(value) else { raise TypeMismatch("String") }
  value
}

///|
pub impl FromAny for Bytes with fn from_any(value) {
  guard value is Buffer(value) else { raise TypeMismatch("Bytes") }
  value
}

///|
pub impl FromAny for Int64 with fn from_any(value) {
  match value {
    Integer(value) => value
    Float(value) => {
      guard value >= -9223372036854775808.0 && value <= 9223372036854775808.0 else {
        raise TypeMismatch("Int64")
      }
      // Rust's float-to-integer cast saturates at this rounded endpoint.
      if value == 9223372036854775808.0 {
        return 9223372036854775807L
      }
      let integer = value.to_int64()
      guard integer.to_double() == value else { raise TypeMismatch("Int64") }
      integer
    }
    _ => raise TypeMismatch("Int64")
  }
}

///|
pub impl FromAny for Int32 with fn from_any(value) {
  let integer : Int64 = from_any(value)
  guard integer >= -2147483648L && integer <= 2147483647L else {
    raise OutOfRange("Int")
  }
  integer.to_int()
}

///|
pub impl FromAny for UInt32 with fn from_any(value) {
  let integer : Int64 = from_any(value)
  guard integer >= 0L && integer <= 4294967295L else {
    raise OutOfRange("UInt")
  }
  integer.to_int().reinterpret_as_uint()
}

///|
pub impl FromAny for UInt64 with fn from_any(value) {
  let integer : Int64 = from_any(value)
  guard integer >= 0L else { raise OutOfRange("UInt64") }
  integer.reinterpret_as_uint64()
}

///|
pub impl FromAny for Double with fn from_any(value) {
  match value {
    Float(value) => value
    Integer(value) => {
      let number = value.to_double()
      if value == 9223372036854775807L {
        return number
      }
      guard number < 9223372036854775808.0 && number.to_int64() == value else {
        raise TypeMismatch("Double")
      }
      number
    }
    _ => raise TypeMismatch("Double")
  }
}

///|
pub impl FromAny for Float with fn from_any(value) {
  let number : Double = from_any(value)
  Float::from_double(number)
}

///|
pub impl[T : FromAny] FromAny for T? with fn from_any(value) {
  match value {
    Null | Undefined => None
    _ => Some(T::from_any(value))
  }
}

///|
pub impl[T : FromAny] FromAny for Array[T] with fn from_any(value) {
  guard value is Array(values) else { raise TypeMismatch("Array") }
  let result = []
  for value in values {
    result.push(T::from_any(value))
  }
  result
}

///|
pub impl[T : FromAny] FromAny for Map[String, T] with fn from_any(value) {
  guard value is Object(values) else { raise TypeMismatch("Map") }
  let result : Map[String, T] = Map([])
  for (key, value) in values {
    result[key] = T::from_any(value)
  }
  result
}

///|
pub impl[A : FromAny, B : FromAny] FromAny for (A, B) with fn from_any(value) {
  guard value is Array(values) && values.length() == 2 else {
    raise TypeMismatch("pair")
  }
  (A::from_any(values[0]), B::from_any(values[1]))
}

///|
pub impl FromAny for Unit with fn from_any(value) {
  guard value is Null || value is Undefined else { raise TypeMismatch("Unit") }
}

///|
pub extend Any with FromAny::{from_any}
