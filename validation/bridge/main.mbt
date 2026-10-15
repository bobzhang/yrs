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
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  let parsed = try! @json.parse(input)
  guard parsed is Array(commands) else { abort("expected commands") }
  let docs = [@yrs.Doc(client_id=1UL), Doc(client_id=2UL), Doc(client_id=3UL)]
  let texts = docs.map(fn(d) { d.get_or_insert_text("note") })
  let queued : Array[(Int32, Bytes)] = []
  let snapshots : Array[Json] = []
  for command in commands {
    guard command is Array(args) && args[0] is String(kind) else {
      abort("bad command")
    }
    let x = integer(args[1])
    match kind {
      "i" => {
        guard args[3] is String(s) else { abort("expected string") }
        texts[x].insert(integer(args[2]) % (texts[x].length() + 1), s)
      }
      "d" => {
        let n = texts[x].length()
        let pos = integer(args[2]) % (n + 1)
        texts[x].remove_range(pos, integer(args[3]) % (n - pos + 1))
      }
      "s" | "q" => {
        let y = integer(args[2])
        let bytes = docs[x].encode_state_as_update_v1(
          remote=docs[y].state_vector(),
        )
        if kind == "q" {
          queued.push((y, bytes))
        } else {
          try! docs[y].apply_update_v1(bytes)
        }
      }
      "r" =>
        if !queued.is_empty() {
          let (y, bytes) = queued[x % queued.length()]
          try! docs[y].apply_update_v1(bytes)
        }
      "a" => {
        guard args[2] is String(s) else { abort("expected hex") }
        try! docs[x].apply_update_v1(unhex(s))
      }
      _ => abort("unknown command")
    }
    snapshots.push(Json(texts.map(fn(t) { t.get_string() })))
  }
  let updates = docs.map(fn(d) { hex(d.encode_state_as_update_v1()) })
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
    } : Json).stringify()
}
