///|
fn bytes(value : Json) -> Bytes {
  guard value is Array(values) else { abort("bytes") }
  Bytes::from_array(
    values.map(fn(v) {
      guard v is Number(n, ..) else { abort("byte") }
      n.to_int().to_byte()
    })[:],
  )
}

///|
fn state(s : @yrs.StateVector) -> Json {
  Json(s.entries().map(fn(p) { Json([Json(p.0.to_int()), Json(p.1)]) }))
}

///|
fn ranges(s : @yrs.IdSet) -> Json {
  Json(
    s.ranges().map(fn(r) { Json([Json(r.0.to_int()), Json(r.1), Json(r.2)]) }),
  )
}

///|
fn info(u : @yrs.Update) -> Json {
  {
    "state": state(u.state_vector()),
    "lower": state(u.state_vector_lower()),
    "deleted": ranges(u.delete_set()),
    "inserted": ranges(u.insertions(include_deleted=true)),
    "empty": Json(u.is_empty()),
  }
}

///|
fn view(doc : @yrs.Doc, check_retained : Bool) -> Json raise {
  let wire = doc.encode_diff_v1(@yrs.StateVector())
  let retained = if check_retained {
    let peer = @yrs.Doc(client_id=99UL)
    peer.apply_update_v1(
      doc.encode_state_from_snapshot_v1(@yrs.Snapshot(state=doc.state_vector())),
    )
    Json(peer.get_or_insert_text("text").get_string())
  } else {
    Json::null()
  }
  {
    "retained": retained,
    "missing": Json(doc.has_pending_updates()),
    "state": state(doc.state_vector()),
    "text": doc
    .get_text("text")
    .map(fn(t) { Json(t.get_string()) })
    .unwrap_or(Json::null()),
    "full": info(@yrs.Update::decode_v1(doc.encode_state_as_update_v1())),
    "diff": info(@yrs.Update::decode_v1(wire)),
    "wire": Json(wire.iter().map(fn(b) { Json(b.to_int()) }).to_array()),
  }
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input) is Object(fields) &&
    fields.get("packets") is Some(Array(packets)) else {
    abort("packets")
  }
  let doc = @yrs.Doc(client_id=1UL)
  for packet in packets {
    doc.apply_update_v1(bytes(packet))
  }
  if fields.get("gc") is Some(Array(ranges)) {
    let set = @yrs.IdSet()
    for range in ranges {
      guard range is Array([Number(c, ..), Number(s, ..), Number(n, ..)]) else {
        abort("scope")
      }
      set.insert(
        { client: c.to_uint64(), clock: s.to_int().reinterpret_as_uint(), },
        n.to_int().reinterpret_as_uint(),
      )
    }
    doc.gc(delete_set=set)
  }
  let before = view(doc, fields.contains("gc"))
  let saved = doc.prune_pending()
  let pending = saved.map(info).unwrap_or(Json::null())
  let after = view(doc, fields.contains("gc"))
  if saved is Some(update) {
    doc.apply_update(update)
  }
  let restored = view(doc, fields.contains("gc"))
  if fields.get("complete") is Some(Array(packets)) {
    for packet in packets {
      doc.apply_update_v1(bytes(packet))
    }
  }
  let completed = view(doc, fields.contains("gc"))
  (
    {
      "before": before,
      "pending": pending,
      "after": after,
      "restored": restored,
      "settled": restored,
      "completed": completed,
      "retry_rounds": Json(0),
    } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
