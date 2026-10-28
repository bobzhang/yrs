///|
/// A normalized set of CRDT clock ranges. End clocks are exclusive.
/// Like Yrs, zero-length insertion retains the client entry: length/is_empty
/// count clients even when ranges() is empty. Difference/intersection prune them.
pub struct IdSet {
  priv mut ranges : Array[(UInt64, UInt32, UInt32)]
  priv mut clients : Set[UInt64]
}

///|
pub fn IdSet::IdSet(ranges~ : Array[(UInt64, UInt32, UInt32)] = []) -> IdSet {
  {
    ranges: normalize_id_ranges(ranges),
    clients: Set::from_array(ranges.map(fn(r) { r.0 })),
  }
}

///|
fn normalize_id_ranges(
  ranges : Array[(UInt64, UInt32, UInt32)],
) -> Array[(UInt64, UInt32, UInt32)] {
  let sorted = ranges.copy()
  sorted.sort_by(fn(a, b) {
    if a.0 != b.0 {
      a.0.compare(b.0)
    } else {
      a.1.compare(b.1)
    }
  })
  let result : Array[(UInt64, UInt32, UInt32)] = []
  for (client, start, end) in sorted {
    guard start <= end else { abort("reversed clock range") }
    if start == end {
      continue
    }
    if result.last() is Some((c, a, b)) && c == client && start <= b {
      result[result.length() - 1] = (client, a, b.max(end))
    } else {
      result.push((client, start, end))
    }
  }
  result
}

///|
fn IdSet::copy(self : IdSet) -> IdSet {
  {
    ranges: self.ranges.copy(),
    clients: Set::from_array(self.clients.to_array()),
  }
}

///|
fn IdSet::deletion_map(self : IdSet) -> Map[UInt64, Array[(UInt32, UInt32)]] {
  let result : Map[UInt64, Array[(UInt32, UInt32)]] = Map([])
  for client in self.clients {
    result[client] = []
  }
  for (client, start, end) in self.ranges {
    result[client].push((start, end))
  }
  result
}

///|
pub fn IdSet::ranges(self : IdSet) -> Array[(UInt64, UInt32, UInt32)] {
  self.ranges.copy()
}

///|
pub fn IdSet::contains(self : IdSet, id : Id) -> Bool {
  for lo = 0, hi = self.ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let (client, start, end) = self.ranges[mid]
    if client < id.client || (client == id.client && end <= id.clock) {
      continue mid + 1, hi
    } else if client > id.client || start > id.clock {
      continue lo, mid
    } else {
      return true
    }
  } nobreak {
    false
  }
}

///|
pub fn IdSet::is_empty(self : IdSet) -> Bool {
  self.clients.is_empty()
}

///|
pub fn IdSet::client_ids(self : IdSet) -> Array[UInt64] {
  let result = self.clients.to_array()
  result.sort()
  result
}

///|
/// Number of clients represented in this set, matching Yrs IdSet::len.
pub fn IdSet::length(self : IdSet) -> Int32 {
  self.clients.length()
}

///|
pub fn IdSet::get(self : IdSet, client : UInt64) -> Array[(UInt32, UInt32)]? {
  guard self.clients.contains(client) else { return None }
  Some([ for (c, start, end) in self.ranges if c == client => (start, end) ])
}

///|
pub fn IdSet::insert(self : IdSet, id : Id, length : UInt32) -> Unit {
  guard length <= 0xffff_ffffU - id.clock else { abort("clock range overflow") }
  self.clients.add(id.client)
  guard length > 0U else { return }
  let ranges = self.ranges
  let end = id.clock + length
  if ranges.last() is Some((client, start, stop)) {
    if client < id.client || (client == id.client && stop < id.clock) {
      ranges.push((id.client, id.clock, end))
      return
    }
    if client == id.client && start <= id.clock {
      ranges[ranges.length() - 1] = (client, start, stop.max(end))
      return
    }
  }
  let first = for lo = 0, hi = ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let (client, _, stop) = ranges[mid]
    if client < id.client || (client == id.client && stop < id.clock) {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo
  }
  let mut last = first
  let mut start = id.clock
  let mut stop = end
  while last < ranges.length() &&
        ranges[last].0 == id.client &&
        ranges[last].1 <= stop {
    start = start.min(ranges[last].1)
    stop = stop.max(ranges[last].2)
    last += 1
  }
  if first == last {
    ranges.insert(first, (id.client, start, stop))
  } else {
    ranges[first] = (id.client, start, stop)
    let removed = last - first - 1
    if removed > 0 {
      for i in last..<ranges.length() {
        ranges[i - removed] = ranges[i]
      }
      ranges.truncate(ranges.length() - removed)
    }
  }
}

