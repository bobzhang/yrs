///|
fn hex(bytes : Bytes) -> String {
  let out = StringBuilder()
  let digits = "0123456789abcdef"
  for b in bytes {
    out.write_char(digits[b.to_int() / 16].to_int().unsafe_to_char())
    out.write_char(digits[b.to_int() % 16].to_int().unsafe_to_char())
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
fn integer(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("integer") }
  n.to_int()
}

///|
fn string(value : Json) -> String {
  guard value is String(s) else { abort("string") }
  s
}

///|
fn keys(values : Map[String, @yrs.EntryChange]) -> Json {
  let out : Map[String, Json] = Map([])
  for key, value in values {
    out[key] = value.to_json()
  }
  Json(out)
}

///|
fn event_json(event : @yrs.Event) -> Json {
  let out : Map[String, Json] = Map([])
  out["path"] = Json(
    event.path().iter().map(@yrs.PathSegment::to_json).to_array(),
  )
  out["target"] = event.target().to_json()
  match event {
    Text(e) => {
      out["kind"] = "text"
      out["delta"] = Json(e.delta().iter().map(@yrs.Delta::to_json).to_array())
    }
    Array(e) => {
      out["kind"] = "array"
      out["delta"] = Json(e.delta().iter().map(@yrs.Change::to_json).to_array())
    }
    Map(e) => {
      out["kind"] = "map"
      out["keys"] = keys(e.keys())
    }
    XmlFragment(e) => {
      out["kind"] = "xml"
      out["delta"] = Json(e.delta().iter().map(@yrs.Change::to_json).to_array())
      out["keys"] = keys(e.keys())
      out["children"] = Json(e.children_changed())
    }
    XmlText(e) => {
      out["kind"] = "xmltext"
      out["delta"] = Json(e.delta().iter().map(@yrs.Delta::to_json).to_array())
      out["keys"] = keys(e.keys())
    }
  }
  Json(out)
}

///|
fn run(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let docs = Array::makei(3, fn(i) { @yrs.Doc(client_id=(i + 1).to_uint64()) })
  let roots = docs.map(fn(d) { d.get_or_insert_map("root") })
  let xmls = docs.map(fn(d) { d.get_or_insert_xml_fragment("xml") })
  let texts = docs.map(fn(d) { d.get_or_insert_text("text") })
  let tick = [100UL]
  let managers : Array[@yrs.UndoManager[Unit]] = Array::makei(3, fn(i) {
    let manager : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { tick[0] })
    manager.expand_scope(Map(roots[i]))
    manager.expand_scope(XmlFragment(xmls[i]))
    manager.expand_scope(Text(texts[i]))
    manager.include_origin(b"user")
    manager
  })
  let notifications : Array[Json] = []
  for i in 0..<3 {
    roots[i].observe_deep("deep", fn(events, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "map",
        "events": Json(events.iter().map(event_json).to_array()),
      })
    })
    xmls[i].observe_deep("deep", fn(events, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "xml",
        "events": Json(events.iter().map(event_json).to_array()),
      })
    })
    xmls[i].observe("shallow", fn(e, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "shallow",
        "delta": Json(e.delta().iter().map(@yrs.Change::to_json).to_array()),
        "keys": keys(e.keys()),
        "children": Json(e.children_changed()),
      })
    })
  }
  let snapshots : Array[Json] = []
  for command in commands {
    notifications.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    let mut result : Json = Json::null()
    if string(c[0]) == "apply" {
      let bytes = unhex(string(c[2]))
      if v2 {
        docs[x].apply_update_v2(bytes)
      } else {
        docs[x].apply_update_v1(bytes)
      }
    } else if string(c[0]) == "undo" {
      result = Json(managers[x].undo())
    } else if string(c[0]) == "redo" {
      result = Json(managers[x].redo())
    } else if string(c[0]) == "reset" {
      managers[x].reset()
    } else if string(c[0]) == "clear" {
      managers[x].clear_all()
    } else if string(c[0]) == "tick" {
      tick[0] += integer(c[2]).to_uint64()
    } else if string(c[0]) == "sync" {
      let y = integer(c[2])
      if v2 {
        docs[y].apply_update_v2(
          docs[x].encode_state_as_update_v2(remote=docs[y].state_vector()),
        )
      } else {
        docs[y].apply_update_v1(
          docs[x].encode_state_as_update_v1(remote=docs[y].state_vector()),
        )
      }
    } else {
      guard c[2] is Array(ops) else { abort("operations") }
      docs[x].transact(
        fn(_) {
          for operation in ops {
            guard operation is Array(op) else { abort("op") }
            let n = integer(op[1])
            let key = "key\{n % 3}"
            match string(op[0]) {
              "i" => texts[x].insert(n % (texts[x].length() + 1), "abc")
              "d" | "f" => {
                let len = texts[x].length()
                let p = n % (len + 1)
                let count = n / 3 % (len - p + 1)
                if string(op[0]) == "d" {
                  texts[x].remove_range(p, count)
                } else {
                  texts[x].format(p, count, [("bold", Bool(n % 2 == 0))])
                }
              }
              "m" => roots[x].insert(key, Integer(n.to_int64()))
              "new" => {
                let m = roots[x].insert_map(key)
                m.insert_text("title").insert(0, "hello")
                let a = m.insert_array("list")
                a.insert_map(0).insert("done", Bool(false))
              }
              "remove" => roots[x].remove(key) |> ignore
              "edit" | "shift" =>
                if roots[x].get(key) is Some(Map(m)) {
                  if m.get("title") is Some(Text(t)) {
                    t.insert(n % (t.length() + 1), "!")
                  }
                  if m.get("list") is Some(Array(a)) {
                    for value in a.to_array() {
                      if value is Map(row) {
                        row.insert("done", Bool(true))
                        break
                      }
                    }
                    a.insert_range(
                      if string(op[0]) == "shift" {
                        0
                      } else {
                        a.length()
                      },
                      [Integer(n.to_int64())],
                    )
                  }
                }
              "xnew" => {
                let e = xmls[x].insert_element(n % (xmls[x].length() + 1), "p")
                e.insert_attribute("class", String("entry"))
                e.as_fragment().insert_text(0).as_text().insert(0, "hello")
              }
              "xremove" => {
                let len = xmls[x].length()
                if len > 0 {
                  xmls[x].remove_range(n % len, 1)
                }
              }
              "xedit" => {
                let len = xmls[x].length()
                if len > 0 && xmls[x].children()[n % len] is Element(e) {
                  e.insert_attribute("class", String("c\{n}"))
                  if e.as_fragment().children().get(0) is Some(Text(t)) {
                    t.insert_attribute("lang", String("en"))
                    let text = t.as_text()
                    text.insert(n % (text.length() + 1), "!")
                  }
                }
              }
              _ => abort("operation")
            }
          }
        },
        origin=b"user",
      )
    }
    let current = Array::makei(3, fn(i) {
      (
        {
          "map": roots[i].to_json(),
          "xml": Json(xmls[i].get_string()),
          "text": Json(texts[i].get_string()),
          "delta": Json(
            texts[i]
            .to_delta()
            .map(fn(d) {
              (
                {
                  "insert": d.insert.to_json(),
                  "attributes": if d.attributes.is_empty() {
                    Json::null()
                  } else {
                    let a : Map[String, Json] = Map([])
                    for (k, v) in d.attributes {
                      a[k] = v.to_json()
                    }
                    Json(a)
                  },
                } : Json)
            }),
          ),
        } : Json)
    })
    snapshots.push({
      "docs": Json(current),
      "result": result,
      "stacks": Json(
        managers.map(fn(m) {
          ([Json(m.undo_stack().length()), Json(m.redo_stack().length())] : Json)
        }),
      ),
      "notifications": Json(notifications.copy()),
    })
  }
  let updates = docs.map(fn(d) raise {
    Json(
      hex(
        if v2 {
          d.encode_state_as_update_v2()
        } else {
          d.encode_state_as_update_v1()
        },
      ),
    )
  })
  ({ "snapshots": Json(snapshots), "updates": Json(updates) } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  run(input, false) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}

///|
#export_name("evaluate_v2")
pub fn evaluate_v2(input : String) -> String {
  run(input, true) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}
