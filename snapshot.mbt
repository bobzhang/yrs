///|
/// A logical document version: observed insert clocks and deletion ranges.
/// The snapshot owns its metadata; later edits do not mutate it.
pub struct Snapshot {
  priv state : StateVector
  priv deletes : Map[UInt64, Array[(UInt32, UInt32)]]
} derive(Debug)

///|
/// Deletion tuples contain client ID, inclusive start and exclusive end.
/// Optional delete_set metadata is copied and unioned with these tuples.
pub fn Snapshot::Snapshot(
  state~ : StateVector = StateVector(),
  deletions~ : Array[(UInt64, UInt32, UInt32)] = [],
  delete_set? : IdSet,
) -> Snapshot {
  let ranges = IdSet(ranges=deletions)
  if delete_set is Some(set) {
    ranges.merge_with(set)
  }
  {
    state: StateVector(entries=state.entries()),
    deletes: ranges.deletion_map(),
  }
}

///|
pub fn Snapshot::state_vector(self : Snapshot) -> StateVector {
  StateVector(entries=self.state.entries())
}

///|
/// Return an owned copy, retaining clients with no deletion ranges.
pub fn Snapshot::delete_set(self : Snapshot) -> IdSet {
  let ranges = []
  for client, entries in self.deletes {
    if entries.is_empty() {
      ranges.push((client, 0U, 0U))
    }
    for (start, end) in entries {
      ranges.push((client, start, end))
    }
  }
  IdSet(ranges~)
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
fn Doc::integrated_delete_set(self : Doc) -> IdSet {
  let deleted = IdSet()
  for items in self.clients.values() {
    for item in items {
      if item.deleted {
        deleted.insert(item.id, item.content.length().reinterpret_as_uint())
      }
    }
  }
  deleted
}

///|
/// Capture every integrated item, including items beyond missing clock ranges.
/// Snapshot clocks bound observed identities; absent ranges are excluded by its
/// delete set. Use Doc::state_vector (not this snapshot's vector) for replication.
pub fn Doc::snapshot(self : Doc) -> Snapshot {
  let state = StateVector(entries=self.state.entries())
  let deleted = self.integrated_delete_set()
  for client, items in self.clients {
    let mut end = 0U
    for item in items {
      if end < item.id.clock {
        deleted.insert({ client, clock: end, }, item.id.clock - end)
      }
      end = item.id.clock + item.content.length().reinterpret_as_uint()
    }
    state.set_max(client, end)
  }
  Snapshot(state~, delete_set=deleted)
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
  let deletions = IdSet::read(reader, v2)
  let state = StateVector()
  let clients = reader.count()
  for _ in 0..<clients {
    let client = reader.uint()
    state.clocks[client] = reader.clock()
  }
  { state, deletes: deletions.deletion_map(), }
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
    let end = snapshot.state.get(client)
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
