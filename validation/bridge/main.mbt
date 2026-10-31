///|
fn integer(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("expected integer") }
  n.to_int()
}

///|
fn hex(bytes : Bytes) -> String {
  let out = StringBuilder()
  for b in bytes {
    out <+ "\{b.to_hex()}"
  }
  out.to_string()
}

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
  Bytes::from_array(bytes[:])
}

///|
fn entries_json(entries : Array[(String, @yrs.Out)]) -> Json {
  Json(Map(entries.map(fn(pair) { (pair.0, pair.1.to_json()) })))
}

///|
fn any_attributes(fields : Map[String, Json]) -> Array[(String, @yrs.Any)] {
  fields.to_array().map(fn(pair) { (pair.0, @yrs.Any::from_json(pair.1)) })
}

///|
fn xml_snapshot(node : @yrs.XmlNode) -> Json {
  match node {
    Element(node) =>
      {
        "tag": Json(node.tag()),
        "attributes": entries_json(node.attributes()),
        "children": Json(node.as_fragment().children().map(xml_snapshot)),
      }
    Fragment(node) => { "children": Json(node.children().map(xml_snapshot)) }
    Text(node) =>
      {
        "text": Json(node.get_string()),
        "attributes": entries_json(node.attributes()),
      }
  }
}

///|
fn encode_update(
  doc : @yrs.Doc,
  v2 : Bool,
  remote? : @yrs.StateVector,
) -> Bytes raise {
  if v2 {
    doc.encode_state_as_update_v2(remote?)
  } else {
    doc.encode_state_as_update_v1(remote?)
  }
}

///|
fn apply_update(doc : @yrs.Doc, bytes : Bytes, v2 : Bool) -> Unit raise {
  if v2 {
    doc.apply_update_v2(bytes)
  } else {
    doc.apply_update_v1(bytes)
  }
}

