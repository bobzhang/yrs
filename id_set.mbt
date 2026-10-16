///|
/// A normalized set of CRDT clock ranges. End clocks are exclusive.
pub struct IdSet {
  priv mut ranges : Array[(UInt64, UInt32, UInt32)]
}

///|
pub fn IdSet::IdSet(ranges~ : Array[(UInt64, UInt32, UInt32)] = []) -> IdSet {
  { ranges: Snapshot(deletions=ranges).deletions(), }
}

///|
pub fn IdSet::ranges(self : IdSet) -> Array[(UInt64, UInt32, UInt32)] {
  self.ranges.copy()
}

///|
pub fn IdSet::contains(self : IdSet, id : Id) -> Bool {
  contains_range(self.ranges, id)
}

///|
pub fn IdSet::is_empty(self : IdSet) -> Bool {
  self.ranges.is_empty()
}

///|
pub fn IdSet::client_ids(self : IdSet) -> Array[UInt64] {
  let result = []
  for (client, _, _) in self.ranges {
    if result.last() != Some(client) {
      result.push(client)
    }
  }
  result
}

///|
/// Number of clients represented in this set, matching Yrs IdSet::len.
pub fn IdSet::length(self : IdSet) -> Int32 {
  self.client_ids().length()
}

///|
pub fn IdSet::get(self : IdSet, client : UInt64) -> Array[(UInt32, UInt32)]? {
  let ranges = self.ranges
    .filter(fn(r) { r.0 == client })
    .map(fn(r) { (r.1, r.2) })
  if ranges.is_empty() {
    None
  } else {
    Some(ranges)
  }
}

///|
pub fn IdSet::insert(self : IdSet, id : Id, length : UInt32) -> Unit {
  guard length <= 0xffff_ffffU - id.clock else { abort("clock range overflow") }
  self.ranges = Snapshot(
    deletions=self.ranges + [(id.client, id.clock, id.clock + length)],
  ).deletions()
}

///|
pub fn IdSet::merge(self : IdSet, other : IdSet) -> IdSet {
  IdSet(ranges=self.ranges + other.ranges)
}

///|
pub fn IdSet::merge_with(self : IdSet, other : IdSet) -> Unit {
  self.ranges = self.merge(other).ranges
}

///|
pub fn IdSet::diff(self : IdSet, other : IdSet) -> IdSet {
  let result = []
  for (client, start, end) in self.ranges {
    let mut cursor = start
    for (c, a, b) in other.ranges {
      if c != client || b <= cursor {
        continue
      }
      if a >= end {
        break
      }
      if a > cursor {
        result.push((client, cursor, a))
      }
      cursor = cursor.max(b).min(end)
      if cursor == end {
        break
      }
    }
    if cursor < end {
      result.push((client, cursor, end))
    }
  }
  { ranges: result, }
}

///|
pub fn IdSet::diff_with(self : IdSet, other : IdSet) -> Unit {
  self.ranges = self.diff(other).ranges
}

///|
pub fn IdSet::intersect(self : IdSet, other : IdSet) -> IdSet {
  let result = []
  for (client, start, end) in self.ranges {
    for (c, a, b) in other.ranges {
      if c == client && start < b && a < end {
        result.push((client, start.max(a), end.min(b)))
      }
    }
  }
  IdSet(ranges=result)
}

///|
pub fn IdSet::intersect_with(self : IdSet, other : IdSet) -> Unit {
  self.ranges = self.intersect(other).ranges
}

///|
pub fn IdSet::remove_range(self : IdSet, id : Id, length : UInt32) -> Unit {
  let other = IdSet()
  other.insert(id, length)
  self.diff_with(other)
}

///|
fn IdSet::write(self : IdSet, writer : Writer, v2 : Bool) -> Unit {
  let clients = self.client_ids()
  writer.uint(clients.length().to_uint64())
  for client in clients {
    let ranges = self.get(client).unwrap()
    writer.uint(client)
    writer.uint(ranges.length().to_uint64())
    let mut previous = 0U
    for (start, end) in ranges {
      writer.uint((start - (if v2 { previous } else { 0U })).to_uint64())
      writer.uint((end - start - (if v2 { 1U } else { 0U })).to_uint64())
      previous = end
    }
  }
}

///|
pub fn IdSet::encode_v1(self : IdSet) -> Bytes {
  let writer : Writer = { bytes: [], }
  self.write(writer, false)
  writer.finish()
}

///|
pub fn IdSet::encode_v2(self : IdSet) -> Bytes raise DecodeError {
  let writer = UpdateWriter::make(true)
  self.write(writer.raw, true)
  writer.finish()
}

///|
fn IdSet::read(reader : Reader, v2 : Bool) -> IdSet raise DecodeError {
  let ranges = []
  let clients = reader.count()
  for _ in 0..<clients {
    let client = reader.uint()
    let count = reader.count()
    let mut previous = 0UL
    for _ in 0..<count {
      let start = reader.clock().to_uint64() + (if v2 { previous } else { 0UL })
      let length = reader.clock().to_uint64() + (if v2 { 1UL } else { 0UL })
      guard start + length <= 0xffff_ffffUL else {
        raise InvalidData("clock range overflow")
      }
      ranges.push((client, start.to_uint(), (start + length).to_uint()))
      previous = start + length
    }
  }
  IdSet(ranges~)
}

///|
pub fn IdSet::decode_v1(bytes : Bytes) -> IdSet raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let result = IdSet::read(reader, false)
  reader.finish()
  result
}

///|
pub fn IdSet::decode_v2(bytes : Bytes) -> IdSet raise DecodeError {
  let reader = UpdateReader::make(bytes, true, 1000000)
  let result = IdSet::read(reader.raw, true)
  reader.finish()
  result
}

///|
/// Rust serde represents IdSet as its v1 encoded byte array.
pub fn IdSet::to_json(self : IdSet) -> Json {
  Json(self.encode_v1().iter().map(fn(b) { Json(b.to_int()) }).to_array())
}

///|
pub fn IdSet::from_json(json : Json) -> IdSet raise DecodeError {
  guard json is Array(values) else {
    raise InvalidData("expected encoded IdSet array")
  }
  let bytes = []
  for value in values {
    guard value is Number(n, ..) &&
      n >= 0.0 &&
      n <= 255.0 &&
      n.to_int().to_double() == n else {
      raise InvalidData("invalid IdSet byte")
    }
    bytes.push(n.to_int().to_byte())
  }
  IdSet::decode_v1(Bytes::from_array(bytes[:]))
}
