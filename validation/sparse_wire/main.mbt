///|
fn bytes(value : Json) -> Bytes {
  guard value is Array(values) else { abort("bytes") }
  Bytes::from_array(
    values.map(fn(value) {
      guard value is Number(n, ..) else { abort("byte") }
      n.to_int().to_byte()
    }),
  )
}

///|
fn array(value : Bytes) -> Json {
  Json(value.to_array().map(fn(byte) { Json(byte.to_int()) }))
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input) is Object(fields) else { abort("request") }
  guard fields.get("packets") is Some(Array(packets)) else { abort("packets") }
  let v2 = fields.get("version") == Some(Json(2))
  if fields.get("apply") == Some(Json(true)) {
    let doc = @yrs.Doc(
      client_id=99UL,
      skip_gc=fields.get("gc") != Some(Json(true)),
    )
    for packet in packets {
      if v2 {
        doc.apply_update_v2(bytes(packet))
      } else {
        doc.apply_update_v1(bytes(packet))
      }
    }
    return (
      {
        "text": Json(doc.get_or_insert_text("text").get_string()),
        "array": @yrs.Out::Array(doc.get_or_insert_array("array")).to_json(),
        "map": @yrs.Out::Map(doc.get_or_insert_map("map")).to_json(),
        "state": array(doc.state_vector().encode_v1()),
        "wire": array(doc.encode_state_as_update_v2()),
        "pending": Json(doc.has_pending_updates()),
      } : Json).stringify()
  }
  let packets = packets.map(bytes)
  let remote = bytes(fields.get("remote").unwrap())
  let merged = if v2 {
    @yrs.merge_updates_v2(packets)
  } else {
    @yrs.merge_updates_v1(packets)
  }
  let diff = if v2 {
    @yrs.diff_updates_v2(merged, remote)
  } else {
    @yrs.diff_updates_v1(merged, remote)
  }
  let vector = if v2 {
    @yrs.encode_state_vector_from_update_v2(merged)
  } else {
    @yrs.encode_state_vector_from_update_v1(merged)
  }
  (
    { "merged": array(merged), "diff": array(diff), "vector": array(vector) } :
    Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