///|
pub fn IdSet::merge(self : IdSet, other : IdSet) -> IdSet {
  let result = []
  let mut left = 0
  let mut right = 0
  while left < self.ranges.length() || right < other.ranges.length() {
    let next = if right == other.ranges.length() ||
      (
        left < self.ranges.length() &&
        (
          self.ranges[left].0 < other.ranges[right].0 ||
          (
            self.ranges[left].0 == other.ranges[right].0 &&
            self.ranges[left].1 <= other.ranges[right].1
          )
        )
      ) {
      let item = self.ranges[left]
      left += 1
      item
    } else {
      let item = other.ranges[right]
      right += 1
      item
    }
    let (client, start, end) = next
    if result.last() is Some((c, a, b)) && c == client && start <= b {
      result[result.length() - 1] = (client, a, b.max(end))
    } else {
      result.push(next)
    }
  }
  {
    ranges: result,
    clients: Set::from_array(self.clients.to_array() + other.clients.to_array()),
  }
}

///|
pub fn IdSet::merge_with(self : IdSet, other : IdSet) -> Unit {
  let merged = self.merge(other)
  self.ranges = merged.ranges
  self.clients = merged.clients
}

///|
pub fn IdSet::diff(self : IdSet, other : IdSet) -> IdSet {
  let result = []
  let mut right = 0
  for (client, start, end) in self.ranges {
    let mut cursor = start
    while right < other.ranges.length() {
      let (c, a, b) = other.ranges[right]
      if c < client || (c == client && b <= cursor) {
        right += 1
        continue
      }
      if c > client || a >= end {
        break
      }
      if a > cursor {
        result.push((client, cursor, a))
      }
      cursor = cursor.max(b).min(end)
      if b >= end {
        break
      }
      right += 1
    }
    if cursor < end {
      result.push((client, cursor, end))
    }
  }
  { ranges: result, clients: Set::from_array(result.map(fn(r) { r.0 })), }
}

///|
pub fn IdSet::diff_with(self : IdSet, other : IdSet) -> Unit {
  let difference = self.diff(other)
  self.ranges = difference.ranges
  self.clients = difference.clients
}

///|
pub fn IdSet::intersect(self : IdSet, other : IdSet) -> IdSet {
  let result = []
  let mut left = 0
  let mut right = 0
  while left < self.ranges.length() && right < other.ranges.length() {
    let (client, start, end) = self.ranges[left]
    let (c, a, b) = other.ranges[right]
    if client < c || (client == c && end <= a) {
      left += 1
    } else if client > c || b <= start {
      right += 1
    } else {
      result.push((client, start.max(a), end.min(b)))
      if end <= b {
        left += 1
      } else {
        right += 1
      }
    }
  }
  { ranges: result, clients: Set::from_array(result.map(fn(r) { r.0 })), }
}

///|
pub fn IdSet::intersect_with(self : IdSet, other : IdSet) -> Unit {
  let intersection = self.intersect(other)
  self.ranges = intersection.ranges
  self.clients = intersection.clients
}

///|
pub fn IdSet::remove_range(self : IdSet, id : Id, length : UInt32) -> Unit {
  let other = IdSet()
  other.insert(id, length)
  self.ranges = self.diff(other).ranges
  if !self.ranges.any(fn(r) { r.0 == id.client }) {
    self.clients.remove(id.client)
  }
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
  let seen : Set[UInt64] = Set([])
  let clients = reader.count()
  for _ in 0..<clients {
    let client = reader.uint()
    seen.add(client)
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
  { ranges: normalize_id_ranges(ranges), clients: seen, }
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
