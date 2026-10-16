///|
pub(all) suberror ValueEncodeError {
  UnrepresentableInt
  Custom(String)
} derive(Debug)

///|
pub extend ValueEncodeError with Debug::{to_repr}

///|
/// Serialize application data to lib0 values without passing through JSON.
/// Implement this trait for records and variants using Object/Array/String.
/// Map keys are restricted to String by the built-in implementation.
pub(open) trait ToAny {
  fn to_any(Self) -> Any raise ValueEncodeError
}

///|
pub fn[T : ToAny] to_any(value : T) -> Any raise ValueEncodeError {
  value.to_any()
}

///|
pub impl ToAny for Bool with fn to_any(self) {
  Bool(self)
}

///|
pub impl ToAny for String with fn to_any(self) {
  String(self)
}

///|
pub impl ToAny for Bytes with fn to_any(self) {
  Buffer(self)
}

///|
pub impl ToAny for Int64 with fn to_any(self) {
  Integer(self)
}

///|
pub impl ToAny for Int32 with fn to_any(self) {
  Integer(self.to_int64())
}

///|
pub impl ToAny for UInt32 with fn to_any(self) {
  Integer(self.to_uint64().reinterpret_as_int64())
}

///|
pub impl ToAny for UInt64 with fn to_any(self) {
  guard self <= 0x7fff_ffff_ffff_ffffUL else { raise UnrepresentableInt }
  Integer(self.reinterpret_as_int64())
}

///|
pub impl ToAny for Byte with fn to_any(self) {
  Integer(self.to_int().to_int64())
}

///|
pub impl ToAny for UInt16 with fn to_any(self) {
  Integer(self.to_int().to_int64())
}

///|
pub impl ToAny for Char with fn to_any(self) {
  String(self.to_string())
}

///|
pub impl ToAny for Double with fn to_any(self) {
  Float(self)
}

///|
pub impl ToAny for Float with fn to_any(self) {
  Float(self.to_double())
}

///|
pub impl ToAny for Unit with fn to_any(_self) {
  Null
}

///|
pub impl[T : ToAny] ToAny for T? with fn to_any(self) {
  match self {
    Some(value) => value.to_any()
    None => Null
  }
}

///|
pub impl[T : ToAny] ToAny for Array[T] with fn to_any(self) {
  let values = self.map(value => value.to_any())
  Array(ReadOnlyArray::from_array(values[:]))
}

///|
pub impl[T : ToAny] ToAny for ReadOnlyArray[T] with fn to_any(self) {
  let values = []
  for value in self {
    values.push(value.to_any())
  }
  Array(ReadOnlyArray::from_array(values[:]))
}

///|
pub impl[T : ToAny] ToAny for Map[String, T] with fn to_any(self) {
  let values = []
  for key, value in self {
    values.push((key, value.to_any()))
  }
  Object(ReadOnlyArray::from_array(values[:]))
}

///|
pub impl[A : ToAny, B : ToAny] ToAny for (A, B) with fn to_any(self) {
  Array([self.0.to_any(), self.1.to_any()])
}

///|
/// Rust's serde adapter maps Undefined to Null, recursively, and normalizes
/// integral floating-point values. Direct Any.encode preserves Undefined.
pub impl ToAny for Any with fn to_any(self) {
  match self {
    Undefined | Null => Null
    Float(n) => {
      // Match Number::as_i64, including its saturating rounded upper endpoint.
      let integer : Int64? = Some(from_any(self)) catch { _ => None }
      match integer {
        Some(value) => Integer(value)
        None => Float(n)
      }
    }
    Array(values) => to_any(values)
    Object(entries) => to_any(Map::from_array(entries.iter().to_array()))
    _ => self
  }
}

///|
pub extend Any with ToAny::{to_any}
