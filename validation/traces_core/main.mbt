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
  fn digit(c : UInt16) -> Int32 {
    if c <= '9' {
      c.to_int() - 48
    } else {
      c.to_int() - 87
    }
  }
  Bytes::makei(s.length() / 2, fn(i) {
    (digit(s[i * 2]) * 16 + digit(s[i * 2 + 1])).to_byte()
  })
}

///|
fn replay(input : String) -> String raise {
  guard @json.parse(input) is Object(fields) else { abort("request") }
  let doc = @yrs.Doc(
    client_id=1UL,
    skip_gc=fields.get("gc") != Some(Json(true)),
  )
  let text = doc.get_or_insert_text("text")
  if fields.get("wire") is Some(String(wire)) {
    if fields.get("v2") == Some(Json(true)) {
      doc.apply_update_v2(unhex(wire))
    } else {
      doc.apply_update_v1(unhex(wire))
    }
    return text.get_string()
  }
  guard fields.get("txns") is Some(Array(txns)) else { abort("transactions") }
  let follower = @yrs.Doc(client_id=2UL, skip_gc=doc.skip_gc())
  let peer_text = follower.get_or_insert_text("text")
  let queue : Array[Bytes] = []
  let mut patches = 0
  let mut packets = 0
  let mut checkpoints = 0
  let mut catchups = 0
  doc.observe_update_v1("network", fn(bytes, _) { queue.push(bytes) })
  for i, txn in txns {
    guard txn is Array(changes) else { abort("changes") }
    doc.transact(fn(_) {
      for change in changes {
        guard change
          is Array([Number(at, ..), Number(count, ..), String(value)]) else {
          abort("patch")
        }
        if count > 0 {
          text.remove_range(at.to_int(), count.to_int())
        }
        if !value.is_empty() {
          text.insert(at.to_int(), value)
        }
        patches += 1
      }
    })
    if (i + 1) % 128 == 0 || i + 1 == txns.length() {
      // A reconnect delivers recent packets first, including duplicates.
      while queue.pop() is Some(bytes) {
        follower.apply_update_v1(bytes)
        follower.apply_update_v1(bytes)
        packets += 2
      }
      if text.get_string() != peer_text.get_string() ||
        doc.state_vector() != follower.state_vector() {
        follower.apply_update_v1(doc.encode_state_as_update_v1())
        catchups += 1
      }
      guard text.get_string() == peer_text.get_string() &&
        doc.state_vector() == follower.state_vector() else {
        abort("reconnect divergence at transaction \{i}")
      }
      checkpoints += 1
    }
  }
  let wire_v1 = doc.encode_state_as_update_v1()
  let wire_v2 = doc.encode_state_as_update_v2()
  for version in 1..<=2 {
    let peer = @yrs.Doc(client_id=3UL)
    if version == 1 {
      peer.apply_update_v1(wire_v1)
    } else {
      peer.apply_update_v2(wire_v2)
    }
    guard peer.get_or_insert_text("text").get_string() == text.get_string() else {
      abort("full-state restart diverged")
    }
  }
  (
    {
      "text": Json(text.get_string()),
      "clock": Json(doc.state_vector().get(1UL)),
      "patches": Json(patches),
      "transactions": Json(txns.length()),
      "deliveries": Json(packets),
      "checkpoints": Json(checkpoints),
      "catchups": Json(catchups),
      "wire_v1": Json(hex(wire_v1)),
      "wire_v2": Json(hex(wire_v2)),
    } : Json).stringify()
}

///|
pub fn evaluate(input : String) -> String {
  try! replay(input)
}