///|
fn evaluate_mode(input : String, v2 : Bool, gc~ : Bool = false) -> String raise {
  guard @json.parse(input) is Array(commands) else {
    abort("expected commands")
  }
  let docs = [
    @yrs.Doc(client_id=1UL, skip_gc=!gc),
    Doc(client_id=2UL, skip_gc=!gc),
    Doc(client_id=3UL, skip_gc=!gc),
  ]
  let texts = docs.map(fn(d) { d.get_or_insert_text("note") })
  let arrays = docs.map(fn(d) { d.get_or_insert_array("items") })
  let maps = docs.map(fn(d) { d.get_or_insert_map("settings") })
  let xmls = docs.map(fn(d) { d.get_or_insert_xml_fragment("article") })
  let queued : Array[(Int32, Bytes)] = []
  let snapshots : Array[Json] = []
  let mut trace = false
  let history : Array[Json] = []
  let local_cases : Array[Json] = []
  let previous = docs.map(fn(d) { d.state_vector() })
  for command in commands {
    guard command is Array(args) && args[0] is String(kind) else {
      abort("bad command")
    }
    let x = integer(args[1])
    if trace && ["i", "d", "f", "t", "b", "embed"].contains(kind) {
      let bytes = encode_update(docs[x], v2)
      local_cases.push(([["a", Json(x), Json(hex(bytes))], command] : Json))
    }
    match kind {
      "trace" => {
        trace = true
        continue
      }
      "i" => {
        guard args[3] is String(s) else { abort("expected string") }
        texts[x].insert(integer(args[2]) % (texts[x].length() + 1), s)
      }
      "d" => {
        let n = texts[x].length()
        let pos = integer(args[2]) % (n + 1)
        texts[x].remove_range(pos, integer(args[3]) % (n - pos + 1))
      }
      "f" | "t" | "b" => {
        guard args[4] is Object(fields) else { abort("expected attributes") }
        let attrs = any_attributes(fields)
        let n = texts[x].length()
        let pos = integer(args[2]) % (n + 1)
        if kind == "f" {
          texts[x].format(pos, integer(args[3]) % (n - pos + 1), attrs)
        } else if kind == "t" {
          guard args[3] is String(value) else { abort("expected text") }
          texts[x].insert_with_attributes(pos, value, attrs)
        } else {
          texts[x].insert_embed(
            pos,
            @yrs.Any::from_json(args[3]),
            attributes=attrs,
          )
        }
      }
      "embed" => {
        let attributes = match args[5] {
          Object(fields) => Some(any_attributes(fields))
          _ => None
        }
        let input : @yrs.In = match args[3] {
          "map" => Map([("value", Value(@yrs.Any::from_json(args[4])))])
          "array" => Array([Value(@yrs.Any::from_json(args[4]))])
          "text" => Text([Inserted(Value(@yrs.Any::from_json(args[4])), [])])
          _ => Value(@yrs.Any::from_json(args[4]))
        }
        texts[x].insert_embed_input(
          integer(args[2]) % (texts[x].length() + 1),
          input,
          attributes?,
        )
        |> ignore
      }
      "x" => {
        guard args[3] is String(tag) && args[4] is String(value) else {
          abort("invalid XML insert")
        }
        let node = xmls[x].insert_element(
          integer(args[2]) % (xmls[x].length() + 1),
          tag,
        )
        node.insert_attribute("class", String("entry"))
        node.as_fragment().insert_text(0).as_text().insert(0, value)
      }
      "xmlattr" =>
        if xmls[x].length() > 0 {
          let node = xmls[x].get(integer(args[2]) % xmls[x].length()).unwrap()
          guard node is Element(element) && args[4] is String(key) else {
            abort("element")
          }
          let value = @yrs.Any::from_json(args[5])
          if args[3] == "text" {
            guard element.as_fragment().get(0) is Some(Text(child)) else {
              abort("text child")
            }
            child.insert_attribute(key, value)
          } else {
            element.insert_attribute(key, value)
          }
        }
      "copyxml" =>
        if xmls[x].length() > 0 {
          let node = xmls[x].get(integer(args[2]) % xmls[x].length()).unwrap()
          xmls[x].push_back(node.as_out().to_input()) |> ignore
        }
      "X" => {
        let n = xmls[x].length()
        let pos = integer(args[2]) % (n + 1)
        xmls[x].remove_range(pos, integer(args[3]) % (n - pos + 1))
      }
      "z" => {
        guard args[3] is String(value) else { abort("invalid XML attribute") }
        let children = xmls[x].children()
        if !children.is_empty() &&
          children[integer(args[2]) % children.length()] is Element(node) {
          node.insert_attribute("class", String(value))
          if node.as_fragment().children().get(0) is Some(Text(node)) {
            let text = node.as_text()
            text.insert(integer(args[2]) % (text.length() + 1), "!")
          }
        }
      }
      "n" => {
        guard args[2] is String(key) && args[3] is String(title) else {
          abort("bad nested command")
        }
        let inner = maps[x].insert_map(key)
        inner.insert_text("title").insert(0, title)
        inner.insert_array("list").insert_map(0).insert("done", Bool(false))
      }
      "e" => {
        guard args[2] is String(key) else { abort("bad nested command") }
        if maps[x].get(key) is Some(Map(inner)) {
          if inner.get("title") is Some(Text(text)) {
            text.insert(integer(args[3]) % (text.length() + 1), "!")
          }
          if inner.get("list") is Some(Array(list)) {
            if list.to_array().get(0) is Some(Map(row)) {
              row.insert("done", Bool(true))
            }
            list.insert_range(list.length(), [
              Integer(integer(args[3]).to_int64()),
            ])
          }
        }
      }
      "I" => {
        guard args[3] is Array(values) else { abort("expected array") }
        arrays[x].insert_range(
          integer(args[2]) % (arrays[x].length() + 1),
          values.map(@yrs.Any::from_json),
        )
      }
      "D" => {
        let n = arrays[x].length()
        let pos = integer(args[2]) % (n + 1)
        arrays[x].remove_range(pos, integer(args[3]) % (n - pos + 1))
      }
      "m" => {
        guard args[2] is String(key) else { abort("expected key") }
        maps[x].insert(key, @yrs.Any::from_json(args[3]))
      }
      "M" => {
        guard args[2] is String(key) else { abort("expected key") }
        maps[x].remove(key)
      }
      "s" | "q" | "u" => {
        let y = integer(args[2])
        let remote = if kind == "u" {
          guard args[3] is Array(entries) else {
            abort("expected state vector")
          }
          @yrs.StateVector(
            entries=entries.map(fn(pair) {
              guard pair is Array(parts) else { abort("expected state entry") }
              (
                integer(parts[0]).to_uint64(),
                integer(parts[1]).reinterpret_as_uint(),
              )
            }),
          )
        } else {
          docs[y].state_vector()
        }
        let bytes = encode_update(docs[x], v2, remote~)
        if kind == "q" {
          queued.push((y, bytes))
        } else {
          apply_update(docs[y], bytes, v2)
        }
      }
      "r" =>
        if !queued.is_empty() {
          let (y, bytes) = queued[x % queued.length()]
          apply_update(docs[y], bytes, v2)
        }
      "a" => {
        guard args[2] is String(s) else { abort("expected hex") }
        apply_update(docs[x], unhex(s), v2)
      }
      _ => abort("unknown command")
    }
    if trace {
      for i in 0..<3 {
        let bytes = encode_update(docs[i], v2, remote=previous[i])
        history.push((["a", Json(i), Json(hex(bytes))] : Json))
        previous[i] = docs[i].state_vector()
      }
    }
    snapshots.push(
      Json(
        Array::makei(3, fn(i) {
          (
            {
              "text": Json(texts[i].get_string()),
              "delta": Json(texts[i].to_delta().map(@yrs.TextChunk::to_json)),
              "array": Json(arrays[i].to_array().map(@yrs.Out::to_json)),
              "map": entries_json(maps[i].entries()),
              "xml": Json(xmls[i].children().map(xml_snapshot)),
            } : Json)
        }),
      ),
    )
  }
  let updates = docs.map(fn(d) raise { hex(encode_update(d, v2)) })
  let states = docs.map(fn(d) {
    Json(
      d
      .state_vector()
      .entries()
      .map(fn(pair) { ([Json(pair.0), Json(pair.1)] : Json) }),
    )
  })
  (
    {
      "snapshots": Json(snapshots),
      "updates": Json(updates),
      "states": Json(states),
      "history": Json(history),
      "local_cases": Json(local_cases),
    } : Json).stringify()
}

