///|
priv enum Parent {
  Root(String)
  Nested(Id)
} derive(Eq, Hash)

///|
priv enum SharedKind {
  SharedArray
  SharedMap
  SharedText
  SharedXmlElement(String)
  SharedXmlFragment
  SharedXmlText
}

///|
priv enum Content {
  Characters(String)
  Values(ReadOnlyArray[Any])
  Binary(Bytes)
  Shared(SharedKind)
  Subdocument(Doc)
  Format(String, Any)
  Embed(Any)
  Deleted(Int32)
  Garbage(Int32)
}

///|
fn Content::length(self : Content) -> Int32 {
  match self {
    Characters(s) => s.length()
    Values(values) => values.length()
    Binary(_) | Shared(_) | Subdocument(_) | Format(_, _) | Embed(_) => 1
    Deleted(n) | Garbage(n) => n
  }
}

///|
// Yjs indexes text by UTF-16 code units. Splitting a surrogate pair replaces
// the orphaned halves with U+FFFD, while preserving their two logical clocks.
fn utf16_slice(s : String, start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  let mut offset = 0
  for c in s {
    let size = if c.to_int() > 0xffff { 2 } else { 1 }
    if offset >= start && offset + size <= end {
      out.write_char(c)
    } else if offset < end && offset + size > start {
      out.write_char('\ufffd')
    }
    offset += size
  }
  out.to_string()
}

///|
fn Content::slice(self : Content, start : Int32, end : Int32) -> Content {
  match self {
    Characters(s) => Characters(utf16_slice(s, start, end))
    Values(values) =>
      Values(
        ReadOnlyArray::from_array(
          Array::makei(end - start, fn(i) { values[start + i] })[:],
        ),
      )
    Binary(_) | Shared(_) | Subdocument(_) | Format(_, _) | Embed(_) => {
      guard start == 0 && end == 1 else { abort("binary item is indivisible") }
      self
    }
    Deleted(_) => Deleted(end - start)
    Garbage(_) => Garbage(end - start)
  }
}

///|
priv struct RawItem {
  id : Id
  origin : Id?
  right_origin : Id?
  parent : Parent?
  parent_sub : String?
  content : Content
}

///|
priv struct Item {
  id : Id
  origin : Id?
  right_origin : Id?
  parent : Parent?
  parent_sub : String?
  mut content : Content
  mut left : Id?
  mut right : Id?
  mut redone : Id?
  mut deleted : Bool
  mut keep : Bool
}

///|
priv struct Branch {
  mut kind : SharedKind?
  mut head : Id?
  heads : Map[String, Id]
  values : Map[String, Id]
  mut formatted : Bool
}

///|
/// A document replica. Each independently edited replica must use a distinct
/// client ID. This initial API uses Yjs UTF-16 positions and retains tombstones.
pub struct Doc {
  priv identity : UInt64
  priv mut active_transaction : Transaction?
  priv mut notifying_transaction : Bool
  priv deep_observers : Map[
    Parent,
    Map[String, (ReadOnlyArray[Event], Transaction) -> Unit],
  ]
  priv xml_observers : Map[Parent, Map[String, (XmlEvent, Transaction) -> Unit]]
  priv xml_text_observers : Map[
    Parent,
    Map[String, (XmlTextEvent, Transaction) -> Unit],
  ]
  priv array_observers : Map[
    Parent,
    Map[String, (ArrayEvent, Transaction) -> Unit],
  ]
  priv text_observers : Map[
    Parent,
    Map[String, (TextEvent, Transaction) -> Unit],
  ]
  priv map_observers : Map[Parent, Map[String, (MapEvent, Transaction) -> Unit]]
  priv before_observers : Map[String, (Transaction) -> Unit]
  priv after_observers : Map[String, (Transaction) -> Unit]
  priv cleanup_observers : Map[String, (Transaction) -> Unit]
  priv update_v1_observers : Map[String, (Bytes, Transaction) -> Unit]
  priv update_v2_observers : Map[String, (Bytes, Transaction) -> Unit]
  priv mut client : UInt64
  priv document_guid : String
  priv mut collection : String?
  priv auto_loading : Bool
  priv mut loading : Bool
  priv wire_gc : Bool
  priv wire_encoding : Int32
  priv mut owner : (Doc, Id)?
  priv children_docs : Map[UInt64, Doc]
  priv undo_retention : Map[String, () -> Array[(UInt64, UInt32, UInt32)]]
  priv subdoc_observers : Map[String, (SubdocsEvent, Transaction) -> Unit]
  priv destroy_observers : Map[String, (Doc) -> Unit]
  priv state : StateVector
  priv clients : Map[UInt64, Array[Item]]
  priv items : Map[Id, Item]
  priv roots : Map[Parent, Branch]
  priv pending : Array[RawItem]
  priv mut collect_deletes : Bool
  priv deleted_items : Array[Item]
  priv inserted_items : Array[Item]
  priv deletes : Map[UInt64, Array[(UInt32, UInt32)]]
}

