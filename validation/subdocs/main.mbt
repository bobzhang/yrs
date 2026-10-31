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
  Bytes::from_array(bytes)
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
fn description(doc : @yrs.Doc) -> Json {
  {
    "guid": Json(doc.guid()),
    "auto": Json(doc.auto_load()),
    "load": Json(doc.should_load()),
    "client": Json(doc.client_id().to_int()),
    "collection": match doc.collection_id() {
      Some(s) => Json(s)
      None => Json::null()
    },
    "text": Json(doc.get_or_insert_text("body").get_string()),
    "parent": Json(doc.parent_doc() is Some(_)),
  }
}

///|
fn guids(docs : ArrayView[@yrs.Doc]) -> Json {
  let result = docs.iter().map(@yrs.Doc::guid).to_array()
  result.sort()
  Json(result)
}

///|
fn run(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let docs = Array::makei(3, fn(i) {
    @yrs.Doc(client_id=(i + 1).to_uint64(), collection_id="workspace")
  })
  let roots = docs.map(fn(d) { d.get_or_insert_map("files") })
  let notifications : Array[Json] = []
  for i, doc in docs {
    doc.observe_subdocs("events", fn(e, _) {
      notifications.push({
        "doc": Json(i),
        "added": guids(e.added()),
        "removed": guids(e.removed()),
        "loaded": guids(e.loaded()),
      })
    })
  }
  let snapshots : Array[Json] = []
  for command in commands {
    notifications.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    let op = string(c[0])
    if op == "apply" || op == "sync" {
      let (target, bytes) = if op == "apply" {
        (x, unhex(string(c[2])))
      } else {
        let y = integer(c[2])
        (
          y,
          if v2 {
            docs[x].encode_state_as_update_v2(remote=docs[y].state_vector())
          } else {
            docs[x].encode_state_as_update_v1(remote=docs[y].state_vector())
          },
        )
      }
      if v2 {
        docs[target].apply_update_v2(bytes)
      } else {
        docs[target].apply_update_v1(bytes)
      }
    } else {
      let key = string(c[2])
      if op == "put" {
        let child = @yrs.Doc(
          client_id=99UL,
          guid=string(c[3]),
          auto_load=c[4] == Json(true),
          should_load=c[5] == Json(true),
        )
        roots[x].insert_doc(key, child) |> ignore
      } else if op == "remove" {
        roots[x].remove(key) |> ignore
      } else if roots[x].get(key) is Some(Subdoc(child)) {
        if op == "load" {
          child.load()
        } else if op == "destroy" {
          child.destroy()
        } else if op == "edit" {
          let t = child.get_or_insert_text("body")
          t.insert(t.length(), string(c[3]))
        } else if op == "childsync" {
          let y = integer(c[3])
          if roots[y].get(key) is Some(Subdoc(target)) &&
            target.guid() == child.guid() {
            if v2 {
              target.apply_update_v2(
                child.encode_state_as_update_v2(remote=target.state_vector()),
              )
            } else {
              target.apply_update_v1(
                child.encode_state_as_update_v1(remote=target.state_vector()),
              )
            }
          }
        }
      }
    }
    snapshots.push({
      "docs": Json(
        Array::makei(3, fn(i) {
          let children : Map[String, Json] = Map([])
          for (key, value) in roots[i].entries() {
            if value is Subdoc(d) {
              children[key] = description(d)
            }
          }
          { "files": Json(children), "registered": guids(docs[i].subdocs()) }
        }),
      ),
      "events": Json(notifications.copy()),
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
