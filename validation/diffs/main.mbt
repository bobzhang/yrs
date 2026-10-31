///|
fn wire_byte(value : Json) -> Byte {
  guard value is Number(n, ..) else { abort("number") }
  n.to_int().to_byte()
}

///|
fn bytes_of(values : ArrayView[Json]) -> Bytes {
  Bytes::from_array(values.map(wire_byte))
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input)
    is { "packet": Array(packet), "hi": hi, "lo": lo, "cleanup": cleanup, .. } else {
    abort("request")
  }
  let doc = @yrs.Doc(client_id=1UL, cleanup_formatting=cleanup == Json(true))
  let text = doc.get_or_insert_text("text")
  doc.apply_update_v1(bytes_of(packet))
  fn snapshot(value : Json) -> @yrs.Snapshot? raise @yrs.DecodeError {
    match value {
      Array(bytes) => Some(@yrs.Snapshot::decode_v1(bytes_of(bytes)))
      _ => None
    }
  }
  let chunks = text.diff_range(
    @yrs.YChange::identity,
    hi?=snapshot(hi),
    lo?=snapshot(lo),
  )
  Json(
    chunks.map(fn(d) {
      let attrs = Map::from_array(
        d.attributes.map(fn(a) { (a.0, a.1.to_json()) }),
      )
      {
        "insert": d.insert.to_json(),
        "attrs": Json(attrs),
        "change": match d.ychange {
          None => Json::null()
          Some(c) =>
            Json([
              Json(if c.kind == Added { "Added" } else { "Removed" }),
              Json(c.id.client.to_string()),
              Json(c.id.clock),
            ])
        },
      }
    }),
  ).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
