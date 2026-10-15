///|
fn read_update(
  reader : Reader,
) -> (Array[RawItem], Array[(UInt64, UInt32, UInt32)]) raise DecodeError {
  let items = []
  let clients = reader.count()
  for _ in 0..<clients {
    let count = reader.count()
    let client = reader.uint()
    let mut clock = reader.clock()
    for _ in 0..<count {
      let info = reader.byte()
      let origin = if (info & 128) != 0 { Some(reader.id()) } else { None }
      let right_origin = if (info & 64) != 0 { Some(reader.id()) } else { None }
      let kind = info & 31
      let parent = if kind != 0 &&
        kind != 10 &&
        origin is None &&
        right_origin is None {
        guard reader.uint() == 1UL else {
          raise InvalidData("nested shared types are not implemented yet")
        }
        Some(reader.string())
      } else {
        None
      }
      let parent_sub = if parent is Some(_) && (info & 32) != 0 {
        Some(reader.string())
      } else {
        None
      }
      let content = match kind {
        3 => Binary(reader.buffer())
        8 => {
          let values = []
          let count = reader.count()
          for _ in 0..<count {
            values.push(reader.any())
          }
          Values(ReadOnlyArray::from_array(values[:]))
        }
        4 => Characters(reader.string())
        0 | 1 | 10 => {
          let length = reader.clock()
          guard length <= 0x7fff_ffffU else {
            raise InvalidData("block too large")
          }
          if kind == 1 {
            Deleted(length.reinterpret_as_int())
          } else {
            Garbage(length.reinterpret_as_int())
          }
        }
        _ => raise InvalidData("unsupported item content")
      }
      let length = content.length()
      guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
        raise InvalidData("clock overflow")
      }
      if length > 0 && kind != 10 {
        items.push({
          id: { client, clock, },
          origin,
          right_origin,
          parent,
          parent_sub,
          content,
        })
      }
      clock += length.reinterpret_as_uint()
    }
  }
  let deletions = []
  let clients = reader.count()
  for _ in 0..<clients {
    let client = reader.uint()
    let count = reader.count()
    for _ in 0..<count {
      let start = reader.clock()
      let len = reader.clock()
      guard start.to_uint64() + len.to_uint64() <= 0xffff_ffffUL else {
        raise InvalidData("delete range overflow")
      }
      deletions.push((client, start, start + len))
    }
  }
  reader.finish()
  (items, deletions)
}

///|
/// Decode the entire update before mutating the document. Missing dependencies
/// and early deletions remain pending and are retried on subsequent updates.
pub fn Doc::apply_update_v1(
  self : Doc,
  bytes : Bytes,
) -> Unit raise DecodeError {
  let (items, deletions) = read_update({ bytes, offset: 0, })
  for raw in items {
    self.pending.push(raw)
  }
  for (client, start, end) in deletions {
    self.add_delete(client, start, end)
  }
  self.settle()
}

///|
pub fn Doc::encode_state_as_update_v1(
  self : Doc,
  remote~ : StateVector = StateVector(),
) -> Bytes {
  let writer : Writer = { bytes: [], }
  let clients = self.state
    .entries()
    .filter(fn(pair) { pair.1 > remote.get(pair.0) })
  clients.sort_by(fn(a, b) { b.0.compare(a.0) })
  writer.uint(clients.length().to_uint64())
  for (client, _) in clients {
    let known = remote.get(client)
    let items = self.clients[client].filter(fn(item) {
      item.id.clock + item.content.length().reinterpret_as_uint() > known
    })
    writer.uint(items.length().to_uint64())
    writer.uint(client)
    writer.uint(known.to_uint64())
    for item in items {
      let offset = if item.id.clock < known {
        (known - item.id.clock).reinterpret_as_int()
      } else {
        0
      }
      let content = item.content.slice(offset, item.content.length())
      let origin = if offset == 0 {
        item.origin
      } else {
        Some({ client, clock: known - 1U, })
      }
      let kind = match content {
        Characters(_) => 4
        Values(_) => 8
        Binary(_) => 3
        Deleted(_) => 1
        Garbage(_) => 0
      }
      let info = if kind == 0 {
        0
      } else {
        kind |
        (if origin is Some(_) { 128 } else { 0 }) |
        (if item.right_origin is Some(_) { 64 } else { 0 }) |
        (if item.parent_sub is Some(_) { 32 } else { 0 })
      }
      writer.byte(info)
      if kind != 0 {
        if origin is Some(id) {
          writer.id(id)
        }
        if item.right_origin is Some(id) {
          writer.id(id)
        }
        if origin is None && item.right_origin is None {
          writer.uint(1UL)
          writer.string(item.parent.unwrap())
          if item.parent_sub is Some(key) {
            writer.string(key)
          }
        }
      }
      match content {
        Characters(s) => writer.string(s)
        Binary(b) => writer.buffer(b)
        Values(values) => {
          writer.uint(values.length().to_uint64())
          for value in values {
            writer.any(value)
          }
        }
        Deleted(n) | Garbage(n) => writer.uint(n.to_uint64())
      }
    }
  }
  let clients = self.deletes.to_array()
  clients.sort_by(fn(a, b) { b.0.compare(a.0) })
  writer.uint(clients.length().to_uint64())
  for (client, ranges) in clients {
    writer.uint(client)
    writer.uint(ranges.length().to_uint64())
    for (start, end) in ranges {
      writer.uint(start.to_uint64())
      writer.uint((end - start).to_uint64())
    }
  }
  writer.finish()
}
