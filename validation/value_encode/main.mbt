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
fn view(value : @yrs.Any) -> Json {
  match value {
    Undefined => ["undefined"]
    Null => ["null"]
    Bool(v) => ["bool", Json(v)]
    Integer(v) => ["int", Json(v.to_string())]
    Float(v) => ["float", Json(v.reinterpret_as_uint64().to_string())]
    String(v) => ["string", Json(v)]
    Buffer(v) => ["buffer", Json(v.to_array().map(fn(b) { b.to_int() }))]
    Array(v) => ["array", Json(v.iter().map(view).to_array())]
    Object(v) => {
      let entries : Map[String, Json] = Map([])
      for (key, value) in v {
        entries[key] = view(value)
      }
      ["object", Json(entries)]
    }
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
      let bytes = Bytes::from_array(values.map(fn(v) { v.to_byte() }))
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
    let bytes = Bytes::from_array(numbers.map(fn(n) { n.to_byte() }))
    let reader = @yrs.Cursor(bytes)
    let result : Json = try {
      let value = @yrs.Any::decode_from(reader)
      let writer = @yrs.ByteWriter()
      value.encode_to(writer)
      {
        "value": view(value),
        "tail": Json(
          reader
          .read_exact(reader.remaining())
          .to_array()
          .map(fn(b) { b.to_int() }),
        ),
        "encoded": Json(writer.to_bytes().to_array().map(fn(b) { b.to_int() })),
      }
    } catch {
      _ => { "rejected": Json(true) }
    }
    return result.stringify()
  }
  let result : Json = { "ok": Json(true), "value": view(convert(kind, value)) } catch {
    _ => { "ok": Json(false) }
  }
  result.stringify()
}
