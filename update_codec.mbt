///|
priv struct UpdateReader {
  raw : Reader
  columns : Array[Column]
  text : String
  mut text_offset : Int32
  keys : Array[String]
  mut budget : Int32
}

///|
fn UpdateReader::make(
  bytes : Bytes,
  v2 : Bool,
  budget : Int32,
) -> UpdateReader raise DecodeError {
  guard budget >= 0 else { raise InvalidData("negative decode budget") }
  let raw : Reader = { bytes, offset: 0, }
  let columns = []
  let mut text = ""
  if v2 {
    guard raw.byte() == 0 else {
      raise InvalidData("unsupported v2 feature flag")
    }
    for index in 0..<9 {
      let reader : Reader = { bytes: raw.buffer(), offset: 0, }
      if index == 5 {
        text = reader.string()
      }
      let kind = if index == 0 || index == 2 || index == 3 {
        1
      } else if index == 4 || index == 6 {
        2
      } else {
        0
      }
      columns.push({ reader, kind, count: 0UL, last: 0UL, delta: 0L, })
    }
  }
  { raw, columns, text, text_offset: 0, keys: [], budget, }
}

///|
fn UpdateReader::count(self : UpdateReader) -> Int32 raise DecodeError {
  let count = self.raw.clock().to_uint64()
  guard count <= self.budget.to_uint64() else {
    raise InvalidData("update exceeds decode item budget")
  }
  self.budget -= count.to_int()
  count.to_int()
}

///|
fn UpdateReader::field(
  self : UpdateReader,
  column : Int32,
) -> UInt64 raise DecodeError {
  if self.columns.is_empty() {
    if column == 4 || column == 7 {
      self.raw.byte().to_uint64()
    } else {
      self.raw.uint()
    }
  } else {
    self.columns[column].next()
  }
}

///|
fn UpdateReader::string(self : UpdateReader) -> String raise DecodeError {
  if self.columns.is_empty() {
    return self.raw.string()
  }
  let length = self.columns[5].next()
  guard length <= (self.text.length() - self.text_offset).to_uint64() else {
    raise InvalidData("string column length exceeds data")
  }
  let end = self.text_offset + length.to_int()
  for offset in [self.text_offset, end] {
    guard offset == 0 ||
      offset == self.text.length() ||
      !(self.text[offset] >= 0xdc00 &&
      self.text[offset] <= 0xdfff &&
      self.text[offset - 1] >= 0xd800 &&
      self.text[offset - 1] <= 0xdbff) else {
      raise InvalidData("string column splits a surrogate pair")
    }
  }
  let result = self.text[self.text_offset:end].to_owned()
  self.text_offset = end
  result
}

///|
fn UpdateReader::key(self : UpdateReader) -> String raise DecodeError {
  if self.columns.is_empty() {
    return self.raw.string()
  }
  let key = self.columns[0].next()
  guard key <= self.keys.length().to_uint64() else {
    raise InvalidData("invalid key dictionary index")
  }
  if key == self.keys.length().to_uint64() {
    let value = self.string()
    self.keys.push(value)
    value
  } else {
    self.keys[key.to_int()]
  }
}

///|
fn UpdateReader::json(self : UpdateReader) -> Any raise DecodeError {
  if self.columns.is_empty() {
    let parsed = @json.parse(self.raw.string()) catch {
      _ => raise InvalidData("invalid embedded JSON")
    }
    Any::from_json(parsed)
  } else {
    self.raw.any()
  }
}

///|
fn UpdateReader::finish(self : UpdateReader) -> Unit raise DecodeError {
  self.raw.finish()
  if !self.columns.is_empty() {
    guard self.text_offset == self.text.length() else {
      raise InvalidData("unused string column data")
    }
    for column in self.columns {
      column.reader.finish()
      guard column.count == 0UL || column.count == 0xffff_ffff_ffff_ffffUL else {
        raise InvalidData("unused RLE values")
      }
    }
  }
}

///|
priv struct UpdateWriter {
  raw : Writer
  v2 : Bool
  columns : Array[Array[UInt64]]
  strings : Array[String]
}

///|
fn UpdateWriter::make(v2 : Bool) -> UpdateWriter {
  {
    raw: { bytes: [], },
    v2,
    columns: Array::makei(9, fn(_) { [] }),
    strings: [],
  }
}

///|
fn UpdateWriter::field(
  self : UpdateWriter,
  column : Int32,
  value : UInt64,
) -> Unit {
  if self.v2 {
    self.columns[column].push(value)
  } else if column == 4 || column == 7 {
    self.raw.byte(value.to_int())
  } else {
    self.raw.uint(value)
  }
}

///|
fn UpdateWriter::string(self : UpdateWriter, value : String) -> Unit {
  if self.v2 {
    self.strings.push(value)
  } else {
    self.raw.string(value)
  }
}

///|
fn UpdateWriter::key(self : UpdateWriter, value : String) -> Unit {
  if self.v2 {
    self.columns[0].push(self.columns[0].length().to_uint64())
    self.strings.push(value)
  } else {
    self.raw.string(value)
  }
}

///|
fn UpdateWriter::json(self : UpdateWriter, value : Any) -> Unit {
  if self.v2 {
    self.raw.any(value)
  } else {
    self.raw.string(value.to_json().stringify())
  }
}

