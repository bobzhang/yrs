///|
fn n(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("number") }
  n.to_int()
}

///|
fn range(value : Json) -> @yrs.BlockRange {
  guard value is Array([c, s, l]) else { abort("range") }
  @yrs.BlockRange(
    n(c).to_uint64(),
    n(s).reinterpret_as_uint(),
    n(l).reinterpret_as_uint(),
  )
}

///|
fn attrs(value : Json) -> Array[@yrs.ContentAttribute[String]] {
  guard value is Array(values) else { abort("attrs") }
  values.map(fn(v) {
    guard v is Array([String(k), String(v)]) else { abort("attr") }
    @yrs.ContentAttribute(k, v)
  })
}

///|
fn bytes(value : Bytes) -> Json {
  Json(value.iter().map(fn(b) { Json(b.to_int()) }).to_array())
}

///|
fn decode(value : @yrs.Any) -> String raise @yrs.DecodeError {
  guard value is String(s) else {
    raise @yrs.DecodeError::InvalidData("expected string")
  }
  s
}

///|
fn unbytes(value : Json) -> Bytes {
  guard value is Array(values) else { abort("bytes") }
  Bytes::from_array(values.map(fn(v) { n(v).to_byte() })[:])
}

///|
fn rjson(r : @yrs.AttrRange[String]) -> Json {
  Json([
    Json(r.start),
    Json(r.end),
    Json(r.attrs.as_array().map(fn(a) { Json([Json(a.name), Json(a.value)]) })),
  ])
}

///|
fn report(m : @yrs.IdMap[String]) -> Json raise {
  {
    "ranges": Json(
      m
      .iter()
      .map(fn(p) { Json([Json(p.0.to_string()), rjson(p.1)]) })
      .to_array(),
    ),
    "v1": bytes(m.encode_v1(fn(s) { @yrs.Any::String(s) })),
    "v2": bytes(m.encode_v2(fn(s) { @yrs.Any::String(s) })),
    "set": bytes(m.as_id_set().encode_v1()),
    "empty": Json(m.is_empty()),
    "query": Json(m.attributions(@yrs.BlockRange(1UL, 0U, 120U)).map(rjson)),
  }
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let maps : Array[@yrs.IdMap[String]] = [
    @yrs.IdMap(),
    @yrs.IdMap(),
    @yrs.IdMap(),
  ]
  let rows = []
  for command in commands {
    guard command is Array(op) && op.length() >= 2 else { abort("command") }
    let x = n(op[1])
    match op[0] {
      "insert" => maps[x].insert(range(op[2]), attrs(op[3]))
      "remove" => maps[x].remove(range(op[2]))
      "merge" => maps[x].merge_with(maps[n(op[2])].copy())
      "intersect" => maps[x].intersect_with(maps[n(op[2])].copy())
      "diff" => maps[x].diff_map_with(maps[n(op[2])].copy())
      "filter" => {
        guard op[2] is String(name) else { abort("name") }
        maps[x] = maps[x].filter(fn(a) { a.any(fn(v) { v.name == name }) })
      }
      "from" => {
        let r = range(op[2])
        maps[x] = @yrs.IdMap::from_set(
          @yrs.IdSet(ranges=[(r.client, r.clock, r.clock + r.length)]),
          attrs(op[3]),
        )
      }
      "reload1" =>
        maps[x] = @yrs.IdMap::decode_v1(
          maps[x].encode_v1(fn(s) { @yrs.Any::String(s) }),
          decode,
        )
      "reload2" =>
        maps[x] = @yrs.IdMap::decode_v2(
          maps[x].encode_v2(fn(s) { @yrs.Any::String(s) }),
          decode,
        )
      "load1" => maps[x] = @yrs.IdMap::decode_v1(unbytes(op[2]), decode)
      "load2" => maps[x] = @yrs.IdMap::decode_v2(unbytes(op[2]), decode)
      _ => abort("command")
    }
    rows.push(report(maps[x]))
  }
  Json(rows).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