///|
pub fn Doc::Doc(
  client_id~ : UInt64,
  guid~ : String = "",
  collection_id? : String,
  auto_load~ : Bool = false,
  should_load~ : Bool = true,
  offset_kind~ : OffsetKind = Utf16,
  skip_gc~ : Bool = true,
) -> Doc {
  make_doc(
    client_id,
    guid,
    collection_id,
    auto_load,
    should_load,
    !skip_gc,
    if offset_kind == Bytes {
      1
    } else {
      0
    },
  )
}

///|
fn make_doc(
  client : UInt64,
  guid : String,
  collection : String?,
  auto_load : Bool,
  should_load : Bool,
  wire_gc : Bool,
  wire_encoding : Int32,
) -> Doc {
  {
    identity: allocate_identity(),
    active_transaction: None,
    notifying_transaction: false,
    deep_observers: {},
    xml_observers: {},
    xml_text_observers: {},
    array_observers: {},
    text_observers: {},
    map_observers: {},
    before_observers: {},
    after_observers: {},
    cleanup_observers: {},
    update_v1_observers: {},
    update_v2_observers: {},
    client,
    document_guid: guid,
    collection,
    auto_loading: auto_load,
    loading: should_load,
    wire_gc,
    wire_encoding,
    owner: None,
    children_docs: {},
    undo_retention: {},
    subdoc_observers: {},
    destroy_observers: {},
    state: StateVector(),
    clients: Map([]),
    items: Map([]),
    roots: Map([]),
    pending: [],
    deletes: Map([]),
    collect_deletes: false,
    deleted_items: [],
    inserted_items: [],
  }
}

///|
pub fn Doc::client_id(self : Doc) -> UInt64 {
  self.client
}

///|
pub fn Doc::state_vector(self : Doc) -> StateVector {
  StateVector(entries=self.state.entries())
}

///|
pub fn Doc::pending_items(self : Doc) -> Int32 {
  self.pending.length()
}

///|
fn Doc::branch(self : Doc, name : Parent) -> Branch {
  match self.roots.get(name) {
    Some(b) => b
    None => {
      let b : Branch = {
        kind: None,
        head: None,
        heads: Map([]),
        values: Map([]),
        formatted: false,
      }
      self.roots[name] = b
      b
    }
  }
}

///|
fn Doc::find(self : Doc, id : Id) -> Item? {
  guard self.clients.get(id.client) is Some(items) else { return None }
  for lo = 0, hi = items.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let item = items[mid]
    if id.clock < item.id.clock {
      continue lo, mid
    } else if id.clock - item.id.clock >=
      item.content.length().reinterpret_as_uint() {
      continue mid + 1, hi
    } else {
      return Some(item)
    }
  } nobreak {
    None
  }
}

