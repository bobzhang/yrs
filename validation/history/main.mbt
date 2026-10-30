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
fn branch_json(branch : @yrs.BranchId) -> Json {
  match branch {
    Root(name) => ["root", Json(name)]
    Nested(id) =>
      ["nested", Json(id.client.to_int()), Json(id.clock.reinterpret_as_int())]
  }
}

///|
fn run(input : String, v2 : Bool) -> String raise {
  guard @json.parse(input) is Array(commands) else { abort("commands") }
  let docs = Array::makei(3, fn(i) { @yrs.Doc(client_id=(i + 1).to_uint64()) })
  let texts = docs.map(fn(d) { d.get_or_insert_text("note") })
  let marks : Array[@yrs.StickyIndex?] = []
  let saved : Array[(Int32, @yrs.Snapshot)] = []
  let snapshots : Array[Json] = []
  for command in commands {
    guard command is Array(c) else { abort("command") }
    let x = integer(c[1])
    match string(c[0]) {
      "i" =>
        texts[x].insert(integer(c[2]) % (texts[x].length() + 1), string(c[3]))
      "d" => {
        let n = texts[x].length()
        let pos = integer(c[2]) % (n + 1)
        texts[x].remove_range(pos, integer(c[3]) % (n - pos + 1))
      }
      "s" => {
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
      "mark" =>
        marks.push(
          texts[x].sticky_index(
            integer(c[2]) % (texts[x].length() + 2),
            assoc=if integer(c[3]) == -1 { Before } else { After },
          ),
        )
      "boundary" =>
        marks.push(
          Some(
            StickyIndex(
              scope=Root("note"),
              assoc=if integer(c[2]) == -1 { Before } else { After },
            ),
          ),
        )
      "snapshot" => saved.push((x, docs[x].snapshot()))
      "apply" =>
        if v2 {
          docs[x].apply_update_v2(unhex(string(c[2])))
        } else {
          docs[x].apply_update_v1(unhex(string(c[2])))
        }
      "cursor_bytes" =>
        marks.push(Some(@yrs.StickyIndex::decode_v1(unhex(string(c[2])))))
      "snapshot_bytes" =>
        saved.push(
          (
            x,
            if v2 {
              @yrs.Snapshot::decode_v2(unhex(string(c[2])))
            } else {
              @yrs.Snapshot::decode_v1(unhex(string(c[2])))
            },
          ),
        )
      _ => abort("operation")
    }
    let cursors = marks.map(fn(mark) {
      match mark {
        None => Json::null()
        Some(mark) => {
          let offsets = docs.map(fn(doc) {
            match mark.get_offset(doc) {
              None => Json::null()
              Some(offset) =>
                ([branch_json(offset.branch), Json(offset.index)] : Json)
            }
          })
          (
            {
              "wire": Json(hex(mark.encode_v1())),
              "json": mark.to_json(),
              "offsets": Json(offsets),
            } : Json)
        }
      }
    })
    let past = saved.map(fn(pair) raise {
      let (x, snapshot) = pair
      let restored = @yrs.Doc(client_id=99UL)
      if v2 {
        restored.apply_update_v2(
          docs[x].encode_state_from_snapshot_v2(snapshot),
        )
      } else {
        restored.apply_update_v1(
          docs[x].encode_state_from_snapshot_v1(snapshot),
        )
      }
      Json(restored.get_or_insert_text("note").get_string())
    })
    let metadata = saved.map(fn(pair) {
      let snapshot = pair.1
      let state = snapshot
        .state_vector()
        .entries()
        .map(fn(pair) {
          ([Json(pair.0.to_int()), Json(pair.1.reinterpret_as_int())] : Json)
        })
      let deleted = snapshot
        .deletions()
        .map(fn(tuple) {
          (
            [
              Json(tuple.0.to_int()),
              Json(tuple.1.reinterpret_as_int()),
              Json(tuple.2.reinterpret_as_int()),
            ] : Json)
        })
      ({ "state": Json(state), "deleted": Json(deleted) } : Json)
    })
    snapshots.push(
      (
        {
          "text": Json(texts.map(fn(t) { Json(t.get_string()) })),
          "cursors": Json(cursors),
          "past": Json(past),
          "metadata": Json(metadata),
        } : Json),
    )
  }
  let updates = docs.map(fn(doc) raise {
    Json(
      hex(
        if v2 {
          doc.encode_state_as_update_v2()
        } else {
          doc.encode_state_as_update_v1()
        },
      ),
    )
  })
  let saved = saved.map(fn(pair) raise {
    let restored = @yrs.Doc(client_id=99UL)
    restored.apply_update_v1(docs[pair.0].encode_state_from_snapshot_v1(pair.1))
    (
      [
        Json(pair.0),
        Json(hex(if v2 { pair.1.encode_v2() } else { pair.1.encode_v1() })),
        Json(restored.get_or_insert_text("note").get_string()),
      ] : Json)
  })
  let marks = marks.filter_map(fn(mark) {
    mark.map(fn(mark) { Json(hex(mark.encode_v1())) })
  })
  (
    {
      "snapshots": Json(snapshots),
      "updates": Json(updates),
      "saved": Json(saved),
      "marks": Json(marks),
    } : Json).stringify()
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
