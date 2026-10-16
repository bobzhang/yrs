///|
fn[A : Eq] IdMap::write(
  self : IdMap[A],
  writer : UpdateWriter,
  encode_value : (A) -> Any,
) -> Unit {
  let clients = self.clients.to_array()
  clients.sort_by(fn(a, b) { a.0.compare(b.0) })
  writer.raw.uint(clients.length().to_uint64())
  let attributes : Array[ContentAttribute[A]] = []
  let names : Array[String] = []
  let mut previous_client = 0UL
  for (client, ranges) in clients {
    writer.raw.uint(client - previous_client)
    previous_client = client
    writer.raw.uint(ranges.length().to_uint64())
    let mut previous_end = 0U
    for range in ranges {
      writer.raw.uint(
        (range.start - (if writer.v2 { previous_end } else { 0U })).to_uint64(),
      )
      writer.raw.uint(
        (range.end - range.start - (if writer.v2 { 1U } else { 0U })).to_uint64(),
      )
      previous_end = range.end
      writer.raw.uint(range.attrs.length().to_uint64())
      for attr in range.attrs.values {
        let mut index = 0
        while index < attributes.length() && attributes[index] != attr {
          index += 1
        }
        writer.raw.uint(index.to_uint64())
        if index == attributes.length() {
          attributes.push(attr)
          let mut name_index = 0
          while name_index < names.length() && names[name_index] != attr.name {
            name_index += 1
          }
          writer.raw.uint(name_index.to_uint64())
          if name_index == names.length() {
            names.push(attr.name)
            writer.string(attr.name)
          }
          writer.raw.any(encode_value(attr.value))
        }
      }
    }
  }
}

///|
pub fn[A : Eq] IdMap::encode_v1(
  self : IdMap[A],
  encode_value : (A) -> Any,
) -> Bytes {
  let writer = UpdateWriter::make(false)
  self.write(writer, encode_value)
  writer.raw.finish()
}

///|
pub fn[A : Eq] IdMap::encode_v2(
  self : IdMap[A],
  encode_value : (A) -> Any,
) -> Bytes raise DecodeError {
  let writer = UpdateWriter::make(true)
  self.write(writer, encode_value)
  writer.finish()
}

///|
fn[A] IdMap::read(
  reader : UpdateReader,
  decode_value : (Any) -> A raise DecodeError,
) -> IdMap[A] raise DecodeError {
  let result = IdMap()
  let attrs : Array[ContentAttribute[A]] = []
  let names : Array[String] = []
  let mut previous_client = 0UL
  for _ in 0..<reader.count() {
    let delta = reader.raw.uint()
    guard delta <= 0xffff_ffff_ffff_ffffUL - previous_client else {
      raise InvalidData("client ID overflow")
    }
    let client = previous_client + delta
    guard !result.clients.contains(client) else {
      raise InvalidData("duplicate attribution client")
    }
    previous_client = client
    let mut previous_end = 0UL
    let ranges = []
    for _ in 0..<reader.count() {
      let start = reader.raw.clock().to_uint64() +
        (if reader.columns.is_empty() { 0UL } else { previous_end })
      let length = reader.raw.clock().to_uint64() +
        (if reader.columns.is_empty() { 0UL } else { 1UL })
      guard start >= previous_end &&
        start + length <= 0xffff_ffffUL &&
        length > 0UL else {
        raise InvalidData("invalid attribution range")
      }
      let values = []
      for _ in 0..<reader.count() {
        let index = reader.raw.uint()
        guard index <= attrs.length().to_uint64() else {
          raise InvalidData("invalid attribution dictionary index")
        }
        if index == attrs.length().to_uint64() {
          let name_index = reader.raw.uint()
          guard name_index <= names.length().to_uint64() else {
            raise InvalidData("invalid attribution name index")
          }
          if name_index == names.length().to_uint64() {
            names.push(reader.string())
          }
          attrs.push(
            ContentAttribute(
              names[name_index.to_int()],
              decode_value(reader.raw.any()),
            ),
          )
        }
        values.push(attrs[index.to_int()])
      }
      previous_end = start + length
      ranges.push(
        AttrRange(
          start.to_uint(),
          previous_end.to_uint(),
          attrs=ContentAttributes(values~),
        ),
      )
    }
    result.clients[client] = ranges
  }
  result
}

///|
pub fn[A] IdMap::decode_v1(
  bytes : Bytes,
  decode_value : (Any) -> A raise DecodeError,
  max_items~ : Int32 = 1000000,
) -> IdMap[A] raise DecodeError {
  let reader = UpdateReader::make(bytes, false, max_items)
  let result = IdMap::read(reader, decode_value)
  reader.finish()
  result
}

///|
pub fn[A] IdMap::decode_v2(
  bytes : Bytes,
  decode_value : (Any) -> A raise DecodeError,
  max_items~ : Int32 = 1000000,
) -> IdMap[A] raise DecodeError {
  let reader = UpdateReader::make(bytes, true, max_items)
  let result = IdMap::read(reader, decode_value)
  reader.finish()
  result
}
