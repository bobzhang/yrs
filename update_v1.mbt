///|
fn read_update(reader : Reader) -> (Array[RawItem], IdSet) raise DecodeError {
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
      if kind == 10 {
        let length = reader.clock()
        guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
          raise InvalidData("clock overflow")
        }
        clock += length
        continue
      }
      let parent : Parent? = if kind != 0 &&
        kind != 10 &&
        origin is None &&
        right_origin is None {
        match reader.uint() {
          1UL => Some(Root(reader.string()))
          0UL => Some(Nested(reader.id()))
          _ => raise InvalidData("invalid parent discriminator")
        }
      } else {
        None
      }
      let parent_sub = if parent is Some(_) && (info & 32) != 0 {
        Some(reader.string())
      } else {
        None
      }
      let content = match kind {
        2 => {
          let values = []
          let count = reader.count()
          for _ in 0..<count {
            let value = reader.string()
            values.push(
              if value == "undefined" {
                Undefined
              } else {
                Any::from_json(
                  @json.parse(value) catch {
                    _ => raise InvalidData("invalid legacy JSON")
                  },
                )
              },
            )
          }
          LegacyJson(ReadOnlyArray::from_array(values[:]))
        }
        9 => Subdocument(reader.subdocument())
        5 => Embed(reader.json_value())
        6 => Format(reader.string(), reader.json_value())
        7 =>
          Shared(
            match reader.byte() {
              0 => SharedArray
              1 => SharedMap
              2 => SharedText
              3 => SharedXmlElement(reader.string())
              4 => SharedXmlFragment
              6 => SharedXmlText
              7 => SharedWeak(reader.weak_link())
              5 | 9 | 15 as reference => SharedOpaque(reference)
              _ => raise InvalidData("unsupported shared type")
            },
          )
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
  let deletions = IdSet::read(reader, false)
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
  let deletions = deletions.ranges()
  self.with_mutation(fn() {
    self.active_transaction.unwrap().is_local = false
    self.collect_deletes = true
    let retained = self.pending[:].to_owned()
    self.pending.clear()
    for raw in items {
      self.pending.push(raw)
    }
    for (client, start, end) in deletions {
      self.add_delete(client, start, end)
    }
    self.settle(incoming=deletions)
    for raw in retained {
      self.pending.push(raw)
    }
    self.settle()
  })
}

///|
pub fn Doc::encode_state_as_update_v1(
  self : Doc,
  remote~ : StateVector = StateVector(),
) -> Bytes {
  self.encode_document(remote, true)
}

///|
fn Doc::encode_document(
  self : Doc,
  remote : StateVector,
  include_pending : Bool,
) -> Bytes {
  let items = []
  for client, blocks in self.clients {
    if remote.clocks.contains(client) &&
      self.state.get(client) <= remote.get(client) {
      continue
    }
    for item in blocks {
      if item.id.clock + item.content.length().reinterpret_as_uint() >
        remote.get(client) {
        items.push(
          (
            {
              id: item.id,
              origin: item.origin,
              right_origin: item.right_origin,
              parent: item.parent,
              parent_sub: item.parent_sub,
              content: item.content,
            } : RawItem).trim_start(remote.get(client)),
        )
      }
    }
  }
  // Pending blocks must be forwarded even when a recipient's advertised state
  // is ahead of our integrated prefix. They may carry missing dependencies.
  if include_pending {
    for item in self.pending {
      items.push(item)
    }
  }
  encode_raw_update(
    items,
    if include_pending {
      self.deletes
    } else {
      self.snapshot().deletes
    },
  )
}

///|
fn Writer::raw_item(self : Writer, item : RawItem) -> Unit {
  let content = item.content
  let origin = item.origin
  let kind = match content {
    Characters(_) => 4
    Values(_) => 8
    LegacyJson(_) => 2
    Binary(_) => 3
    Shared(_) => 7
    Subdocument(_) => 9
    Format(_, _) => 6
    Embed(_) => 5
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
  self.byte(info)
  if kind != 0 {
    if origin is Some(id) {
      self.id(id)
    }
    if item.right_origin is Some(id) {
      self.id(id)
    }
    if origin is None && item.right_origin is None {
      match item.parent.unwrap() {
        Root(name) => {
          self.uint(1UL)
          self.string(name)
        }
        Nested(id) => {
          self.uint(0UL)
          self.id(id)
        }
      }
      if item.parent_sub is Some(key) {
        self.string(key)
      }
    }
  }
  match content {
    Subdocument(child) => {
      self.string(child.guid())
      self.any(child.wire_options())
    }
    Characters(s) => self.string(s)
    Binary(b) => self.buffer(b)
    Format(key, value) => {
      self.string(key)
      self.string(value.to_json().stringify())
    }
    Embed(value) => self.string(value.to_json().stringify())
    Shared(kind) =>
      match kind {
        SharedArray => self.byte(0)
        SharedMap => self.byte(1)
        SharedText => self.byte(2)
        SharedXmlElement(tag) => {
          self.byte(3)
          self.string(tag)
        }
        SharedXmlFragment => self.byte(4)
        SharedXmlText => self.byte(6)
        SharedWeak(link) => {
          self.byte(7)
          self.weak_link(link)
        }
        SharedOpaque(reference) => self.byte(reference)
      }
    LegacyJson(values) => {
      self.uint(values.length().to_uint64())
      for value in values {
        self.string(
          if value is Undefined {
            "undefined"
          } else {
            value.to_json().stringify()
          },
        )
      }
    }
    Values(values) => {
      self.uint(values.length().to_uint64())
      for value in values {
        self.any(value)
      }
    }
    Deleted(n) | Garbage(n) => self.uint(n.to_uint64())
  }
}

///|
fn Reader::json_value(self : Reader) -> Any raise DecodeError {
  let value = @json.parse(self.string()) catch {
    _ => raise InvalidData("invalid embedded JSON")
  }
  Any::from_json(value)
}
