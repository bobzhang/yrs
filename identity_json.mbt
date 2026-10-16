///|
pub fn Id::to_json(self : Id) -> Json {
  {
    "client": Json::number(
      self.client.to_double(),
      repr=self.client.to_string(),
    ),
    "clock": Json::number(self.clock.to_double(), repr=self.clock.to_string()),
  }
}

///|
pub fn Id::from_json(value : Json) -> Id raise DecodeError {
  guard value is Object(fields) &&
    fields.get("client") is Some(client) &&
    fields.get("clock") is Some(clock) else {
    raise InvalidData("invalid item identity")
  }
  fn number(value : Json, maximum : UInt64) -> UInt64 raise DecodeError {
    guard value is Number(_, repr~) else {
      raise InvalidData("expected unsigned integer")
    }
    let repr = repr.unwrap_or(value.stringify())
    guard !repr.is_empty() else { raise InvalidData("empty integer") }
    let mut n = 0UL
    for ch in repr {
      guard ch >= '0' && ch <= '9' else {
        raise InvalidData("invalid unsigned integer")
      }
      let digit = (ch.to_int() - 48).to_uint64()
      guard n <= (maximum - digit) / 10UL else {
        raise InvalidData("integer overflow")
      }
      n = n * 10UL + digit
    }
    n
  }
  {
    client: number(client, 0xffff_ffff_ffff_ffffUL),
    clock: number(clock, 0xffff_ffffUL).to_uint(),
  }
}

///|
/// Rust serde representation of a logical branch identity.
pub fn BranchId::to_json(self : BranchId) -> Json {
  match self {
    Root(name) => { "Root": Json(name) }
    Nested(id) => { "Nested": id.to_json() }
  }
}

///|
pub fn BranchId::from_json(value : Json) -> BranchId raise DecodeError {
  guard value is Object(fields) && fields.length() == 1 else {
    raise InvalidData("invalid branch identity")
  }
  match fields.get("Root") {
    Some(String(name)) => Root(name)
    None =>
      match fields.get("Nested") {
        Some(value) => Nested(Id::from_json(value))
        None => raise InvalidData("invalid branch identity")
      }
    _ => raise InvalidData("invalid root identity")
  }
}

///|
pub fn[S] Hook::to_json(self : Hook[S]) -> Json {
  { "id": self.id().to_json(), "_tag": Json::null() }
}

///|
pub fn[S] Hook::from_json(value : Json) -> Hook[S] raise DecodeError {
  guard value is Object(fields) &&
    fields.get("id") is Some(id) &&
    fields.get("_tag") == Some(Json::null()) else {
    raise InvalidData("invalid hook")
  }
  Hook(BranchId::from_json(id))
}
