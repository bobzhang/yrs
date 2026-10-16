///|
/// Read a JSON-like lib0 value without losing integer or binary representations.
pub fn Out::to_any(self : Out) -> Any {
  match self {
    Value(value) => value
    Array(value) =>
      Array(ReadOnlyArray::from_array(value.to_array().map(Out::to_any)))
    Map(value) =>
      Object(
        ReadOnlyArray::from_array(
          value.entries().map(fn(p) { (p.0, p.1.to_any()) }),
        ),
      )
    Text(value) => String(value.get_string())
    XmlElement(value) => String(value.get_string())
    XmlFragment(value) => String(value.get_string())
    XmlText(value) => String(value.get_string())
    Subdoc(value) => Object([("guid", String(value.guid()))])
    UndefinedRef(_) | WeakLink(_) => Undefined
  }
}

///|
/// Decode a collection value into an application type. Missing entries are null,
/// matching upstream get_as. Implement FromAny for application records.
pub fn[T : FromAny] MapRef::get_as(
  self : MapRef,
  key : String,
) -> T raise ValueDecodeError {
  from_any(self.get(key).map(Out::to_any).unwrap_or(Null))
}

///|
pub fn[T : FromAny] ArrayRef::get_as(
  self : ArrayRef,
  index : Int32,
) -> T raise ValueDecodeError {
  from_any(self.get(index).map(Out::to_any).unwrap_or(Null))
}

///|
/// Decode with MoonBit's JSON conventions instead (e.g. Int64 uses a string).
pub fn[T : @json.FromJson] MapRef::get_json_as(
  self : MapRef,
  key : String,
) -> T raise @json.JsonDecodeError {
  @json.from_json(self.get(key).map(Out::to_json).unwrap_or(Json::null()))
}

///|
pub fn[T : @json.FromJson] ArrayRef::get_json_as(
  self : ArrayRef,
  index : Int32,
) -> T raise @json.JsonDecodeError {
  @json.from_json(self.get(index).map(Out::to_json).unwrap_or(Json::null()))
}
