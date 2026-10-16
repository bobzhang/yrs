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
fn boundaries(text : String, bytes : Bool) -> Array[Int32] {
  let result = [0]
  let mut offset = 0
  for c in text {
    let n = c.to_int()
    offset += if bytes {
      if n < 0x80 {
        1
      } else if n < 0x800 {
        2
      } else if n < 0x10000 {
        3
      } else {
        4
      }
    } else if n > 0xffff {
      2
    } else {
      1
    }
    result.push(offset)
  }
  result
}

///|
fn run(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let docs = Array::makei(3, fn(i) {
    @yrs.Doc(
      client_id=(i + 1).to_uint64(),
      offset_kind=if i == 1 { Utf16 } else { Bytes },
    )
  })
  let texts = docs.map(fn(d) { d.get_or_insert_text("text") })
  let events : Array[Json] = []
  for i in 0..<3 {
    texts[i].observe("event", fn(e, _) {
      events.push({
        "doc": Json(i),
        "delta": Json(e.delta().iter().map(@yrs.Delta::to_json).to_array()),
      })
    })
  }
  let snapshots : Array[Json] = []
  for command in commands {
    events.clear()
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    let op = string(c[0])
    if op == "apply" || op == "sync" {
      let (target, update) = if op == "apply" {
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
        docs[target].apply_update_v2(update)
      } else {
        docs[target].apply_update_v1(update)
      }
    } else {
      let points = boundaries(texts[x].get_string(), x != 1)
      let p = integer(c[2]) % points.length()
      if op == "i" {
        texts[x].insert(points[p], string(c[3]))
      } else {
        let end = p + integer(c[3]) % (points.length() - p)
        if op == "d" {
          texts[x].remove_range(points[p], points[end] - points[p])
        } else if op == "delta" {
          texts[x].apply_delta([
            Retain(points[p], []),
            Deleted(points[end] - points[p]),
            Inserted(Value(String("界🦀")), [
              ("bold", Bool(integer(c[4]) == 1)),
            ]),
          ])
        } else {
          texts[x].format(points[p], points[end] - points[p], [
            ("bold", Bool(integer(c[4]) == 1)),
          ])
        }
      }
    }
    snapshots.push({
      "docs": Json(
        Array::makei(3, fn(i) {
          (
            {
              "text": Json(texts[i].get_string()),
              "length": Json(texts[i].length()),
              "delta": Json(
                texts[i]
                .to_delta()
                .map(fn(d) {
                  @yrs.Delta::Inserted(d.insert, d.attributes).to_json()
                }),
              ),
              "sv": Json(
                docs[i]
                .state_vector()
                .entries()
                .map(fn(e) {
                  ([Json(e.0.to_int()), Json(e.1.reinterpret_as_int())] : Json)
                }),
              ),
            } : Json)
        }),
      ),
      "events": Json(events.copy()),
    })
  }
  (
    {
      "snapshots": Json(snapshots),
      "updates": Json(
        docs.map(fn(d) raise {
          Json(
            hex(
              if v2 {
                d.encode_state_as_update_v2()
              } else {
                d.encode_state_as_update_v1()
              },
            ),
          )
        }),
      ),
    } : Json).stringify()
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
