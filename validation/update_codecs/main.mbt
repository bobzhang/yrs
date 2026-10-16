///|
fn bytes(value : Json) -> Bytes raise {
  let items : Array[Int32] = @json.from_json(value)
  Bytes::from_array(items.map(fn(v) { v.to_byte() }))
}

///|
fn type_ref(value : Json) -> @yrs.TypeRef raise {
  guard value is { "kind": kind, .. } else { abort("type reference") }
  let kind : Int32 = @json.from_json(kind)
  match kind {
    0 => Array
    1 => Map
    2 => Text
    3 => {
      guard value is { "tag": String(tag), .. } else { abort("tag") }
      XmlElement(tag)
    }
    4 => XmlFragment
    5 => XmlHook
    6 => XmlText
    7 => {
      guard value is { "start": start, "end": end, .. } else { abort("link") }
      WeakLink(
        @yrs.LinkSource(
          @yrs.StickyIndex::from_json(start),
          @yrs.StickyIndex::from_json(end),
        ),
      )
    }
    9 => SubDoc
    15 => Undefined
    _ => abort("kind")
  }
}

///|
fn encode(ops : Array[Json], encoder : &@yrs.Encoder) -> Unit raise {
  for op in ops {
    guard op is Array([String(kind), value]) else { abort("operation") }
    match kind {
      "reset" => encoder.reset_ds_cur_val()
      "left" | "right" => {
        guard value is Array([client, clock]) else { abort("id") }
        let id : @yrs.Id = {
          client: @json.from_json(client),
          clock: @json.from_json(clock),
        }
        if kind == "left" {
          encoder.write_left_id(id)
        } else {
          encoder.write_right_id(id)
        }
      }
      "client" => encoder.write_client(@json.from_json(value))
      "typevalue" => type_ref(value).encode(encoder)
      "string" | "key" => {
        guard value is String(s) else { abort("string") }
        if kind == "key" {
          encoder.write_key(s)
        } else {
          @yrs.Write::write_string(encoder, s)
        }
      }
      "parent" => encoder.write_parent_info(value == Json(true))
      "any" | "json" => {
        let any = @yrs.Any::from_json(value)
        if kind == "any" {
          encoder.write_any(any)
        } else {
          encoder.write_json(any)
        }
      }
      "all" => @yrs.Write::write_all(encoder, bytes(value))
      "buf" => @yrs.Write::write_buf(encoder, bytes(value))
      _ => {
        let n : UInt32 = @json.from_json(value)
        match kind {
          "dsclock" => encoder.write_ds_clock(n)
          "dslen" => encoder.write_ds_len(n)
          "info" => encoder.write_info(n.to_byte())
          "type" => encoder.write_type_ref(n.to_byte())
          "len" => encoder.write_len(n)
          "u8" => @yrs.Write::write_u8(encoder, n.to_byte())
          "u32" => @yrs.Write::write_u32(encoder, n)
          "var" => @yrs.Write::write_var_uint(encoder, n.to_uint64())
          _ => abort("kind")
        }
      }
    }
  }
}

///|
fn decode(ops : Array[Json], decoder : &@yrs.Decoder) -> Json raise {
  let values = []
  for op in ops {
    guard op is Array([String(kind), expected]) else { abort("operation") }
    let value : Json = match kind {
      "reset" => {
        decoder.reset_ds_cur_val()
        Json::null()
      }
      "left" | "right" => {
        let id = if kind == "left" {
          decoder.read_left_id()
        } else {
          decoder.read_right_id()
        }
        [Json(id.client.to_string()), Json(id.clock)]
      }
      "client" => Json(decoder.read_client().to_string())
      "typevalue" => {
        let actual = @yrs.TypeRef::decode(decoder)
        {
          "kind": Json(actual.kind().to_int()),
          "equal": Json(actual == type_ref(expected)),
        }
      }
      "string" => Json(@yrs.Read::read_string(decoder))
      "key" => Json(decoder.read_key())
      "parent" => Json(decoder.read_parent_info())
      "any" => decoder.read_any().to_json()
      "json" => decoder.read_json().to_json()
      "dsclock" => Json(decoder.read_ds_clock())
      "dslen" => Json(decoder.read_ds_len())
      "info" => Json(decoder.read_info().to_int())
      "type" => Json(decoder.read_type_ref().to_int())
      "len" => Json(decoder.read_len())
      "u8" => Json(@yrs.Read::read_u8(decoder).to_int())
      "u32" => Json(@yrs.Read::read_u32(decoder))
      "var" => Json(@yrs.Read::read_var_uint(decoder).to_uint())
      _ => abort("raw-only operation")
    }
    values.push(value)
  }
  {
    "values": Json(values),
    "tail": Json(decoder.read_to_end().to_array().map(fn(b) { b.to_int() })),
  }
}

///|
fn run(input : String) -> String raise {
  let request = @json.parse(input)
  if request is { "update": data, "v2": version, .. } {
    let packet = bytes(data)
    let update : @yrs.Update = if version == Json(true) {
      @yrs.Decode::decode_v2(packet)
    } else {
      @yrs.Decode::decode_v1(packet)
    }
    let v1 = @yrs.Encode::encode_v1(update)
    let v2 = @yrs.Encode::encode_v2(update)
    return (
      {
        "v1": Json(v1.to_array().map(fn(b) { b.to_int() })),
        "v2": Json(v2.to_array().map(fn(b) { b.to_int() })),
      } : Json).stringify()
  }
  guard request is { "ops": Array(ops), "v2": version, .. } else {
    abort("input")
  }
  let v2 = version == Json(true)
  let encoder : &@yrs.Encoder = if v2 {
    (@yrs.EncoderV2() : &@yrs.Encoder)
  } else {
    (@yrs.EncoderV1() : &@yrs.Encoder)
  }
  encode(ops, encoder)
  let packet = encoder.to_bytes()
  let raw = match request {
    { "bytes": value, .. } => bytes(value)
    _ => packet
  }
  let decoded = try {
    let decoder : &@yrs.Decoder = if v2 {
      (@yrs.DecoderV2(raw) : &@yrs.Decoder)
    } else {
      (@yrs.DecoderV1(raw) : &@yrs.Decoder)
    }
    if request is { "raw": raw_only, .. } && raw_only == Json(true) {
      Json(decoder.read_to_end().to_array().map(fn(b) { b.to_int() }))
    } else {
      decode(ops, decoder)
    }
  } catch {
    _ => Json("error")
  }
  (
    {
      "encoded": Json(packet.to_array().map(fn(b) { b.to_int() })),
      "decoded": decoded,
    } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
