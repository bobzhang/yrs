///|
fn read_update(reader : Reader) -> (Array[RawItem], IdSet) raise DecodeError {
  let (items, deleted, _) = read_update_fields({
    raw: reader,
    columns: [],
    text: "",
    text_offset: 0,
    keys: [],
    budget: 0x7fff_ffff,
  })
  (items, deleted)
}

///|
/// Decode the entire update before mutating the document. Missing dependencies
/// and early deletions remain pending and are retried on subsequent updates.
pub fn Doc::apply_update_v1(
  self : Doc,
  bytes : Bytes,
) -> Unit raise DecodeError {
  let (items, deletions) = read_update({ bytes, offset: 0, })
  self.apply_raw_update(items, deletions)
}

///|
fn Doc::apply_raw_update(
  self : Doc,
  items : Array[RawItem],
  deletions : IdSet,
) -> Unit {
  let deletions = deletions.ranges()
  self.with_mutation(fn() {
    self.active_transaction.unwrap().is_local = false
    self.collect_deletes = true
    let retained = self.pending[:].to_owned()
    self.pending.clear()
    for raw in items {
      self.pending.push(raw.owned_update_item())
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
  v2~ : Bool = false,
) -> Bytes {
  let items = []
  for client, blocks in self.clients {
    let clock = remote.get(client)
    for index in first_block_after(blocks, clock)..<blocks.length() {
      let item = blocks[index]
      items.push(
        (
          {
            id: item.id,
            origin: item.origin,
            right_origin: item.right_origin,
            parent: item.parent,
            parent_sub: item.parent_sub,
            content: item.content,
          } : RawItem).trim_start(clock),
      )
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
      self.integrated_delete_set().deletion_map()
    },
    v2~,
  )
}

///|
fn UpdateWriter::raw_item(self : UpdateWriter, item : RawItem) -> Unit {
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
  self.field(4, info.to_uint64())
  if kind != 0 {
    if origin is Some(id) {
      self.field(1, id.client)
      self.field(2, id.clock.to_uint64())
    }
    if item.right_origin is Some(id) {
      self.field(1, id.client)
      self.field(3, id.clock.to_uint64())
    }
    if origin is None && item.right_origin is None {
      match item.parent.unwrap() {
        Root(name) => {
          self.field(6, 1UL)
          self.string(name)
        }
        Nested(id) => {
          self.field(6, 0UL)
          self.field(1, id.client)
          self.field(2, id.clock.to_uint64())
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
      self.raw.any(
        child.decoded_options.unwrap_or_else(fn() { child.wire_options() }),
      )
    }
    Characters(s) => self.string(s.text())
    Binary(b) => self.raw.buffer(b)
    Format(key, value) => {
      self.key(key)
      self.json(value)
    }
    Embed(value) => self.json(value)
    Shared(kind) =>
      match kind {
        SharedArray => self.field(7, 0UL)
        SharedMap => self.field(7, 1UL)
        SharedText => self.field(7, 2UL)
        SharedXmlElement(tag) => {
          self.field(7, 3UL)
          self.key(tag)
        }
        SharedXmlFragment => self.field(7, 4UL)
        SharedXmlText => self.field(7, 6UL)
        SharedWeak(link) => {
          self.field(7, 7UL)
          link.write(self)
        }
        SharedOpaque(reference) => self.field(7, reference.to_uint64())
      }
    LegacyJson(values) => {
      self.field(8, values.length().to_uint64())
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
      self.field(8, values.length().to_uint64())
      for value in values {
        self.raw.any(value)
      }
    }
    Deleted(n) | Garbage(n) => self.field(8, n.to_uint64())
  }
}