///|
fn evaluate_report(input : String, v2 : Bool) -> String {
  evaluate_mode(input, v2) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}

///|
fn evaluate_report_gc(input : String, v2 : Bool) -> String {
  evaluate_mode(input, v2, gc=true) catch {
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  evaluate_report(input, false)
}

///|
#export_name("evaluate_v2")
pub fn evaluate_v2(input : String) -> String {
  evaluate_report(input, true)
}

///|
fn utilities_mode(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Object(args) &&
    args.get("updates") is Some(Array(updates)) &&
    args.get("remote") is Some(String(remote)) else {
    abort("bad utility request")
  }
  let updates = updates.map(fn(value) {
    guard value is String(value) else { abort("expected hex") }
    unhex(value)
  })
  let merged = if v2 {
    @yrs.merge_updates_v2(updates)
  } else {
    @yrs.merge_updates_v1(updates)
  }
  let diff = if v2 {
    @yrs.diff_updates_v2(merged, unhex(remote))
  } else {
    @yrs.diff_updates_v1(merged, unhex(remote))
  }
  let sv = if v2 {
    @yrs.encode_state_vector_from_update_v2(merged)
  } else {
    @yrs.encode_state_vector_from_update_v1(merged)
  }
  let entries = @yrs.StateVector::decode_v1(sv)
    .entries()
    .map(fn(pair) { ([Json(pair.0), Json(pair.1)] : Json) })
  (
    {
      "merged": Json(hex(merged)),
      "diff": Json(hex(diff)),
      "states": Json(entries),
    } : Json).stringify()
}

///|
fn utilities_report(input : String, v2 : Bool) -> String {
  utilities_mode(input, v2) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}

///|
#export_name("utilities")
pub fn utilities(input : String) -> String {
  utilities_report(input, false)
}

///|
#export_name("utilities_v2")
pub fn utilities_v2(input : String) -> String {
  utilities_report(input, true)
}

///|
#export_name("evaluate_gc")
pub fn evaluate_gc(input : String) -> String {
  evaluate_report_gc(input, false)
}

///|
#export_name("evaluate_v2_gc")
pub fn evaluate_v2_gc(input : String) -> String {
  evaluate_report_gc(input, true)
}
