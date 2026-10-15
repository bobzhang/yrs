///|
fn integer(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("expected integer") }
  n.to_int()
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
fn evaluate_mode(input : String, v2 : Bool) -> String raise {
  let parsed = @json.parse(input)
  guard parsed is Array(commands) else { abort("expected commands") }
  let docs = [@yrs.Doc(client_id=1UL), Doc(client_id=2UL), Doc(client_id=3UL)]
  let texts = docs.map(fn(d) { d.get_or_insert_text("note") })
  let arrays = docs.map(fn(d) { d.get_or_insert_array("items") })
  let maps = docs.map(fn(d) { d.get_or_insert_map("settings") })
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
    if trace && ["i", "d", "f", "t", "b"].contains(kind) {
      let bytes = if v2 {
        docs[x].encode_state_as_update_v2()
      } else {
        docs[x].encode_state_as_update_v1()
      }
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
        let attrs = fields
          .to_array()
          .map(fn(pair) { (pair.0, @yrs.Any::from_json(pair.1)) })
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
        let bytes = if v2 {
          docs[x].encode_state_as_update_v2(remote~)
        } else {
          docs[x].encode_state_as_update_v1(remote~)
        }
        if kind == "q" {
          queued.push((y, bytes))
        } else if v2 {
          docs[y].apply_update_v2(bytes)
        } else {
          docs[y].apply_update_v1(bytes)
        }
      }
      "r" =>
        if !queued.is_empty() {
          let (y, bytes) = queued[x % queued.length()]
          if v2 {
            docs[y].apply_update_v2(bytes)
          } else {
            docs[y].apply_update_v1(bytes)
          }
        }
      "a" => {
        guard args[2] is String(s) else { abort("expected hex") }
        if v2 {
          docs[x].apply_update_v2(unhex(s))
        } else {
          docs[x].apply_update_v1(unhex(s))
        }
      }
      _ => abort("unknown command")
    }
    if trace {
      for i in 0..<3 {
        let bytes = if v2 {
          docs[i].encode_state_as_update_v2(remote=previous[i])
        } else {
          docs[i].encode_state_as_update_v1(remote=previous[i])
        }
        history.push((["a", Json(i), Json(hex(bytes))] : Json))
        previous[i] = docs[i].state_vector()
      }
    }
    snapshots.push(
      Json(
        Array::makei(3, fn(i) {
          let map : Map[String, Json] = Map([])
          for (key, value) in maps[i].entries() {
            map[key] = value.to_json()
          }
          (
            {
              "text": Json(texts[i].get_string()),
              "delta": Json(texts[i].to_delta().map(@yrs.TextChunk::to_json)),
              "array": Json(arrays[i].to_array().map(@yrs.Out::to_json)),
              "map": Json(map),
            } : Json)
        }),
      ),
    )
  }
  let updates = docs.map(fn(d) raise {
    hex(
      if v2 {
        d.encode_state_as_update_v2()
      } else {
        d.encode_state_as_update_v1()
      },
    )
  })
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
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  evaluate_mode(input, false) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}

///|
#export_name("evaluate_v2")
pub fn evaluate_v2(input : String) -> String {
  evaluate_mode(input, true) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
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
#export_name("utilities")
pub fn utilities(input : String) -> String {
  utilities_mode(input, false) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}

///|
#export_name("utilities_v2")
pub fn utilities_v2(input : String) -> String {
  utilities_mode(input, true) catch {
    @yrs.InvalidData(message) => ({ "error": Json(message) } : Json).stringify()
    err => ({ "error": Json(err.to_string()) } : Json).stringify()
  }
}
