///|
fn unhex(s : String) -> Bytes {
  let bytes = []
  fn digit(c : UInt16) -> Int32 {
    if c <= '9' {
      c.to_int() - 48
    } else {
      c.to_int() - 87
    }
  }
  for i = 0; i < s.length(); i = i + 2 {
    bytes.push((digit(s[i]) * 16 + digit(s[i + 1])).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn number(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("number") }
  n.to_int()
}

///|
fn vector(state : @yrs.StateVector) -> Json {
  Json(state.entries().map(fn(p) { Json([Json(p.0.to_string()), Json(p.1)]) }))
}

///|
fn ranges(set : @yrs.IdSet) -> Json {
  Json(
    set
    .ranges()
    .map(fn(r) { Json([Json(r.0.to_string()), Json(r.1), Json(r.2)]) }),
  )
}

///|
fn run(input : String) -> String raise {
  let request = @json.parse(input)
  if request is { "sticky": sticky, "client": client, "clock": clock, .. } {
    let sticky = @yrs.StickyIndex::from_json(sticky)
    let vector = @yrs.StateVector(entries=[
      (number(client).to_uint64(), number(clock).reinterpret_as_uint()),
    ])
    fn bytes(value : Bytes) -> Json {
      Json([ for b in value.iter() => Json(b.to_int()) ])
    }
    let encoded = sticky.encode_v2()
    guard @yrs.StickyIndex::decode_v2(encoded) == sticky else {
      abort("sticky roundtrip")
    }
    return (
      { "sticky": bytes(encoded), "vector": bytes(vector.encode_v2()) } : Json).stringify()
  }
  guard request is Array([String(hex), Array(pairs)]) else { abort("request") }
  let update = @yrs.Update::decode_v1(unhex(hex))
  let state = @yrs.StateVector(
    entries=pairs.map(fn(p) {
      guard p is Array([c, n]) else { abort("pair") }
      (number(c).to_uint64(), number(n).reinterpret_as_uint())
    }),
  )
  (
    {
      "empty": Json(update.is_empty()),
      "extends": Json(update.extends(state)),
      "state": vector(update.state_vector()),
      "lower": vector(update.state_vector_lower()),
      "live": ranges(update.insertions()),
      "all": ranges(update.insertions(include_deleted=true)),
      "deleted": ranges(update.delete_set()),
    } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