///|
fn UpdateWriter::finish(self : UpdateWriter) -> Bytes raise DecodeError {
  if !self.v2 {
    return self.raw.finish()
  }
  let out : Writer = { bytes: [], }
  out.byte(0)
  for index in 0..<9 {
    let bytes = if index == 5 {
      let strings : Writer = { bytes: [], }
      strings.string(self.strings.join(""))
      let lengths = encode_column(
        self.strings.map(fn(s) { s.length().to_uint64() }),
        0,
      )
      for b in lengths {
        strings.bytes.push(b)
      }
      strings.finish()
    } else {
      let kind = if index == 0 || index == 2 || index == 3 {
        1
      } else if index == 4 || index == 6 {
        2
      } else {
        0
      }
      encode_column(self.columns[index], kind)
    }
    out.buffer(bytes)
  }
  for b in self.raw.bytes {
    out.bytes.push(b)
  }
  out.finish()
}

///|
fn transcode_update(
  bytes : Bytes,
  from_v2 : Bool,
  to_v2 : Bool,
  max_items : Int32,
) -> Bytes raise DecodeError {
  let input = UpdateReader::make(bytes, from_v2, max_items)
  let output = UpdateWriter::make(to_v2)
  fn field(column : Int32) -> UInt64 raise DecodeError {
    let value = input.field(column)
    output.field(column, value)
    value
  }
  fn id(column : Int32) -> Unit raise DecodeError {
    field(1) |> ignore
    let clock = field(column)
    guard clock <= 0xffff_ffffUL else {
      raise InvalidData("item clock overflow")
    }
  }
  fn count() -> Int32 raise DecodeError {
    let count = input.count()
    output.raw.uint(count.to_uint64())
    count
  }
  let clients = count()
  for _ in 0..<clients {
    let blocks = count()
    field(1) |> ignore
    output.raw.uint(input.raw.clock().to_uint64())
    for _ in 0..<blocks {
      let info = field(4)
      guard info <= 255UL else { raise InvalidData("invalid item flags") }
      if info == 10UL {
        output.raw.uint(input.raw.clock().to_uint64())
        continue
      }
      if info == 0UL {
        field(8) |> ignore
        continue
      }
      let kind = info & 31UL
      if (info & 128UL) != 0UL {
        id(2)
      }
      if (info & 64UL) != 0UL {
        id(3)
      }
      if (info & 192UL) == 0UL {
        match field(6) {
          1UL => output.string(input.string())
          0UL => id(2)
          _ => raise InvalidData("invalid parent discriminator")
        }
        if (info & 32UL) != 0UL {
          output.string(input.string())
        }
      }
      match kind {
        1UL => field(8) |> ignore
        2UL => {
          let n = field(8)
          guard n <= input.budget.to_uint64() else {
            raise InvalidData("JSON item budget exceeded")
          }
          input.budget -= n.to_int()
          for _ in 0..<n.to_int() {
            output.string(input.string())
          }
        }
        3UL => output.raw.buffer(input.raw.buffer())
        4UL => output.string(input.string())
        5UL => output.json(input.json())
        6UL => {
          output.key(input.key())
          output.json(input.json())
        }
        7UL =>
          match field(7) {
            3UL => output.key(input.key())
            0UL | 1UL | 2UL | 4UL | 5UL | 6UL | 9UL | 15UL => ()
            _ => raise InvalidData("unsupported shared type reference")
          }
        8UL => {
          let n = field(8)
          guard n <= input.budget.to_uint64() else {
            raise InvalidData("value item budget exceeded")
          }
          input.budget -= n.to_int()
          for _ in 0..<n.to_int() {
            output.raw.any(input.raw.any())
          }
        }
        9UL => {
          output.string(input.string())
          output.raw.any(input.raw.any())
        }
        _ => raise InvalidData("invalid content reference")
      }
    }
  }
  let clients = count()
  for _ in 0..<clients {
    output.raw.uint(input.raw.uint())
    let ranges = count()
    let mut previous = 0UL
    for _ in 0..<ranges {
      let clock = input.raw.clock().to_uint64() +
        (if from_v2 { previous } else { 0UL })
      let length = input.raw.clock().to_uint64() +
        (if from_v2 { 1UL } else { 0UL })
      guard clock + length <= 0xffff_ffffUL &&
        (!to_v2 || (clock >= previous && length > 0UL)) else {
        raise InvalidData("invalid delete range")
      }
      output.raw.uint(clock - (if to_v2 { previous } else { 0UL }))
      output.raw.uint(length - (if to_v2 { 1UL } else { 0UL }))
      previous = clock + length
    }
  }
  input.finish()
  output.finish()
}

///|
/// Convert update wire formats without integrating a document. The budget bounds
/// expanded blocks, values, client groups and delete ranges in compressed input.
pub fn convert_update_v2_to_v1(
  bytes : Bytes,
  max_items~ : Int32 = 1000000,
) -> Bytes raise DecodeError {
  transcode_update(bytes, true, false, max_items)
}

///|
pub fn convert_update_v1_to_v2(
  bytes : Bytes,
  max_items~ : Int32 = 1000000,
) -> Bytes raise DecodeError {
  transcode_update(bytes, false, true, max_items)
}

///|
pub fn Doc::apply_update_v2(
  self : Doc,
  bytes : Bytes,
  max_items~ : Int32 = 1000000,
) -> Unit raise DecodeError {
  self.apply_update_v1(convert_update_v2_to_v1(bytes, max_items~))
}

///|
pub fn Doc::encode_state_as_update_v2(
  self : Doc,
  remote~ : StateVector = StateVector(),
) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(
    self.encode_state_as_update_v1(remote~),
    max_items=0x7fff_ffff,
  )
}
