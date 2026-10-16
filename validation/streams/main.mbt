///|
fn encode(ops : Array[Json]) -> Bytes raise {
  let writer = @yrs.ByteWriter()
  for op in ops {
    guard op is Array([String(kind), value]) else { abort("operation") }
    match kind {
      "string" => {
        guard value is String(s) else { abort("string") }
        writer.write_string(s)
      }
      "buf" => {
        let values : Array[Int32] = @json.from_json(value)
        writer.write_buf(Bytes::from_array(values.map(fn(v) { v.to_byte() })))
      }
      "i64" | "varint" | "signed" => {
        let number : Int64 = @json.from_json(value)
        match kind {
          "i64" => writer.write_i64(number)
          "varint" => writer.write_var_int(number)
          _ => writer.write_var_signed((number, number <= 0L))
        }
      }
      _ => {
        let number : UInt64 = @json.from_json(value)
        match kind {
          "u8" => writer.write_u8(number.to_int().to_byte())
          "u16" => writer.write_u16(number.to_uint().to_uint16())
          "u32" => writer.write_u32(number.to_uint())
          "u32be" => writer.write_u32_be(number.to_uint())
          "u64" => writer.write_u64(number)
          "varuint" => writer.write_var_uint(number)
          "f32" =>
            writer.write_f32(Float::reinterpret_from_uint(number.to_uint()))
          "f64" => writer.write_f64(number.reinterpret_as_double())
          _ => abort("kind")
        }
      }
    }
  }
  writer.to_bytes()
}

///|
fn decode(ops : Array[Json], bytes : Bytes) -> Json raise {
  let reader = @yrs.Cursor(bytes)
  let values = []
  for op in ops {
    guard op is Array([String(kind), _]) else { abort("operation") }
    let value : Json = match kind {
      "string" => Json(reader.read_string())
      "buf" => Json(reader.read_buf().to_array().map(fn(b) { b.to_int() }))
      "u8" => Json(reader.read_u8().to_int().to_string())
      "u16" => Json(reader.read_u16().to_uint().to_string())
      "u32" => Json(reader.read_u32().to_string())
      "u32be" => Json(reader.read_u32_be().to_string())
      "u64" => Json(reader.read_u64().to_string())
      "i64" => Json(reader.read_i64().to_string())
      "varuint" => Json(reader.read_var_uint().to_string())
      "varint" => Json(reader.read_var_int().to_string())
      "signed" => {
        let (v, sign) = reader.read_var_signed()
        [Json(v.to_string()), Json(sign)]
      }
      "f32" => Json(reader.read_f32().reinterpret_as_uint().to_string())
      "f64" => Json(reader.read_f64().reinterpret_as_uint64().to_string())
      _ => abort("kind")
    }
    values.push(value)
  }
  {
    "values": Json(values),
    "position": Json(reader.position()),
    "remaining": Json(reader.remaining()),
  }
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  let result = try {
    let request = @json.parse(input)
    guard request is { "ops": Array(ops), .. } else { abort("input") }
    let encoded = encode(ops)
    let bytes = match request {
      { "bytes": bytes, .. } => {
        let values : Array[Int32] = @json.from_json(bytes)
        Bytes::from_array(values.map(fn(v) { v.to_byte() }))
      }
      _ => encoded
    }
    let decoded = decode(ops, bytes) catch { _ => Json("error") }
    (
      {
        "encoded": Json(encoded.to_array().map(fn(b) { b.to_int() })),
        "decoded": decoded,
      } : Json).stringify()
  } catch {
    error => abort(error.to_string())
  }
  result
}
