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
    let n = b.to_int()
    out.write_char(digits[n / 16].unsafe_to_char())
    out.write_char(digits[n % 16].unsafe_to_char())
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
fn ids(values : ReadOnlyArray[UInt64]) -> Json {
  Json(values.map(fn(v) { Json(v.to_int()) }))
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let mut now = 0UL
  let events : Array[Json] = []
  let docs = Array::makei(3, fn(i) {
    let a : @yrs.Awareness = Awareness(Doc(client_id=(i + 1).to_uint64()), clock=fn() {
      now
    })
    for kind in ["change", "update"] {
      let callback = fn(
        _a : @yrs.Awareness,
        e : @yrs.AwarenessSummary,
        _origin : Bytes?,
      ) {
        events.push(
          (
            [Json(i), Json(kind), ids(e.added), ids(e.updated), ids(e.removed)] :
            Json),
        )
      }
      if kind == "change" {
        a.on_change("oracle", callback)
      } else {
        a.on_update("oracle", callback)
      }
    }
    a
  })
  let queued : Array[(Int32, Bytes)] = []
  let snapshots : Array[Json] = []
  for step, command in commands {
    now = step.to_uint64() + 1000UL
    events.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    let kind = string(c[0])
    match kind {
      "set" => docs[x].set_local_state_raw(string(c[2]))
      "remove" => docs[x].remove_state(integer(c[2]).to_uint64())
      "send" | "queue" => {
        let y = integer(c[2])
        let update = if c.length() > 3 {
          guard c[3] is Array(clients) else { abort("clients") }
          docs[x].update_with_clients(
            clients.map(fn(v) { integer(v).to_uint64() }),
          )
        } else {
          docs[x].update()
        }
        let bytes = update.encode_v1()
        if kind == "send" {
          docs[y].apply_update(@yrs.AwarenessUpdate::decode_v1(bytes)) |> ignore
        } else {
          queued.push((y, bytes))
        }
      }
      "deliver" =>
        if !queued.is_empty() {
          let (y, bytes) = queued[x % queued.length()]
          docs[y].apply_update(@yrs.AwarenessUpdate::decode_v1(bytes)) |> ignore
        }
      "apply" =>
        docs[x].apply_update(
          @yrs.AwarenessUpdate::decode_v1(unhex(string(c[2]))),
        )
        |> ignore
      "insert" => {
        let text = docs[x].doc().get_or_insert_text("note")
        text.insert(text.length(), string(c[2]))
      }
      "connect" => {
        let y = integer(c[2])
        let responses = docs[y].handle_sync(docs[x].start_sync())
        for response in responses {
          docs[x].handle_sync(response.encode_v1()) |> ignore
        }
      }
      "query" => {
        let y = integer(c[2])
        let response = docs[y].handle_message(AwarenessQuery).unwrap()
        docs[x].handle_message(response) |> ignore
      }
      _ => abort("bad operation")
    }
    let states = docs.map(fn(a) {
      let entries = a
        .entries()
        .map(fn(pair) {
          let (id, s) = pair
          (
            [
              Json(id.to_int()),
              Json(s.clock.reinterpret_as_int()),
              Json(s.last_updated.to_int()),
              s.data.map(Json::string).unwrap_or(Json::null()),
            ] : Json)
        })
      (
        {
          "states": Json(entries),
          "text": Json(a.doc().get_or_insert_text("note").get_string()),
        } : Json)
    })
    snapshots.push(
      ({ "docs": Json(states), "events": Json(events.copy()) } : Json),
    )
  }
  (
    {
      "snapshots": Json(snapshots),
      "updates": Json(docs.map(fn(a) { Json(hex(a.update().encode_v1())) })),
    } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  run(input) catch {
    error => ({ "error": Json(error.to_string()) } : Json).stringify()
  }
}