///|
fn Doc::split(self : Doc, item : Item, at : Int32) -> Item {
  if self.active_transaction is Some(transaction) {
    transaction.merge_clients.add(item.id.client) |> ignore
  }
  let length = item.content.length()
  guard at > 0 && at < length else { abort("invalid item split") }
  let id : Id = {
    client: item.id.client,
    clock: item.id.clock + at.reinterpret_as_uint(),
  }
  let tail : Item = {
    id,
    origin: Some({ client: id.client, clock: id.clock - 1U, }),
    right_origin: item.right_origin,
    parent: item.parent,
    parent_sub: item.parent_sub,
    content: item.content.slice(at, length),
    left: Some(item.id),
    right: item.right,
    redone: item.redone.map(fn(id) {
      ({ client: id.client, clock: id.clock + at.reinterpret_as_uint(), } : Id)
    }),
    deleted: item.deleted,
    keep: item.keep,
  }
  if item.right is Some(right) {
    self.items[right].left = Some(id)
  } else if item.parent is Some(parent) && item.parent_sub is Some(key) {
    self.branch(parent).values[key] = id
  }
  item.content = item.content.slice(0, at)
  item.right = Some(id)
  let entries = self.clients[item.id.client]
  let index = for i = 0; i < entries.length(); i = i + 1 {
    if entries[i].id == item.id {
      break i
    }
  } nobreak {
    abort("missing split item")
  }
  entries.insert(index + 1, tail)
  self.items[id] = tail
  tail
}

///|
fn Doc::clean_start(self : Doc, id : Id) -> Item {
  let item = self.find(id).unwrap()
  if item.id.clock == id.clock {
    item
  } else {
    self.split(item, (id.clock - item.id.clock).reinterpret_as_int())
  }
}

///|
fn Doc::clean_end(self : Doc, id : Id) -> Item {
  let item = self.find(id).unwrap()
  let offset = (id.clock - item.id.clock).reinterpret_as_int() + 1
  if offset < item.content.length() {
    self.split(item, offset) |> ignore
  }
  item
}

///|
fn Doc::integrate(self : Doc, raw : RawItem) -> Bool {
  let end = raw.id.clock + raw.content.length().reinterpret_as_uint()
  let mut start = raw.id.clock
  let missing : Array[RawItem] = []
  for item in self.clients.get(raw.id.client).unwrap_or([]) {
    let item_end = item.id.clock + item.content.length().reinterpret_as_uint()
    if item_end <= start {
      continue
    }
    if item.id.clock >= end {
      break
    }
    if start < item.id.clock {
      missing.push({
        ..raw.trim_start(start),
        content: raw.content.slice(
          (start - raw.id.clock).reinterpret_as_int(),
          (item.id.clock - raw.id.clock).reinterpret_as_int(),
        ),
      })
    }
    start = start.max(item_end)
  }
  if start < end {
    missing.push(raw.trim_start(start))
  }
  for part in missing {
    if !self.integrate_missing(part) {
      return false
    }
  }
  true
}

