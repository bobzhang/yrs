///|
fn main {
  let args = @env.args()
  guard args is [.., kind, size_arg] else {
    abort("expected workload kind and size")
  }
  let size : Int32 = try! @json.from_json(try! @json.parse(size_arg))
  let doc = @yrs.Doc(client_id=1000000UL)
  let text = doc.get_or_insert_text("text")
  let array = doc.get_or_insert_array("array")
  match kind {
    "text" =>
      for i in 0..<size {
        text.insert(i, "x")
      }
    "array" =>
      for i in 0..<size {
        array.insert_range(i, [Integer(i.to_int64())])
      }
    "dependencies" => {
      // Descending clients form the worst ordering for the old retry scans.
      let encoder = @yrs.EncoderV1()
      encoder.write_var_uint(size.to_uint64())
      for i in size>=..1 {
        encoder.write_var_uint(1UL)
        encoder.write_client(i.to_uint64())
        encoder.write_var_uint(0UL)
        if i == 1 {
          encoder.write_info(b'\x04')
          encoder.write_parent_info(true)
          encoder.write_string("text")
        } else {
          encoder.write_info(b'\x84')
          encoder.write_left_id({ client: (i - 1).to_uint64(), clock: 0U, })
        }
        encoder.write_string("x")
      }
      encoder.write_var_uint(0UL)
      try! doc.apply_update_v1(try! encoder.to_bytes())
    }
    _ => abort("unknown workload")
  }
  let length = if kind == "array" { array.length() } else { text.length() }
  guard length == size else { abort("length mismatch") }
  if kind == "array" {
    for i in 0..<size {
      guard array.get(i) == Some(Value(Integer(i.to_int64()))) else {
        abort("array mismatch")
      }
    }
  } else {
    for c in text.get_string() {
      guard c == 'x' else { abort("text mismatch") }
    }
  }
  let v1 = doc.encode_state_as_update_v1()
  let v2 = try! doc.encode_state_as_update_v2()
  println(
    (
      {
        "length": Json(length),
        "v1_bytes": Json(v1.length()),
        "v2_bytes": Json(v2.length()),
      } : Json).stringify(),
  )
}
