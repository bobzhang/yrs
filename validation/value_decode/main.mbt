///|
fn[T : @yrs.FromAny] convert(value : @yrs.Any, encode : (T) -> Json) -> Json {
  { "ok": Json(true), "value": encode(@yrs.from_any(value)) } catch {
    _ => { "ok": Json(false) }
  }
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  guard (try! @json.parse(input)) is Array([String(kind), Array(encoded)]) else {
    abort("request")
  }
  let bytes = Bytes::from_array(
    encoded.map(fn(v) {
      guard v is Number(n, ..) else { abort("byte") }
      n.to_int().to_byte()
    }),
  )
  let value = try! @yrs.Any::decode(bytes)
  let result : Json = match kind {
    "i64" => convert(value, fn(n : Int64) { Json(n.to_string()) })
    "i32" => convert(value, fn(n : Int32) { Json(n.to_string()) })
    "u32" => convert(value, fn(n : UInt32) { Json(n.to_string()) })
    "u64" => convert(value, fn(n : UInt64) { Json(n.to_string()) })
    "f64" =>
      convert(value, fn(n : Double) {
        Json(n.reinterpret_as_uint64().to_string())
      })
    "f32" =>
      convert(value, fn(n : Float) { Json(n.reinterpret_as_uint().to_string()) })
    "bool" => convert(value, fn(n : Bool) { Json(n) })
    "string" => convert(value, fn(n : String) { Json(n) })
    "optional" =>
      convert(value, fn(n : Int64?) {
        n.map(fn(n) { Json(n.to_string()) }).unwrap_or(Json::null())
      })
    "array" =>
      convert(value, fn(n : Array[Int64]) {
        Json(n.map(fn(n) { Json(n.to_string()) }))
      })
    _ => abort("kind")
  }
  result.stringify()
}
