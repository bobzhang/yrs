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
fn run(input : String) -> String raise {
  guard @json.parse(input) is Array(packets) else { abort("packets") }
  let output = []
  for
    i, value in [
      @yrs.Any::Buffer(b"\x01\x02"),
      Undefined,
      Integer(9007199254740993L),
    ] {
    let doc = @yrs.Doc(client_id=1UL)
    let text = doc.get_or_insert_text("text")
    if packets.is_empty() {
      doc.transact(fn(_) {
        text.insert_embed(0, value)
        text.insert_with_attributes(1, "x", [("custom", value)])
      })
    } else {
      guard packets[i] is String(packet) else { abort("packet") }
      doc.apply_update_v2(unhex(packet))
    }
    let delta = text.to_delta()
    assert_eq(delta.length(), 2)
    assert_true(delta[0].insert == @yrs.Out::Value(value))
    assert_eq(delta[1].attributes, [("custom", value)])
    output.push(Json(hex(doc.encode_state_as_update_v2())))
  }
  Json(output).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  run(input) catch {
    error => ({ "error": Json(error.to_string()) } : Json).stringify()
  }
}
