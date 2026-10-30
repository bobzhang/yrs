///|
priv struct Record {
  id : UInt64
  title : String
  flags : Array[Bool]
  extra : Int64?
}

///|
impl @yrs.ToAny for Record with fn to_any(self) {
  Object([
    ("id", @yrs.to_any(self.id)),
    ("title", @yrs.to_any(self.title)),
    ("flags", @yrs.to_any(self.flags)),
    ("extra", @yrs.to_any(self.extra)),
  ])
}

///|
fn to_ints(bytes : Bytes) -> Array[Int32] {
  bytes.to_array().map(fn(b) { b.to_int() })
}

///|
fn to_bytes(numbers : Array[Int32]) -> Bytes {
  Bytes::from_array(numbers.map(fn(v) { v.to_byte() }))
}

///|
fn view(value : @yrs.Any) -> Json {
  match value {
    Undefined => ["undefined"]
    Null => ["null"]
    Bool(v) => ["bool", v]
    Integer(v) => ["int", v.to_string()]
    Float(v) => ["float", v.reinterpret_as_uint64().to_string()]
    String(v) => ["string", v]
    Buffer(v) => ["buffer", to_ints(v)]
    Array(v) => ["array", v.map(view)]
    Object(v) =>
      ["object", Map([ for (key, value) in v => (key, view(value)) ])]
  }
}

///|
fn convert(kind : String, value : Json) -> @yrs.Any raise {
  match kind {
    "i64" => @yrs.to_any((@json.from_json(value) : Int64))
    "i32" => @yrs.to_any((@json.from_json(value) : Int32))
    "u64" => @yrs.to_any((@json.from_json(value) : UInt64))
    "u32" => @yrs.to_any((@json.from_json(value) : UInt32))
    "f64" => {
      let bits : UInt64 = @json.from_json(value)
      @yrs.to_any(bits.reinterpret_as_double())
    }
    "f32" => {
      let bits : UInt32 = @json.from_json(value)
      @yrs.to_any(Float::reinterpret_from_uint(bits))
    }
    "bool" => @yrs.to_any(value == Json(true))
    "string" => @yrs.to_any((@json.from_json(value) : String))
    "unit" => @yrs.to_any(())
    "optional" => {
      let v : UInt64? = if value == Json::null() {
        None
      } else {
        Some(@json.from_json(value))
      }
      @yrs.to_any(v)
    }
    "array" => @yrs.to_any((@json.from_json(value) : Array[UInt64]))
    "map" => @yrs.to_any((@json.from_json(value) : Map[String, UInt64]))
    "tuple" => @yrs.to_any((@json.from_json(value) : (String, UInt64)))
    "record" => {
      guard value
        is { "id": id, "title": title, "flags": flags, "extra": extra, .. } else {
        abort("record")
      }
      @yrs.to_any(Record::{
        id: @json.from_json(id),
        title: @json.from_json(title),
        flags: @json.from_json(flags),
        extra: if extra == Json::null() {
          None
        } else {
          Some(@json.from_json(extra))
        },
      })
    }
    "any" | "bytes" => {
      let values : Array[Int32] = @json.from_json(value)
      let bytes = to_bytes(values)
      if kind == "any" {
        @yrs.to_any(@yrs.Any::decode(bytes))
      } else {
        @yrs.to_any(bytes)
      }
    }
    _ => abort("kind")
  }
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  guard (try! @json.parse(input)) is Array([String(kind), value]) else {
    abort("request")
  }
  if kind == "stream" {
    let numbers : Array[Int32] = try! @json.from_json(value)
    let bytes = to_bytes(numbers)
    let reader = @yrs.Cursor(bytes)
    let result : Json = try {
      let value = @yrs.Any::decode_from(reader)
      let writer = @yrs.ByteWriter()
      value.encode_to(writer)
      {
        "value": view(value),
        "tail": to_ints(reader.read_exact(reader.remaining())),
        "encoded": to_ints(writer.to_bytes()),
      }
    } catch {
      _ => { "rejected": true }
    }
    return result.stringify()
  }
  let result : Json = { "ok": true, "value": view(convert(kind, value)) } catch {
    _ => { "ok": false }
  }
  result.stringify()
}
