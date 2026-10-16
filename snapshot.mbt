///|
/// A logical document version: observed insert clocks and deletion ranges.
/// The snapshot owns its metadata; later edits do not mutate it.
pub struct Snapshot {
  priv state : StateVector
  priv deletes : Map[UInt64, Array[(UInt32, UInt32)]]
} derive(Debug)

///|
/// Deletion tuples contain client ID, inclusive start and exclusive end.
pub fn Snapshot::Snapshot(
  state~ : StateVector = StateVector(),
  deletions~ : Array[(UInt64, UInt32, UInt32)] = [],
) -> Snapshot {
  let normalized = Doc(client_id=0UL)
  for (client, start, end) in deletions {
    guard start <= end else { abort("reversed snapshot deletion range") }
    normalized.add_delete(client, start, end)
  }
  { state: StateVector(entries=state.entries()), deletes: normalized.deletes, }
}

///|
pub fn Snapshot::state_vector(self : Snapshot) -> StateVector {
  StateVector(entries=self.state.entries())
}

///|
pub fn Snapshot::deletions(self : Snapshot) -> Array[(UInt64, UInt32, UInt32)] {
  let clients = self.deletes.to_array()
  clients.sort_by(fn(a, b) { a.0.compare(b.0) })
  let result = []
  for (client, ranges) in clients {
    for (start, end) in ranges {
      result.push((client, start, end))
    }
  }
  result
}

///|
pub fn Snapshot::is_visible(self : Snapshot, id : Id) -> Bool {
  self.state.get(id.client) > id.clock &&
  !self.deletes
  .get(id.client)
  .unwrap_or([])
  .any(fn(range) { range.0 <= id.clock && id.clock < range.1 })
}

///|
pub fn Doc::snapshot(self : Doc) -> Snapshot {
  let ranges = []
  for client, items in self.clients {
    for item in items {
      if item.deleted {
        ranges.push(
          (
            client,
            item.id.clock,
            item.id.clock + item.content.length().reinterpret_as_uint(),
          ),
        )
      }
    }
  }
  Snapshot(state=self.state, deletions=ranges)
}

///|
fn Snapshot::write(self : Snapshot, out : Writer, v2 : Bool) -> Unit {
  let clients = self.deletes.to_array()
  clients.sort_by(fn(a, b) { b.0.compare(a.0) })
  out.uint(clients.length().to_uint64())
  for (client, ranges) in clients {
    out.uint(client)
    out.uint(ranges.length().to_uint64())
    let mut previous = 0U
    for (start, end) in ranges {
      out.uint((start - (if v2 { previous } else { 0U })).to_uint64())
      out.uint((end - start - (if v2 { 1U } else { 0U })).to_uint64())
      previous = end
    }
  }
  out.uint(self.state.clocks.length().to_uint64())
  for (client, clock) in self.state.entries() {
    out.uint(client)
    out.uint(clock.to_uint64())
  }
}

///|
pub fn Snapshot::encode_v1(self : Snapshot) -> Bytes {
  let writer : Writer = { bytes: [], }
  self.write(writer, false)
  writer.finish()
}

///|
pub fn Snapshot::encode_v2(self : Snapshot) -> Bytes raise DecodeError {
  let writer = UpdateWriter::make(true)
  self.write(writer.raw, true)
  writer.finish()
}

///|
fn Snapshot::read(reader : Reader, v2 : Bool) -> Snapshot raise DecodeError {
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
        raise InvalidData("snapshot clock overflow")
      }
      ranges.push((client, start.to_uint(), (start + length).to_uint()))
      previous = start + length
    }
  }
  let state = StateVector()
  let clients = reader.count()
  for _ in 0..<clients {
    let client = reader.uint()
    state.clocks[client] = reader.clock()
  }
  Snapshot(state~, deletions=ranges)
}

///|
pub fn Snapshot::decode_v1(bytes : Bytes) -> Snapshot raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let result = Snapshot::read(reader, false)
  reader.finish()
  result
}

///|
pub fn Snapshot::decode_v2(bytes : Bytes) -> Snapshot raise DecodeError {
  let reader = UpdateReader::make(bytes, true, 1000000)
  let result = Snapshot::read(reader.raw, true)
  reader.finish()
  result
}

///|
/// Reconstruct the snapshot using retained CRDT history. As with upstream, a
/// snapshot cannot recover content already garbage-collected by another peer.
pub fn Doc::encode_state_from_snapshot_v1(
  self : Doc,
  snapshot : Snapshot,
) -> Bytes raise DecodeError {
  guard self.skip_gc() else {
    raise InvalidData("snapshot encoding requires skip_gc=true")
  }
  let items = []
  for client, blocks in self.clients {
    let end = snapshot.state.get(client).min(self.state.get(client))
    for item in blocks {
      if item.id.clock >= end {
        break
      }
      let length = item.content
        .length()
        .reinterpret_as_uint()
        .min(end - item.id.clock)
        .reinterpret_as_int()
      items.push(
        (
          {
            id: item.id,
            origin: item.origin,
            right_origin: item.right_origin,
            parent: item.parent,
            parent_sub: item.parent_sub,
            content: item.content.slice(0, length),
          } : RawItem),
      )
    }
  }
  encode_raw_update(items, snapshot.deletes)
}

///|
pub fn Doc::encode_state_from_snapshot_v2(
  self : Doc,
  snapshot : Snapshot,
) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(
    self.encode_state_from_snapshot_v1(snapshot),
    max_items=0x7fff_ffff,
  )
}
