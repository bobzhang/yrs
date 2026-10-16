///|
fn RawItem::trim_start(self : RawItem, clock : UInt32) -> RawItem {
  if clock <= self.id.clock {
    return self
  }
  let offset = (clock - self.id.clock).reinterpret_as_int()
  {
    ..self,
    id: { client: self.id.client, clock, },
    origin: if self.content is Garbage(_) {
      None
    } else {
      Some({ client: self.id.client, clock: clock - 1U, })
    },
    content: self.content.slice(offset, self.content.length()),
  }
}

///|
// Gaps are represented by skip blocks when encoding; they never enter a Doc.
fn normalize_items(items : Array[RawItem]) -> Array[RawItem] {
  let sorted = items[:].to_owned()
  sorted.sort_by(fn(a, b) {
    let client = b.id.client.compare(a.id.client)
    if client != 0 {
      client
    } else {
      a.id.clock.compare(b.id.clock)
    }
  })
  let out : Array[RawItem] = []
  for item in sorted {
    let mut start = item.id.clock
    if out.last() is Some(previous) && previous.id.client == item.id.client {
      start = start.max(
        previous.id.clock + previous.content.length().reinterpret_as_uint(),
      )
    }
    if start < item.id.clock + item.content.length().reinterpret_as_uint() {
      out.push(item.trim_start(start))
    }
  }
  out
}

///|
fn encode_raw_update(
  items : Array[RawItem],
  deletes : Map[UInt64, Array[(UInt32, UInt32)]],
  v2~ : Bool = false,
) -> Bytes {
  let groups : Map[UInt64, Array[RawItem]] = Map([])
  for item in normalize_items(items) {
    match groups.get(item.id.client) {
      Some(items) => items.push(item)
      None => groups[item.id.client] = [item]
    }
  }
  let clients = groups.to_array()
  clients.sort_by(fn(a, b) { b.0.compare(a.0) })
  let writer = UpdateWriter::make(v2)
  writer.raw.uint(clients.length().to_uint64())
  for (client, items) in clients {
    let mut count = items.length()
    let mut clock = items[0].id.clock
    for item in items {
      if clock < item.id.clock {
        count += 1
      }
      clock = item.id.clock + item.content.length().reinterpret_as_uint()
    }
    writer.raw.uint(count.to_uint64())
    writer.field(1, client)
    clock = items[0].id.clock
    writer.raw.uint(clock.to_uint64())
    for item in items {
      if clock < item.id.clock {
        writer.field(4, 10UL)
        writer.raw.uint((item.id.clock - clock).to_uint64())
      }
      writer.raw_item(item)
      clock = item.id.clock + item.content.length().reinterpret_as_uint()
    }
  }
  let clients = deletes.to_array()
  clients.sort_by(fn(a, b) { b.0.compare(a.0) })
  writer.raw.uint(clients.length().to_uint64())
  for (client, ranges) in clients {
    writer.raw.uint(client)
    writer.raw.uint(ranges.length().to_uint64())
    let mut previous = 0U
    for (start, end) in ranges {
      writer.raw.uint((start - (if v2 { previous } else { 0U })).to_uint64())
      writer.raw.uint((end - start - (if v2 { 1U } else { 0U })).to_uint64())
      previous = end
    }
  }
  try! writer.finish()
}

///|
/// Merge updates without integrating a document, preserving missing histories.
/// Byte layout may differ from upstream block compaction; item identities and
/// delete ranges are preserved. Unsupported content is rejected during decode.
pub fn merge_updates_v1(updates : Array[Bytes]) -> Bytes raise DecodeError {
  let all = []
  let deletes = IdSet()
  for bytes in updates {
    let (items, ranges) = read_update({ bytes, offset: 0, })
    for item in items {
      all.push(item)
    }
    deletes.merge_with(ranges)
  }
  encode_raw_update(all, deletes.deletion_map())
}

///|
pub fn diff_updates_v1(
  update : Bytes,
  state_vector : Bytes,
) -> Bytes raise DecodeError {
  let remote = StateVector::decode_v1(state_vector)
  let (items, ranges) = read_update({ bytes: update, offset: 0, })
  let filtered = []
  for item in items {
    let known = remote.get(item.id.client)
    if item.id.clock + item.content.length().reinterpret_as_uint() > known {
      filtered.push(item.trim_start(known))
    }
  }
  encode_raw_update(filtered, ranges.deletion_map())
}

///|
/// Extract contiguous clock prefixes; a missing prefix or a skip is not known.
pub fn encode_state_vector_from_update_v1(
  update : Bytes,
) -> Bytes raise DecodeError {
  let (items, _) = read_update({ bytes: update, offset: 0, })
  let state = StateVector()
  for item in normalize_items(items) {
    if item.id.clock == state.get(item.id.client) {
      state.set_max(
        item.id.client,
        item.id.clock + item.content.length().reinterpret_as_uint(),
      )
    }
  }
  state.encode_v1()
}

///|
pub fn merge_updates_v2(updates : Array[Bytes]) -> Bytes raise DecodeError {
  let result : Update = Update()
  for bytes in updates {
    result.merge(Update::decode_v2(bytes))
  }
  result.encode_v2()
}

///|
pub fn diff_updates_v2(
  update : Bytes,
  state_vector : Bytes,
) -> Bytes raise DecodeError {
  Update::decode_v2(update).encode_diff_v2(StateVector::decode_v1(state_vector))
}

///|
pub fn encode_state_vector_from_update_v2(
  update : Bytes,
) -> Bytes raise DecodeError {
  Update::decode_v2(update).state_vector().encode_v1()
}

///|
// Decoded updates and pending-store snapshots own subdocument descriptors.
// Integrating an update into one replica must not attach another replica's Doc.
fn RawItem::owned_update_item(self : RawItem) -> RawItem {
  match self.content {
    Subdocument(child) =>
      {
        ..self,
        content: Subdocument(
          decode_subdocument(
            child.guid(),
            child.decoded_options.unwrap_or_else(fn() { child.wire_options() }),
          ),
        ),
      }
    _ => self
  }
}
