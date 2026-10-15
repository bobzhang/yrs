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
fn state_json(state : @yrs.StateVector) -> Json {
  Json(
    state
    .entries()
    .map(fn(pair) {
      ([Json(pair.0.to_int()), Json(pair.1.reinterpret_as_int())] : Json)
    }),
  )
}

///|
fn ranges_json(ranges : Array[(UInt64, UInt32, UInt32)]) -> Json {
  Json(
    ranges.map(fn(r) {
      (
        [
          Json(r.0.to_int()),
          Json(r.1.reinterpret_as_int()),
          Json(r.2.reinterpret_as_int()),
        ] : Json)
    }),
  )
}

///|
fn meta(tx : @yrs.Transaction, doc : Int32, phase : String) -> Json {
  {
    "doc": Json(doc),
    "phase": Json(phase),
    "before": state_json(tx.before_state()),
    "after": state_json(tx.after_state()),
    "inserted": ranges_json(tx.insertions()),
    "deleted": ranges_json(tx.deletions()),
    "origin": tx.origin().map(fn(b) { Json(hex(b)) }).unwrap_or(Json::null()),
  }
}

///|
fn run(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let docs = Array::makei(3, fn(i) { @yrs.Doc(client_id=(i + 1).to_uint64()) })
  let texts = docs.map(fn(d) { d.get_or_insert_text("note") })
  let maps = docs.map(fn(d) { d.get_or_insert_map("settings") })
  let events : Array[Json] = []
  let packets : Array[(Int32, Bool, Bytes)] = []
  for i, d in docs {
    d.observe_before_observer_calls("oracle", fn(tx) {
      events.push(meta(tx, i, "before"))
    })
    d.observe_after_transaction("oracle", fn(tx) {
      events.push(meta(tx, i, "after"))
    })
    d.observe_transaction_cleanup("oracle", fn(tx) {
      events.push(meta(tx, i, "cleanup"))
    })
    d.observe_update_v1("oracle", fn(bytes, tx) {
      events.push(meta(tx, i, "v1"))
      packets.push((i, false, bytes))
    })
    d.observe_update_v2("oracle", fn(bytes, tx) {
      events.push(meta(tx, i, "v2"))
      packets.push((i, true, bytes))
    })
  }
  let shadows = Array::makei(6, fn(i) {
    @yrs.Doc(client_id=(100 + i).to_uint64())
  })
  let shadow_texts = shadows.map(fn(d) { d.get_or_insert_text("note") })
  let shadow_maps = shadows.map(fn(d) { d.get_or_insert_map("settings") })
  let snapshots : Array[Json] = []
  for command in commands {
    events.clear()
    packets.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    if string(c[0]) == "sync" {
      let y = integer(c[2])
      docs[y].transact(
        fn(_) raise {
          if v2 {
            docs[y].apply_update_v2(
              docs[x].encode_state_as_update_v2(remote=docs[y].state_vector()),
            )
          } else {
            docs[y].apply_update_v1(
              docs[x].encode_state_as_update_v1(remote=docs[y].state_vector()),
            )
          }
        },
        origin=b"remote",
      )
    } else {
      guard c[2] is Array(ops) else { abort("operations") }
      docs[x].transact(
        fn(_) {
          for op in ops {
            guard op is Array(args) else { abort("operation") }
            let kind = string(args[0])
            match kind {
              "i" | "t" => {
                let pos = integer(args[1]) % (texts[x].length() + 1)
                if kind == "i" {
                  texts[x].insert(pos, string(args[2]))
                } else {
                  guard args[3] is True || args[3] is False else {
                    abort("boolean")
                  }
                  texts[x].insert_with_attributes(pos, string(args[2]), [
                    ("bold", Bool(args[3] is True)),
                  ])
                }
              }
              "d" | "f" => {
                let n = texts[x].length()
                let pos = integer(args[1]) % (n + 1)
                let length = integer(args[2]) % (n - pos + 1)
                if kind == "d" {
                  texts[x].remove_range(pos, length)
                } else {
                  texts[x].format(pos, length, [("bold", Bool(args[3] is True))])
                }
              }
              "m" =>
                maps[x].insert(
                  string(args[1]),
                  Integer(integer(args[2]).to_int64()),
                )
              "M" => maps[x].remove(string(args[1]))
              _ => abort("operation")
            }
          }
        },
        origin=@utf8.encode(string(c[3])),
      )
    }
    for (i, v2, bytes) in packets {
      let index = i * 2 + (if v2 { 1 } else { 0 })
      if v2 {
        shadows[index].apply_update_v2(bytes)
      } else {
        shadows[index].apply_update_v1(bytes)
      }
    }
    let current = Array::makei(3, fn(i) {
      ({ "text": Json(texts[i].get_string()), "map": maps[i].to_json() } : Json)
    })
    let replay = Array::makei(6, fn(i) {
      (
        {
          "text": Json(shadow_texts[i].get_string()),
          "map": shadow_maps[i].to_json(),
        } : Json)
    })
    snapshots.push(
      (
        {
          "docs": Json(current),
          "events": Json(events[:].to_owned()),
          "replayed": Json(replay),
        } : Json),
    )
  }
  ({ "snapshots": Json(snapshots) } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  run(input, false) catch {
    error => ({ "error": Json(error.to_string()) } : Json).stringify()
  }
}

///|
#export_name("evaluate_v2")
pub fn evaluate_v2(input : String) -> String {
  run(input, true) catch {
    error => ({ "error": Json(error.to_string()) } : Json).stringify()
  }
}
