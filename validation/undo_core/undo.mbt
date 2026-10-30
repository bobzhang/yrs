///|
fn attributes_json(attributes : Array[(String, @yrs.Out)]) -> Json {
  let out : Map[String, Json] = Map([])
  for (key, value) in attributes {
    out[key] = value.to_json()
  }
  Json(out)
}

///|
fn xml_snapshot(node : @yrs.XmlNode) -> Json {
  match node {
    Element(node) =>
      {
        "tag": Json(node.tag()),
        "attributes": attributes_json(node.attributes()),
        "children": Json(node.as_fragment().children().map(xml_snapshot)),
      }
    Fragment(node) => { "children": Json(node.children().map(xml_snapshot)) }
    Text(node) =>
      {
        "text": Json(node.get_string()),
        "attributes": attributes_json(node.attributes()),
      }
  }
}

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
  out["path"] = Json(event.path().map(@yrs.PathSegment::to_json))
  out["target"] = event.target().to_json()
  match event {
    Weak(_) => out["kind"] = "weak"
    Text(e) => {
      out["kind"] = "text"
      out["delta"] = Json(e.delta().map(@yrs.Delta::to_json))
    }
    Array(e) => {
      out["kind"] = "array"
      out["delta"] = Json(e.delta().map(@yrs.Change::to_json))
    }
    Map(e) => {
      out["kind"] = "map"
      out["keys"] = keys(e.keys())
    }
    XmlFragment(e) => {
      out["kind"] = "xml"
      out["delta"] = Json(e.delta().map(@yrs.Change::to_json))
      out["keys"] = keys(e.keys())
      out["children"] = Json(e.children_changed())
    }
    XmlText(e) => {
      out["kind"] = "xmltext"
      out["delta"] = Json(e.delta().map(@yrs.Delta::to_json))
      out["keys"] = keys(e.keys())
    }
  }
  Json(out)
}

///|
priv struct Session {
  docs : Array[@yrs.Doc]
  roots : Array[@yrs.MapRef]
  xmls : Array[@yrs.XmlFragment]
  texts : Array[@yrs.Text]
  tick : Array[UInt64]
  managers : Array[@yrs.UndoManager[Unit]]
  notifications : Array[Json]
  emitted : Array[Json]
}

///|
let sessions : Array[Session] = []

///|
fn make_session(gc : Bool, v2 : Bool) -> Session {
  let docs = Array::makei(3, fn(i) {
    @yrs.Doc(client_id=(i + 1).to_uint64(), skip_gc=!gc)
  })
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
  let emitted : Array[Json] = []
  for i in 0..<3 {
    if v2 {
      docs[i].observe_update_v2("wire", fn(bytes, _) {
        emitted.push(Json([Json(i), Json(hex(bytes))]))
      })
    } else {
      docs[i].observe_update_v1("wire", fn(bytes, _) {
        emitted.push(Json([Json(i), Json(hex(bytes))]))
      })
    }
    roots[i].observe_deep("deep", fn(events, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "map",
        "events": Json(events.map(event_json)),
      })
    })
    xmls[i].observe_deep("deep", fn(events, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "xml",
        "events": Json(events.map(event_json)),
      })
    })
    xmls[i].observe("shallow", fn(e, _) {
      notifications.push({
        "doc": Json(i),
        "scope": "shallow",
        "delta": Json(e.delta().map(@yrs.Change::to_json)),
        "keys": keys(e.keys()),
        "children": Json(e.children_changed()),
      })
    })
  }
  { docs, roots, xmls, texts, tick, managers, notifications, emitted, }
}

///|
fn run(
  input : String,
  v2 : Bool,
  live~ : Bool = false,
  gc~ : Bool = false,
) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let session = if live {
    if sessions.is_empty() {
      sessions.push(make_session(gc, v2))
    }
    sessions[0]
  } else {
    make_session(gc, v2)
  }
  session.emitted.clear()
  let docs = session.docs
  let roots = session.roots
  let xmls = session.xmls
  let texts = session.texts
  let tick = session.tick
  let managers = session.managers
  let notifications = session.notifications
  let snapshots : Array[Json] = []
  for command in commands {
    notifications.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    let mut result : Json = Json::null()
    match string(c[0]) {
      "seed" => {
        // Validation-only setup: the supplied v1 packet contains compressed GC
        // history and must be installed before any user-authored operations.
        docs[x].apply_update_v1(unhex(string(c[2])))
        result = Json(docs[x].state_vector().get((x + 1).to_uint64()))
      }
      "apply" => {
        let bytes = unhex(string(c[2]))
        if v2 {
          docs[x].apply_update_v2(bytes)
        } else {
          docs[x].apply_update_v1(bytes)
        }
      }
      "undo" => result = Json(managers[x].undo())
      "redo" => result = Json(managers[x].redo())
      "reset" => managers[x].reset()
      "clear" => managers[x].clear_all()
      "tick" => tick[0] += integer(c[2]).to_uint64()
      "sync" => {
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
      }
      _ => {
        guard c[2] is Array(ops) else { abort("operations") }
        docs[x].transact(
          fn(_) {
            for operation in ops {
              guard operation is Array(op) else { abort("op") }
              let n = integer(op[1])
              let key = "key\{n % 3}"
              let kind = string(op[0])
              match kind {
                "i" => texts[x].insert(n % (texts[x].length() + 1), "abc")
                "d" | "f" => {
                  let len = texts[x].length()
                  let p = n % (len + 1)
                  let count = n / 3 % (len - p + 1)
                  if kind == "d" {
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
                      for value in a {
                        if value is Map(row) {
                          row.insert("done", Bool(true))
                          break
                        }
                      }
                      a.insert_range(
                        if kind == "shift" {
                          0
                        } else {
                          a.length()
                        },
                        [Integer(n.to_int64())],
                      )
                    }
                  }
                "xnew" => {
                  let e = xmls[x].insert_element(
                    n % (xmls[x].length() + 1),
                    "p",
                  )
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
    }
    let current = Array::makei(3, fn(i) {
      (
        {
          "map": roots[i].to_json(),
          "xml": Json(xmls[i].get_string()),
          "xml_nodes": Json(xmls[i].children().map(xml_snapshot)),
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
  let causal = docs.map(fn(d) {
    let snapshot = d.snapshot()
    (
      {
        "state": Json(
          snapshot
          .state_vector()
          .entries()
          .map(p => Json([Json(p.0.to_string()), Json(p.1)])),
        ),
        "deleted": Json(
          snapshot
          .deletions()
          .map(p => Json([Json(p.0.to_string()), Json(p.1), Json(p.2)])),
        ),
      } : Json)
  })
  (
    {
      "snapshots": Json(snapshots),
      "updates": Json(updates),
      "causal": Json(causal),
      "emitted": Json(session.emitted),
    } : Json).stringify()
}

///|
pub fn evaluate(input : String) -> String {
  run(input, false) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}

///|
pub fn evaluate_v2(input : String) -> String {
  run(input, true) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}

///|
pub fn evaluate_live(input : String, v2 : Bool, gc : Bool) -> String {
  run(input, v2, live=true, gc~) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}

///|
pub fn evaluate_gc(input : String, v2 : Bool) -> String {
  run(input, v2, gc=true) catch {
    e => ({ "error": Json(e.to_string()) } : Json).stringify()
  }
}
