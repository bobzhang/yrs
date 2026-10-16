///|
pub fn StateVector::is_empty(self : StateVector) -> Bool {
  self.clocks.is_empty()
}

///|
pub fn StateVector::length(self : StateVector) -> Int32 {
  self.clocks.length()
}

///|
pub fn StateVector::contains_client(
  self : StateVector,
  client : UInt64,
) -> Bool {
  self.clocks.contains(client)
}

///|
/// Upstream containment includes the boundary clock. Use Snapshot::is_visible
/// when testing whether a concrete item is visible in a document version.
pub fn StateVector::contains(self : StateVector, id : Id) -> Bool {
  id.clock <= self.get(id.client)
}

///|
pub fn StateVector::inc_by(
  self : StateVector,
  client : UInt64,
  delta : UInt32,
) -> Unit {
  if delta > 0U {
    let clock = self.get(client)
    guard delta <= 0xffff_ffffU - clock else {
      abort("state vector clock overflow")
    }
    self.clocks[client] = clock + delta
  }
}

///|
pub fn StateVector::set_min(
  self : StateVector,
  client : UInt64,
  clock : UInt32,
) -> Unit {
  self.clocks[client] = self.clocks
    .get(client)
    .map(fn(old) { old.min(clock) })
    .unwrap_or(clock)
}

///|
pub fn StateVector::merge(self : StateVector, other : StateVector) -> Unit {
  for client, clock in other.clocks {
    self.set_max(client, clock)
  }
}

///|
/// Returns -1, 0 or 1 for ordered vectors, or None for concurrent versions.
pub fn StateVector::partial_compare(
  self : StateVector,
  other : StateVector,
) -> Int32? {
  let mut less = false
  let mut greater = false
  for (client, _) in self.entries() + other.entries() {
    let a = self.get(client)
    let b = other.get(client)
    if a < b {
      less = true
    }
    if a > b {
      greater = true
    }
    if less && greater {
      return None
    }
  }
  Some(if less { -1 } else if greater { 1 } else { 0 })
}

///|
pub impl Eq for StateVector with fn equal(self, other) {
  self.entries() == other.entries()
}

///|
pub fn StateVector::iter(self : StateVector) -> Iter[(UInt64, UInt32)] {
  self.entries().iter()
}

///|
fn metadata_v2(bytes : Bytes) -> Bytes raise DecodeError {
  let writer = UpdateWriter::make(true)
  for byte in bytes {
    writer.raw.bytes.push(byte)
  }
  writer.finish()
}

///|
fn metadata_v1(bytes : Bytes) -> Bytes raise DecodeError {
  let reader = UpdateReader::make(bytes, true, 1000000)
  let payload = reader.raw.bytes[reader.raw.offset:].to_owned()
  reader.raw.offset = reader.raw.bytes.length()
  reader.finish()
  payload
}

///|
pub fn StateVector::encode_v2(self : StateVector) -> Bytes raise DecodeError {
  metadata_v2(self.encode_v1())
}

///|
pub fn StateVector::decode_v2(bytes : Bytes) -> StateVector raise DecodeError {
  StateVector::decode_v1(metadata_v1(bytes))
}

///|
pub fn StickyIndex::encode_v2(self : StickyIndex) -> Bytes raise DecodeError {
  let writer = UpdateWriter::make(true)
  match self.scope {
    Relative(id) => {
      writer.raw.uint(0UL)
      writer.raw.id(id)
    }
    Root(name) => {
      writer.raw.uint(1UL)
      writer.string(name)
    }
    Nested(id) => {
      writer.raw.uint(2UL)
      writer.raw.id(id)
    }
  }
  writer.raw.signed(if self.assoc == Before { -1L } else { 0L })
  writer.finish()
}

///|
pub fn StickyIndex::decode_v2(bytes : Bytes) -> StickyIndex raise DecodeError {
  let reader = UpdateReader::make(bytes, true, 1000000)
  let scope : IndexScope = match reader.raw.uint() {
    0UL => Relative(reader.raw.id())
    1UL => Root(reader.string())
    2UL => Nested(reader.raw.id())
    _ => raise InvalidData("invalid sticky index scope")
  }
  let assoc = reader.raw.signed()
  guard assoc >= -128L && assoc <= 127L else {
    raise InvalidData("invalid association")
  }
  reader.finish()
  { scope, assoc: if assoc < 0L { Before } else { After }, }
}

///|
pub impl Eq for Snapshot with fn equal(self, other) {
  self.state == other.state && self.deletes == other.deletes
}

///|
pub extend StateVector with Eq::{equal, not_equal}

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub extend StateVector with Debug::{to_repr}

///|
pub extend Snapshot with Debug::{to_repr}
