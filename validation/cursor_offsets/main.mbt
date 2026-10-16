///|
fn run(input : String) -> String raise {
  guard @json.parse(input)
    is Array([String(value), Number(u, ..), Number(b, ..), before]) else {
    abort("request")
  }
  let utf = @yrs.Doc(client_id=1UL)
  let bytes = @yrs.Doc(client_id=2UL, offset_kind=Bytes)
  let a = utf.get_or_insert_text("text")
  let c = bytes.get_or_insert_text("text")
  a.insert(0, value)
  bytes.apply_update_v1(utf.encode_state_as_update_v1())
  let assoc = if before == Json(true) { @yrs.Assoc::Before } else { After }
  let left = a.sticky_index(u.to_int(), assoc~)
  let right = c.sticky_index(b.to_int(), assoc~)
  let rows = []
  for _ in 0..<4 {
    rows.push(
      (
        {
          "text": Json(a.get_string()),
          "utf": left.map(fn(s) { s.to_json() }).unwrap_or(Json::null()),
          "bytes": right.map(fn(s) { s.to_json() }).unwrap_or(Json::null()),
          "utf_offset": left
          .bind(fn(s) { s.get_offset(utf) })
          .map(fn(o) { Json(o.index) })
          .unwrap_or(Json::null()),
          "byte_offset": left
          .bind(fn(s) { s.get_offset(bytes) })
          .map(fn(o) { Json(o.index) })
          .unwrap_or(Json::null()),
          "byte_own_offset": right
          .bind(fn(s) { s.get_offset(bytes) })
          .map(fn(o) { Json(o.index) })
          .unwrap_or(Json::null()),
        } : Json),
    )
    a.insert(0, "é🦀")
    bytes.apply_update_v2(utf.encode_state_as_update_v2())
  }
  Json(rows).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
