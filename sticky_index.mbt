///|
pub(all) enum Assoc {
  Before
  After
} derive(Debug, Eq)

///|
pub(all) enum IndexScope {
  Relative(Id)
  Nested(Id)
  Root(String)
} derive(Debug, Eq)

///|
pub(all) enum BranchId {
  Nested(Id)
  Root(String)
} derive(Debug, Eq)

///|
pub(all) struct StickyIndex {
  scope : IndexScope
  assoc : Assoc
} derive(Debug, Eq)

///|
pub fn StickyIndex::StickyIndex(
  scope~ : IndexScope,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope, assoc, }
}

///|
pub(all) struct Offset {
  branch : BranchId
  index : Int32
  assoc : Assoc
} derive(Debug, Eq)

///|
pub fn StickyIndex::id(self : StickyIndex) -> Id? {
  match self.scope {
    Relative(id) => Some(id)
    _ => None
  }
}

///|
pub fn StickyIndex::is_root(self : StickyIndex) -> Bool {
  self.scope is Root(_)
}

///|
pub fn StickyIndex::is_nested(self : StickyIndex) -> Bool {
  self.scope is Nested(_)
}

///|
pub fn StickyIndex::is_relative(self : StickyIndex) -> Bool {
  self.scope is Relative(_)
}

///|
pub fn StickyIndex::encode_v1(self : StickyIndex) -> Bytes {
  let writer : Writer = { bytes: [], }
  match self.scope {
    Relative(id) => {
      writer.uint(0UL)
      writer.id(id)
    }
    Root(name) => {
      writer.uint(1UL)
      writer.string(name)
    }
    Nested(id) => {
      writer.uint(2UL)
      writer.id(id)
    }
  }
  writer.signed(if self.assoc == Before { -1L } else { 0L })
  writer.finish()
}

///|
pub fn StickyIndex::decode_v1(bytes : Bytes) -> StickyIndex raise DecodeError {
  let reader : Reader = { bytes, offset: 0, }
  let scope = match reader.uint() {
    0UL => IndexScope::Relative(reader.id())
    1UL => Root(reader.string())
    2UL => Nested(reader.id())
    _ => raise InvalidData("invalid sticky index scope")
  }
  let assoc = reader.signed()
  guard assoc >= -128L && assoc <= 127L else {
    raise InvalidData("invalid association")
  }
  reader.finish()
  { scope, assoc: if assoc < 0L { Before } else { After }, }
}

///|
fn Parent::index_scope(self : Parent) -> IndexScope {
  match self {
    Root(name) => Root(name)
    Nested(id) => Nested(id)
  }
}

///|
fn Parent::branch_id(self : Parent) -> BranchId {
  match self {
    Root(name) => Root(name)
    Nested(id) => Nested(id)
  }
}

///|
fn Doc::sticky_index(
  self : Doc,
  name : Parent,
  index : Int32,
  assoc : Assoc,
) -> StickyIndex? {
  guard index >= 0 else { return None }
  let text : Text = { doc: self, name, }
  let length = text.length()
  if assoc == Before && index == 0 {
    return Some({ scope: name.index_scope(), assoc, })
  }
  let mut remaining = index - (if assoc == Before { 1 } else { 0 })
  guard remaining <= length else { return None }
  let mut cursor = self.branch(name).head
  let mut last = None
  while cursor is Some(id) {
    let item = self.items[id]
    if !item.deleted && item.content.offset_length(self) > 0 {
      if remaining < item.content.offset_length(self) {
        return Some({
          scope: Relative({
            client: id.client,
            clock: id.clock + remaining.reinterpret_as_uint(),
          }),
          assoc,
        })
      }
      remaining -= item.content.offset_length(self)
    }
    last = Some(item)
    cursor = item.right
  }
  if assoc == After {
    None
  } else {
    let scope = match last {
      Some(item) =>
        IndexScope::Relative({
          client: item.id.client,
          clock: item.id.clock +
          item.content.length().reinterpret_as_uint() -
          1U,
        })
      None => name.index_scope()
    }
    Some({ scope, assoc, })
  }
}

