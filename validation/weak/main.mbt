///|
fn n(v : Json) -> Int32 {
  guard v is Number(n, ..) else { abort("number") }
  n.to_int()
}

///|
fn s(v : Json) -> String {
  guard v is String(s) else { abort("string") }
  s
}

///|
fn bound(v : Json, len : Int32) -> @yrs.QuoteBound {
  if v == Json::null() {
    return Unbounded
  }
  guard v is Array([String(k), value]) else { abort("bound") }
  if k == "i" {
    Included(n(value) % len)
  } else {
    Excluded(n(value) % len)
  }
}

///|
fn report(d : @yrs.Doc, v2 : Bool) -> Json raise {
  let links : Map[String, Json] = Map([])
  for (key, value) in d.get_or_insert_map("links").entries() {
    if value is WeakLink(link) {
      fn id(value : @yrs.Id?) -> Json {
        match value {
          Some(id) => Json([Json(id.client.to_string()), Json(id.clock)])
          None => Json::null()
        }
      }
      let output = if key.has_prefix("t") {
        Json([Json(link.get_string()), Json(link.get_xml_string())])
      } else if key.has_prefix("a") {
        Json(link.unquote().map(fn(v) { v.to_json() }))
      } else {
        match link.try_deref_value() {
          Some(v) => v.to_json()
          None => Json::null()
        }
      }
      links[key] = Json([Json([id(link.start_id()), id(link.end_id())]), output])
    }
  }
  let bytes = if v2 {
    d.encode_state_as_update_v2()
  } else {
    d.encode_state_as_update_v1()
  }
  {
    "text": Json(d.get_or_insert_text("text").get_string()),
    "array": d.get_or_insert_array("array").to_json(),
    "map": d.get_or_insert_map("map").to_json(),
    "links": Json(links),
    "wire": Json(bytes.iter().map(fn(b) { Json(b.to_int()) }).to_array()),
  }
}

///|
fn run(input : String, v2 : Bool, gc : Bool, raw_bounds : Bool) -> String raise {
  guard @json.parse(input) is Array(ops) else { abort("ops") }
  let d = @yrs.Doc(client_id=1UL, skip_gc=!gc)
  let t = d.get_or_insert_text("text")
  let a = d.get_or_insert_array("array")
  let m = d.get_or_insert_map("map")
  let links = d.get_or_insert_map("links")
  let rows = []
  let events : Array[String] = []
  for command in ops {
    guard command is Array(op) else { abort("op") }
    match op[0] {
      "i" => t.insert(n(op[1]) % (t.length() + 1), s(op[2]))
      "d" =>
        if t.length() > 0 {
          let i = n(op[1]) % t.length()
          t.remove_range(i, n(op[2]).min(t.length() - i))
        }
      "f" =>
        if t.length() > 0 {
          let i = n(op[1]) % t.length()
          t.format(i, n(op[2]).min(t.length() - i), [
            ("b", @yrs.Any::from_json(op[3])),
          ])
        }
      "ai" =>
        a.insert(
          n(op[1]) % (a.length() + 1),
          Value(Integer(n(op[2]).to_int64())),
        )
        |> ignore
      "ad" =>
        if a.length() > 0 {
          let i = n(op[1]) % a.length()
          a.remove_range(i, n(op[2]).min(a.length() - i))
        }
      "m" => m.insert(s(op[1]), Integer(n(op[2]).to_int64()))
      "md" => m.remove(s(op[1]))
      "ml" =>
        if m.link(s(op[2])) is Some(p) {
          links.insert_input(s(op[1]), WeakLink(p)) |> ignore
        }
      "q" => {
        let key = s(op[1])
        let len = if key.has_prefix("t") { t.length() } else { a.length() }
        if len > 0 {
          let mut lo = bound(op[2], len)
          let mut hi = bound(op[3], len)
          fn pos(b : @yrs.QuoteBound) -> Int32 {
            match b {
              Included(i) | Excluded(i) => i
              Unbounded => 0
            }
          }
          if !(lo is Unbounded) && !(hi is Unbounded) && pos(lo) > pos(hi) {
            let tmp = lo
            lo = hi
            hi = tmp
          }
          if !raw_bounds &&
            !(lo is Unbounded) &&
            !(hi is Unbounded) &&
            pos(lo) == pos(hi) {
            lo = Included(pos(lo))
            hi = lo
          }
          let p = if key.has_prefix("t") {
            t.quote(lo, hi)
          } else {
            a.quote(lo, hi)
          }
          links.insert_input(key, WeakLink(p)) |> ignore
        }
      }
      "del" => links.remove(s(op[1]))
      "load" => {
        guard op[1] is Array(values) else { abort("bytes") }
        let bytes = Bytes::from_array(values.map(fn(v) { n(v).to_byte() })[:])
        if v2 {
          d.apply_update_v2(bytes)
        } else {
          d.apply_update_v1(bytes)
        }
      }
      _ => abort("command")
    }
    guard report(d, v2) is Object(row) else { abort("row") }
    row["events"] = Json(events.map(fn(s) { Json(s) }))
    events.clear()
    rows.push(Json(row))
    for (key, value) in links.entries() {
      if value is WeakLink(link) {
        link.observe("watch", fn(_, _) { events.push(key) })
      }
    }
  }
  Json(rows).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(
  input : String,
  v2 : Bool,
  gc : Bool,
  raw_bounds : Bool,
) -> String {
  try! run(input, v2, gc, raw_bounds)
}
