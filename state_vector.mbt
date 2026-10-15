///|
pub(all) struct Id {
  client : UInt64
  clock : UInt32
} derive(Eq, Compare, Hash, Debug)

///|
pub extend Id with Eq::{equal, not_equal}

///|
pub extend Id with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend Id with Hash::{hash, hash_combine}

///|
pub extend Id with Debug::{to_repr}

///|
/// Next expected clock for each client; clocks count UTF-16 units for text.
pub struct StateVector {
  priv clocks : Map[UInt64, UInt32]
}

///|
pub fn StateVector::StateVector(
  entries~ : Array[(UInt64, UInt32)] = [],
) -> StateVector {
  { clocks: Map::from_array(entries), }
}

///|
pub fn StateVector::get(self : StateVector, client : UInt64) -> UInt32 {
  self.clocks.get(client).unwrap_or(0U)
}

///|
pub fn StateVector::set_max(
  self : StateVector,
  client : UInt64,
  clock : UInt32,
) -> Unit {
  self.clocks[client] = self.get(client).max(clock)
}

///|
pub fn StateVector::entries(self : StateVector) -> Array[(UInt64, UInt32)] {
  let entries = self.clocks.to_array()
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  entries
}

///|
pub fn StateVector::encode_v1(self : StateVector) -> Bytes {
  let writer : Writer = { bytes: [], }
  writer.uint(self.clocks.length().to_uint64())
  for (client, clock) in self.entries() {
    writer.uint(client)
    writer.uint(clock.to_uint64())
  }
  writer.finish()
}

///|
pub fn StateVector::decode_v1(bytes : Bytes) -> StateVector raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let result = StateVector()
  let count = reader.count()
  for _ in 0..<count {
    let client = reader.uint()
    result.clocks[client] = reader.clock()
  }
  reader.finish()
  result
}