///|
pub fn StickyIndex::get_offset(self : StickyIndex, doc : Doc) -> Offset? {
  let (parent, index) = match self.scope {
    Relative(original) => {
      guard doc.follow_redone(original) is Some(id) else { return None }
      guard doc.state.get(id.client) > id.clock &&
        doc.find(id) is Some(item) &&
        item.parent is Some(parent) else {
        return None
      }
      let deleted_parent = match parent {
        Root(_) => false
        Nested(id) =>
          doc.find(id).map(fn(owner) { owner.deleted }).unwrap_or(true)
      }
      let mut index = 0
      if !deleted_parent {
        if !item.deleted && item.content.offset_length(doc) > 0 {
          index = (id.clock - item.id.clock).reinterpret_as_int() +
            (if self.assoc == Before { 1 } else { 0 })
        }
        let mut left = item.left
        while left is Some(id) {
          let previous = doc.items[id]
          if !previous.deleted {
            index += previous.content.offset_length(doc)
          }
          left = previous.left
        }
      }
      (parent, index)
    }
    Root(name) => {
      let parent = Parent::Root(name)
      guard doc.roots.contains(parent) else { return None }
      let text : Text = { doc, name: parent, }
      (parent, if self.assoc == After { text.length() } else { 0 })
    }
    Nested(original) => {
      guard doc.follow_redone(original) is Some(id) else { return None }
      guard doc.state.get(id.client) > id.clock &&
        doc.find(id) is Some({ content: Shared(_), .. }) else {
        return None
      }
      let parent = Parent::Nested(id)
      let text : Text = { doc, name: parent, }
      (parent, if self.assoc == After { text.length() } else { 0 })
    }
  }
  Some({ branch: parent.branch_id(), index, assoc: self.assoc, })
}

///|
/// Track a position using CRDT identity. After at the end returns None, matching
/// Yrs; use a Root/Nested StickyIndex to explicitly track a type boundary.
pub fn Text::sticky_index(
  self : Text,
  index : Int32,
  assoc~ : Assoc = After,
) -> StickyIndex? {
  self.doc.sticky_index(self.name, index, assoc)
}

///|
/// Track a position using CRDT identity. After at the end returns None, matching
/// Yrs; use a Root/Nested StickyIndex to explicitly track a type boundary.
pub fn ArrayRef::sticky_index(
  self : ArrayRef,
  index : Int32,
  assoc~ : Assoc = After,
) -> StickyIndex? {
  self.doc.sticky_index(self.name, index, assoc)
}

///|
/// Track a position using CRDT identity. After at the end returns None, matching
/// Yrs; use a Root/Nested StickyIndex to explicitly track a type boundary.
pub fn XmlFragment::sticky_index(
  self : XmlFragment,
  index : Int32,
  assoc~ : Assoc = After,
) -> StickyIndex? {
  self.doc.sticky_index(self.name, index, assoc)
}

///|
/// Track a position using CRDT identity. After at the end returns None, matching
/// Yrs; use a Root/Nested StickyIndex to explicitly track a type boundary.
pub fn XmlElement::sticky_index(
  self : XmlElement,
  index : Int32,
  assoc~ : Assoc = After,
) -> StickyIndex? {
  self.doc.sticky_index(self.name, index, assoc)
}

///|
/// Track a position using CRDT identity. After at the end returns None, matching
/// Yrs; use a Root/Nested StickyIndex to explicitly track a type boundary.
pub fn XmlText::sticky_index(
  self : XmlText,
  index : Int32,
  assoc~ : Assoc = After,
) -> StickyIndex? {
  self.doc.sticky_index(self.name, index, assoc)
}

///|
pub extend Assoc with Debug::{to_repr}

///|
pub extend Assoc with Eq::{equal, not_equal}

///|
pub extend IndexScope with Debug::{to_repr}

///|
pub extend IndexScope with Eq::{equal, not_equal}

///|
pub extend BranchId with Debug::{to_repr}

///|
pub extend BranchId with Eq::{equal, not_equal}

///|
pub extend StickyIndex with Debug::{to_repr}

///|
pub extend StickyIndex with Eq::{equal, not_equal}

///|
pub extend Offset with Debug::{to_repr}