///|
fn Doc::integrate_missing(self : Doc, raw : RawItem) -> Bool {
  if raw.parent is Some(Nested(id)) && self.find(id) is None {
    return false
  }
  for dep in [raw.origin, raw.right_origin] {
    if dep is Some(id) && self.find(id) is None {
      return false
    }
  }
  let mut left = raw.origin.map(fn(id) { self.clean_end(id).id })
  let right = raw.right_origin.map(fn(id) { self.clean_start(id).id })
  let mut parent = match raw.parent {
    Some(name) => Some(name)
    None =>
      match left {
        Some(id) => self.items[id].parent
        None => right.bind(fn(id) { self.items[id].parent })
      }
  }
  if parent is Some(Nested(id)) {
    let owner = self.find(id).unwrap()
    if !(owner.content is Shared(_)) {
      parent = None
    }
  }
  let parent_sub = match left.bind(fn(id) { self.items[id].parent_sub }) {
    Some(key) => Some(key)
    None =>
      match right.bind(fn(id) { self.items[id].parent_sub }) {
        Some(key) => Some(key)
        None => raw.parent_sub
      }
  }
  let mut content = raw.content
  if parent is None {
    content = Garbage(content.length())
  }
  let item : Item = {
    id: raw.id,
    origin: raw.origin,
    right_origin: raw.right_origin,
    parent,
    parent_sub,
    content,
    left,
    right,
    redone: None,
    keep: false,
    deleted: content is (Deleted(_) | Garbage(_)),
  }
  if parent is Some(name) && parent_sub is Some(key) {
    self.touch_map(name, key)
  }
  if parent is Some(name) {
    let branch = self.branch(name)
    if content is Format(_, _) {
      branch.formatted = true
    }
    let start = match left {
      Some(id) => self.items[id].right
      None => branch.first(parent_sub)
    }
    let conflict = match (left, right) {
      (None, Some(id)) => self.items[id].left is Some(_)
      _ => start != right || left is None
    }
    if conflict {
      let before : Set[Id] = Set([])
      let conflicting : Set[Id] = Set([])
      let mut cursor = start
      while cursor is Some(id) && cursor != right {
        let other = self.items[id]
        before.add(id)
        conflicting.add(id)
        if raw.origin == other.origin {
          if id.client < raw.id.client {
            left = Some(id)
            conflicting.clear()
          } else if raw.right_origin == other.right_origin {
            break
          }
        } else if other.origin is Some(origin) &&
          self.find(origin) is Some(origin_item) {
          if before.contains(origin_item.id) {
            if !conflicting.contains(origin_item.id) {
              left = Some(id)
              conflicting.clear()
            }
          } else {
            break
          }
        } else {
          break
        }
        cursor = other.right
      }
    }
    item.left = left
    item.right = match left {
      Some(id) => self.items[id].right
      None => branch.first(parent_sub)
    }
    if left is Some(id) {
      self.items[id].right = Some(item.id)
    } else {
      branch.set_first(parent_sub, item.id)
    }
    if item.right is Some(id) {
      self.items[id].left = Some(item.id)
    }
  }
  self.items[item.id] = item
  if self.active_transaction is Some(transaction) {
    if parent is Some(name) && parent_sub is None {
      transaction.sequences.add(name)
    }
    transaction.added.push(
      (
        item.id.client,
        item.id.clock,
        item.id.clock + item.content.length().reinterpret_as_uint(),
      ),
    )
    if item.deleted {
      transaction.removed.push(
        (
          item.id.client,
          item.id.clock,
          item.id.clock + item.content.length().reinterpret_as_uint(),
        ),
      )
    }
  }
  match self.clients.get(item.id.client) {
    Some(entries) => {
      let mut index = entries.length()
      while index > 0 && entries[index - 1].id.clock > item.id.clock {
        index -= 1
      }
      entries.insert(index, item)
    }
    None => self.clients[item.id.client] = [item]
  }
  if item.content is Subdocument(child) {
    child.owner = Some((self, item.id))
    if self.active_transaction is Some(txn) {
      txn.sub_changed = true
      txn.sub_added[child.identity] = child
      if child.loading {
        txn.sub_loaded[child.identity] = child
      }
    }
  }
  if parent is Some(name) && parent_sub is Some(key) {
    if item.right is None {
      self.branch(name).values[key] = item.id
      if item.left is Some(id) {
        self.mark_deleted(self.items[id])
      }
    } else {
      self.mark_deleted(item)
    }
  }
  if parent is Some(Nested(id)) && self.find(id).unwrap().deleted {
    self.mark_deleted(item)
  }
  if self.collect_deletes {
    self.inserted_items.push(item)
  }
  let mut prefix = self.state.get(item.id.client)
  while self.find({ client: item.id.client, clock: prefix, }) is Some(known) {
    prefix = known.id.clock + known.content.length().reinterpret_as_uint()
  }
  self.state.set_max(item.id.client, prefix)
  true
}

