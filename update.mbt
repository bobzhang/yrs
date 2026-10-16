///|
/// A decoded, unintegrated update. Inspect or merge it without creating a replica.
pub struct Update {
  priv mut wire : Bytes
  priv mut blocks : Array[RawItem]
  priv deleted : IdSet
  priv mut has_blocks : Bool
}

///|
pub fn Update::Update() -> Update {
  { wire: b"\x00\x00", blocks: [], deleted: IdSet(), has_blocks: false, }
}

///|
pub fn Update::decode_v1(bytes : Bytes) -> Update raise DecodeError {
  let (blocks, deleted) = read_update({ bytes, offset: 0, })
  let header : Reader = { bytes, offset: 0, }
  {
    wire: bytes,
    blocks: normalize_items(blocks),
    deleted: IdSet(ranges=deleted),
    has_blocks: header.uint() > 0UL,
  }
}

///|
pub fn Update::decode_v2(
  bytes : Bytes,
  max_items~ : Int32 = 1000000,
) -> Update raise DecodeError {
  Update::decode_v1(convert_update_v2_to_v1(bytes, max_items~))
}

///|
pub fn Update::encode_v1(self : Update) -> Bytes {
  self.wire
}

///|
pub fn Update::encode_v2(self : Update) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(self.wire, max_items=0x7fff_ffff)
}

///|
pub fn Update::is_empty(self : Update) -> Bool {
  !self.has_blocks && self.deleted.is_empty()
}

///|
/// Whether a non-skip block covers the next expected clock for any client.
/// Deletions alone do not extend a state vector.
pub fn Update::extends(self : Update, state : StateVector) -> Bool {
  self.blocks.any(fn(item) {
    let clock = state.get(item.id.client)
    item.id.clock <= clock &&
    clock < item.id.clock + item.content.length().reinterpret_as_uint()
  })
}

///|
pub fn Update::state_vector(self : Update) -> StateVector {
  let result = StateVector()
  for item in self.blocks {
    if item.id.clock == result.get(item.id.client) {
      result.set_max(
        item.id.client,
        item.id.clock + item.content.length().reinterpret_as_uint(),
      )
    }
  }
  result
}

///|
pub fn Update::state_vector_lower(self : Update) -> StateVector {
  let result = StateVector()
  for item in self.blocks {
    if !result.contains_client(item.id.client) {
      result.set_max(item.id.client, item.id.clock)
    }
  }
  result
}

///|
/// The wire delete set has not been integrated: encoded item blocks (including
/// ContentDeleted) are included; include_deleted also includes GC blocks.
pub fn Update::insertions(
  self : Update,
  include_deleted~ : Bool = false,
) -> IdSet {
  let result = IdSet()
  for item in self.blocks {
    if include_deleted || !(item.content is Garbage(_)) {
      result.insert(item.id, item.content.length().reinterpret_as_uint())
    }
  }
  result
}

///|
pub fn Update::delete_set(self : Update) -> IdSet {
  IdSet(ranges=self.deleted.ranges())
}

///|
pub fn Update::merge(self : Update, other : Update) -> Unit {
  self.blocks = normalize_items(self.blocks + other.blocks)
  self.deleted.merge_with(other.deleted)
  self.wire = encode_raw_update(
    self.blocks,
    Snapshot(deletions=self.deleted.ranges()).deletes,
  )
  self.has_blocks = !self.blocks.is_empty()
}

///|
pub fn Update::encode_diff_v1(self : Update, state : StateVector) -> Bytes {
  let blocks = self.blocks.filter_map(fn(item) {
    let known = state.get(item.id.client)
    if item.id.clock + item.content.length().reinterpret_as_uint() > known {
      Some(item.trim_start(known))
    } else {
      None
    }
  })
  encode_raw_update(blocks, Snapshot(deletions=self.deleted.ranges()).deletes)
}

///|
pub fn Update::encode_diff_v2(
  self : Update,
  state : StateVector,
) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(self.encode_diff_v1(state), max_items=0x7fff_ffff)
}

///|
pub fn Doc::apply_update(self : Doc, update : Update) -> Unit raise DecodeError {
  self.apply_update_v1(update.encode_v1())
}