///|
pub extend Offset with Eq::{equal, not_equal}

///|
pub fn StickyIndex::to_json(self : StickyIndex) -> Json {
  let result : Map[String, Json] = {
    "assoc": Json(if self.assoc == Before { -1 } else { 0 }),
  }
  fn id_json(id : Id) -> Json {
    {
      "client": Json::number(id.client.to_double(), repr=id.client.to_string()),
      "clock": Json::number(id.clock.to_double(), repr=id.clock.to_string()),
    }
  }
  match self.scope {
    Relative(id) => result["item"] = id_json(id)
    Nested(id) => result["type"] = id_json(id)
    Root(name) => result["tname"] = Json(name)
  }
  Json(result)
}

///|
pub fn StickyIndex::from_json(value : Json) -> StickyIndex raise DecodeError {
  guard value is Object(fields) else {
    raise InvalidData("sticky index must be an object")
  }
  for key, _ in fields {
    guard ["item", "type", "tname", "assoc"].contains(key) else {
      raise InvalidData("unknown sticky index field")
    }
  }
  fn number(value : Json, maximum : UInt64) -> UInt64 raise DecodeError {
    guard value is Number(_, repr~) else {
      raise InvalidData("expected unsigned integer")
    }
    let repr = repr.unwrap_or(value.stringify())
    guard !repr.is_empty() else { raise InvalidData("empty integer") }
    let mut n = 0UL
    for ch in repr {
      guard ch >= '0' && ch <= '9' else {
        raise InvalidData("invalid unsigned integer")
      }
      let digit = (ch.to_int() - 48).to_uint64()
      guard n <= (maximum - digit) / 10UL else {
        raise InvalidData("integer overflow")
      }
      n = n * 10UL + digit
    }
    n
  }
  fn id(value : Json) -> Id raise DecodeError {
    guard value is Object(fields) &&
      fields.get("client") is Some(client) &&
      fields.get("clock") is Some(clock) else {
      raise InvalidData("invalid item identity")
    }
    {
      client: number(client, 0xffff_ffff_ffff_ffffUL),
      clock: number(clock, 0xffff_ffffUL).to_uint(),
    }
  }
  let item = match fields.get("item") {
    None | Some(Null) => None
    Some(value) => Some(id(value))
  }
  let nested = match fields.get("type") {
    None | Some(Null) => None
    Some(value) => Some(id(value))
  }
  let name = match fields.get("tname") {
    None | Some(Null) => None
    Some(String(name)) => Some(name)
    _ => raise InvalidData("invalid root type name")
  }
  let scope : IndexScope = match (item, name, nested) {
    (Some(id), _, _) => Relative(id)
    (_, Some(name), _) => Root(name)
    (_, _, Some(id)) => Nested(id)
    _ => raise InvalidData("missing sticky index scope")
  }
  let assoc = match fields.get("assoc") {
    None | Some(Null) => Assoc::After
    Some(Number(n, ..)) if n == -1.0 => Before
    Some(Number(n, ..)) if n == 0.0 => After
    _ => raise InvalidData("invalid association")
  }
  { scope, assoc, }
}

///|
/// Track the start or end of this shared sequence, including an empty sequence.
pub fn Text::sticky_boundary(
  self : Text,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope: self.name.index_scope(), assoc, }
}

///|
/// Track the start or end of this shared sequence, including an empty sequence.
pub fn ArrayRef::sticky_boundary(
  self : ArrayRef,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope: self.name.index_scope(), assoc, }
}

///|
/// Track the start or end of this shared sequence, including an empty sequence.
pub fn XmlFragment::sticky_boundary(
  self : XmlFragment,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope: self.name.index_scope(), assoc, }
}

///|
/// Track the start or end of this shared sequence, including an empty sequence.
pub fn XmlElement::sticky_boundary(
  self : XmlElement,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope: self.name.index_scope(), assoc, }
}

///|
/// Track the start or end of this shared sequence, including an empty sequence.
pub fn XmlText::sticky_boundary(
  self : XmlText,
  assoc~ : Assoc = After,
) -> StickyIndex {
  { scope: self.name.index_scope(), assoc, }
}