///|
fn Doc::settle(self : Doc) -> Unit {
  for ;; {
    let mut progress = false
    let unresolved = []
    let blocked : Set[UInt64] = Set([])
    for raw in normalize_items(self.pending) {
      if blocked.contains(raw.id.client) {
        unresolved.push(raw)
        continue
      }
      let before = self.items.length()
      if self.integrate(raw) {
        progress = true
      } else {
        unresolved.push(raw)
        blocked.add(raw.id.client)
      }
      if self.items.length() != before {
        progress = true
      }
    }
    self.pending.clear()
    for raw in unresolved {
      self.pending.push(raw)
    }
    if !progress {
      break
    }
  }
  for (client, ranges) in self.deletes.to_array() {
    for (start, end) in ranges {
      let known = self.clients
        .get(client)
        .map(fn(items) { items[:].to_owned() })
        .unwrap_or([])
      for found in known {
        let found_end = found.id.clock +
          found.content.length().reinterpret_as_uint()
        if found.id.clock >= end {
          break
        }
        if found_end <= start {
          continue
        }
        let item = if found.id.clock < start {
          self.split(found, (start - found.id.clock).reinterpret_as_int())
        } else {
          found
        }
        if item.id.clock + item.content.length().reinterpret_as_uint() > end {
          self.split(item, (end - item.id.clock).reinterpret_as_int()) |> ignore
        }
        self.mark_deleted(item)
      }
    }
  }
}

///|
fn Doc::add_delete(
  self : Doc,
  client : UInt64,
  start : UInt32,
  end : UInt32,
) -> Unit {
  if start == end {
    return
  }
  let ranges = self.deletes
    .get(client)
    .map(fn(ranges) { ranges[:].to_owned() })
    .unwrap_or([])
  ranges.push((start, end))
  ranges.sort_by(fn(a, b) { a.0.compare(b.0) })
  let merged : Array[(UInt32, UInt32)] = []
  for range in ranges {
    if merged.last() is Some(previous) && previous.1 >= range.0 {
      merged[merged.length() - 1] = (previous.0, previous.1.max(range.1))
    } else {
      merged.push(range)
    }
  }
  self.deletes[client] = merged
}

///|
pub struct Text {
  priv doc : Doc
  priv name : Parent
}

///|
pub fn Doc::get_or_insert_text(self : Doc, name : String) -> Text {
  let name : Parent = Root(name)
  self.register_kind(name, SharedText)
  { doc: self, name, }
}

///|
pub fn Text::get_string(self : Text) -> String {
  let out = StringBuilder()
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted && item.content is Characters(s) {
      out.write_string(s)
    }
    cursor = item.right
  }
  out.to_string()
}

///|
pub fn Text::length(self : Text) -> Int32 {
  let mut length = 0
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      length += item.content.offset_length(self.doc)
    }
    cursor = item.right
  }
  length
}

///|
fn Text::position(self : Text, index : Int32) -> (Id?, Id?) {
  guard index >= 0 else { abort("negative text index") }
  let mut remaining = index
  let mut left = None
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      if remaining == 0 {
        return (left, cursor)
      }
      let len = item.content.offset_length(self.doc)
      if remaining < len {
        let tail = self.doc.split(
          item,
          item.content.block_offset(remaining, self.doc),
        )
        return (Some(item.id), Some(tail.id))
      }
      remaining -= len
    }
    left = cursor
    cursor = item.right
  }
  guard remaining == 0 else { abort("text index out of bounds") }
  (left, None)
}

///|
pub fn Text::insert(self : Text, index : Int32, value : String) -> Unit {
  self.doc.with_mutation(fn() {
    let (left, right) = self.position(index)
    if value.is_empty() {
      return
    }
    let clock = self.doc.next_clock(self.doc.client)
    guard clock.to_uint64() + value.length().to_uint64() <= 0xffff_ffffUL else {
      abort("document clock exhausted")
    }
    let origin = left.map(fn(id) {
      let item = self.doc.items[id]
      (
        {
          client: id.client,
          clock: id.clock + item.content.length().reinterpret_as_uint() - 1U,
        } : Id)
    })
    let raw : RawItem = {
      id: { client: self.doc.client, clock, },
      origin,
      right_origin: right,
      parent: Some(self.name),
      parent_sub: None,
      content: Characters(value),
    }
    guard self.doc.integrate(raw) else {
      abort("local insert has missing dependency")
    }
    self.doc.settle()
  })
}

///|
pub fn Text::remove_range(self : Text, index : Int32, length : Int32) -> Unit {
  self.doc.with_mutation(fn() {
    guard length >= 0 &&
      index >= 0 &&
      index <= self.length() &&
      length <= self.length() - index else {
      abort("text deletion out of bounds")
    }
    let pos = self.rich_position(index)
    pos.remove(length)
  })
}

///|
fn Branch::first(self : Branch, key : String?) -> Id? {
  match key {
    None => self.head
    Some(key) => self.heads.get(key)
  }
}

///|
fn Branch::set_first(self : Branch, key : String?, id : Id) -> Unit {
  match key {
    None => self.head = Some(id)
    Some(key) => self.heads[key] = id
  }
}

///|
fn Doc::mark_deleted(self : Doc, item : Item) -> Unit {
  let work = [item]
  while work.pop() is Some(item) {
    if item.deleted {
      continue
    }
    if item.parent is Some(parent) && item.parent_sub is Some(key) {
      self.touch_map(parent, key)
    }
    if item.parent is Some(parent) &&
      item.parent_sub is None &&
      self.active_transaction is Some(transaction) {
      transaction.sequences.add(parent)
    }
    if item.content is Subdocument(child) &&
      self.active_transaction is Some(txn) {
      if txn.sub_added.contains(child.identity) {
        txn.sub_added.remove(child.identity)
      } else {
        txn.sub_removed[child.identity] = child
      }
    }
    item.deleted = true
    if self.active_transaction is Some(transaction) {
      transaction.removed.push(
        (
          item.id.client,
          item.id.clock,
          item.id.clock + item.content.length().reinterpret_as_uint(),
        ),
      )
    }
    if self.collect_deletes {
      self.deleted_items.push(item)
    }
    self.add_delete(
      item.id.client,
      item.id.clock,
      item.id.clock + item.content.length().reinterpret_as_uint(),
    )
    if item.content is Shared(_) &&
      self.roots.get(Nested(item.id)) is Some(branch) {
      // Only the current map value can be live. Restored values may retain
      // neighbors in an older parent, so a cached chain head is insufficient.
      for id in branch.values.values() {
        work.push(self.items[id])
      }
      let mut cursor = branch.head
      while cursor is Some(id) {
        let child = self.items[id]
        work.push(child)
        cursor = child.right
      }
    }
  }
}

///|
fn Content::visible_length(self : Content) -> Int32 {
  match self {
    Format(_, _) | Deleted(_) | Garbage(_) => 0
    _ => self.length()
  }
}

///|
fn Doc::next_clock(self : Doc, client : UInt64) -> UInt32 {
  match self.clients.get(client).bind(Array::last) {
    Some(item) => item.id.clock + item.content.length().reinterpret_as_uint()
    None => 0U
  }
}

///|
pub fn Doc::has_missing_updates(self : Doc) -> Bool {
  if !self.pending.is_empty() {
    return true
  }
  for client, _ in self.clients {
    if self.state.get(client) < self.next_clock(client) {
      return true
    }
  }
  for client, ranges in self.deletes {
    if ranges.last() is Some((_, end)) && end > self.next_clock(client) {
      return true
    }
  }
  false
}
