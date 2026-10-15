///|
fn contains_range(ranges : Array[(UInt64, UInt32, UInt32)], id : Id) -> Bool {
  ranges.any(fn(r) { r.0 == id.client && r.1 <= id.clock && id.clock < r.2 })
}

///|
fn Doc::materialize_ranges(
  self : Doc,
  ranges : Array[(UInt64, UInt32, UInt32)],
) -> Array[Item] {
  let result : Array[Item] = []
  for (client, start, end) in ranges {
    let blocks = self.clients.get(client).unwrap_or([]).copy()
    for block in blocks {
      let stop = block.id.clock + block.content.length().reinterpret_as_uint()
      if block.id.clock >= end || stop <= start {
        continue
      }
      let item = self.clean_start({ client, clock: block.id.clock.max(start), })
      if end < stop {
        self.split(item, (end - item.id.clock).reinterpret_as_int()) |> ignore
      }
      result.push(item)
    }
  }
  result
}

///|
fn Out::location(self : Out) -> (Doc, Parent)? {
  match self {
    Value(_) | Subdoc(_) => None
    Array(v) => Some((v.doc, v.name))
    Map(v) => Some((v.doc, v.name))
    Text(v) => Some((v.doc, v.name))
    XmlElement(v) => Some((v.doc, v.name))
    XmlFragment(v) => Some((v.doc, v.name))
    XmlText(v) => Some((v.doc, v.name))
  }
}

///|
pub struct StackItem[M] {
  priv document : Doc
  priv mut inserted : Array[(UInt64, UInt32, UInt32)]
  priv mut deleted : Array[(UInt64, UInt32, UInt32)]
  mut meta : M
}

///|
pub fn[M] StackItem::insertions(
  self : StackItem[M],
) -> Array[(UInt64, UInt32, UInt32)] {
  self.inserted.copy()
}

///|
pub fn[M] StackItem::deletions(
  self : StackItem[M],
) -> Array[(UInt64, UInt32, UInt32)] {
  self.deleted.copy()
}

///|
pub fn[M] StackItem::doc(self : StackItem[M]) -> Doc {
  self.document
}

///|
pub(all) enum UndoEventKind {
  Undo
  Redo
} derive(Eq, Debug)

///|
pub extend UndoEventKind with Eq::{equal, not_equal}

///|
pub extend UndoEventKind with Debug::{to_repr}

///|
pub struct UndoEvent[M] {
  mut meta : M
  priv event_kind : UndoEventKind
  priv source : Bytes?
}

///|
pub fn[M] UndoEvent::kind(self : UndoEvent[M]) -> UndoEventKind {
  self.event_kind
}

///|
pub fn[M] UndoEvent::origin(self : UndoEvent[M]) -> Bytes? {
  self.source
}

///|
pub struct UndoManager[M] {
  priv key : String
  priv origin : Bytes
  priv clock : () -> UInt64
  priv timeout : UInt64
  priv make_meta : () -> M
  priv filter : (Transaction) -> Bool
  priv scopes : Map[UInt64, (Doc, Set[Parent])]
  priv tracked : Set[Bytes]
  priv undo_items : Array[StackItem[M]]
  priv redo_items : Array[StackItem[M]]
  priv mut last_change : UInt64
  priv mut mode : Int32
  priv added_observers : Map[String, (UndoEvent[M], Transaction) -> Unit]
  priv updated_observers : Map[String, (UndoEvent[M], Transaction) -> Unit]
  priv popped_observers : Map[String, (UndoEvent[M], Transaction) -> Unit]
  priv cleared_observers : Map[String, (Bool, Bool) -> Unit]
}

///|
/// A selective CRDT undo manager. The host supplies a millisecond clock.
/// Capture applies only to scoped collections and the configured origins.
pub fn[M : Default] UndoManager::UndoManager(
  clock~ : () -> UInt64,
  capture_timeout_millis~ : UInt64 = 500UL,
  tracked_origins~ : Array[Bytes] = [],
  capture_transaction~ : (Transaction) -> Bool = fn(_) { true },
) -> UndoManager[M] {
  let key = "yrs.undo.\{allocate_identity()}"
  let origin = @utf8.encode(key)
  let tracked = Set::from_array(tracked_origins)
  tracked.add(origin) |> ignore
  {
    key,
    origin,
    clock,
    timeout: capture_timeout_millis,
    make_meta: fn() { Default::default() },
    filter: capture_transaction,
    scopes: Map([]),
    tracked,
    undo_items: [],
    redo_items: [],
    last_change: 0UL,
    mode: 0,
    added_observers: Map([]),
    updated_observers: Map([]),
    popped_observers: Map([]),
    cleared_observers: Map([]),
  }
}

///|
pub fn[M] UndoManager::expand_scope(
  self : UndoManager[M],
  target : Out,
) -> Unit {
  guard target.location() is Some((doc, parent)) else {
    abort("undo scope must be a shared collection")
  }
  if self.scopes.get(doc.identity) is Some((_, scope)) {
    scope.add(parent) |> ignore
  } else {
    self.scopes[doc.identity] = (doc, Set::from_array([parent]))
    doc.observe_after_transaction(self.key, fn(transaction) {
      self.capture(transaction)
    })
  }
}

///|
pub fn[M] UndoManager::docs(self : UndoManager[M]) -> Array[Doc] {
  self.scopes.values().map(fn(entry) { entry.0 }).to_array()
}

///|
pub fn[M] UndoManager::as_origin(self : UndoManager[M]) -> Bytes {
  self.origin
}

///|
pub fn[M] UndoManager::include_origin(
  self : UndoManager[M],
  origin : Bytes,
) -> Unit {
  self.tracked.add(origin) |> ignore
}

///|
pub fn[M] UndoManager::exclude_origin(
  self : UndoManager[M],
  origin : Bytes,
) -> Unit {
  self.tracked.remove(origin) |> ignore
}

///|
pub fn[M] UndoManager::reset(self : UndoManager[M]) -> Unit {
  self.last_change = 0UL
}

///|
pub fn[M] UndoManager::can_undo(self : UndoManager[M]) -> Bool {
  !self.undo_items.is_empty()
}

///|
pub fn[M] UndoManager::can_redo(self : UndoManager[M]) -> Bool {
  !self.redo_items.is_empty()
}

///|
pub fn[M] UndoManager::undo_stack(
  self : UndoManager[M],
) -> ReadOnlyArray[StackItem[M]] {
  ReadOnlyArray::from_array(self.undo_items[:])
}

///|
pub fn[M] UndoManager::redo_stack(
  self : UndoManager[M],
) -> ReadOnlyArray[StackItem[M]] {
  ReadOnlyArray::from_array(self.redo_items[:])
}

///|
pub fn[M] UndoManager::destroy(self : UndoManager[M]) -> Unit {
  for (doc, _) in self.scopes.values() {
    doc.unobserve_after_transaction(self.key) |> ignore
  }
  self.scopes.clear()
  self.clear_all()
}

///|
fn[M] UndoManager::in_scope(
  self : UndoManager[M],
  doc : Doc,
  parent : Parent,
) -> Bool {
  guard self.scopes.get(doc.identity) is Some((_, scope)) else { return false }
  scope.iter().any(fn(ancestor) { doc.event_path(ancestor, parent) is Some(_) })
}

///|
fn[M] UndoManager::capture(
  self : UndoManager[M],
  transaction : Transaction,
) -> Unit {
  if !(self.filter)(transaction) {
    return
  }
  if !(match transaction.origin() {
      Some(origin) => self.tracked.contains(origin)
      None => self.tracked.length() == 1
    }) {
    return
  }
  let doc = transaction.document
  let parents : Set[Parent] = Set([])
  for parent in transaction.sequences {
    parents.add(parent) |> ignore
  }
  for parent in transaction.map_changes.keys() {
    parents.add(parent) |> ignore
  }
  if !parents
    .iter()
    .any(fn(parent) {
      transaction.observable(parent) &&
      self.in_scope(doc, parent) &&
      doc.event_kind(parent) is Some(_)
    }) {
    return
  }
  if self.mode == 1 {
    self.last_change = 0UL
  } else if self.mode == 0 {
    let retained = self.redo_items.filter(fn(item) {
      item.document.identity != doc.identity
    })
    self.redo_items.clear()
    for item in retained {
      self.redo_items.push(item)
    }
  }
  let stack = if self.mode == 1 { self.redo_items } else { self.undo_items }
  let now = (self.clock)()
  let extending = self.mode == 0 &&
    self.last_change > 0UL &&
    now >= self.last_change &&
    now - self.last_change < self.timeout &&
    stack
    .last()
    .map(fn(item) { item.document.identity == doc.identity })
    .unwrap_or(false)
  let entry = if extending {
    let entry = stack.last().unwrap()
    entry.inserted = Snapshot(
      deletions=entry.inserted + transaction.insertions(),
    ).deletions()
    entry.deleted = Snapshot(deletions=entry.deleted + transaction.deletions()).deletions()
    entry
  } else {
    let entry : StackItem[M] = {
      document: doc,
      inserted: transaction.insertions(),
      deleted: transaction.deletions(),
      meta: (self.make_meta)(),
    }
    stack.push(entry)
    entry
  }
  if self.mode == 0 {
    self.last_change = now
  }
  let event : UndoEvent[M] = {
    meta: entry.meta,
    event_kind: if self.mode == 1 {
      Redo
    } else {
      Undo
    },
    source: transaction.origin(),
  }
  let observers = if extending {
    self.updated_observers
  } else {
    self.added_observers
  }
  for (_, callback) in observers.to_array() {
    callback(event, transaction)
  }
  entry.meta = event.meta
}

///|
fn[M] UndoManager::was_deleted(
  self : UndoManager[M],
  doc : Doc,
  id : Id,
) -> Bool {
  self.undo_items.any(fn(item) {
    item.document.identity == doc.identity && contains_range(item.deleted, id)
  }) ||
  self.redo_items.any(fn(item) {
    item.document.identity == doc.identity && contains_range(item.deleted, id)
  })
}

///|
fn[M] UndoManager::redo_item(
  self : UndoManager[M],
  doc : Doc,
  item : Item,
  redo : Set[Id],
  deleting : Array[(UInt64, UInt32, UInt32)],
) -> Item? {
  if item.redone is Some(id) {
    return doc.find(id).map(fn(_) { doc.clean_start(id) })
  }
  guard item.parent is Some(original_parent) else { return None }
  let mut parent = original_parent
  if parent is Nested(id) {
    guard doc.find(id) is Some(owner) else { return None }
    if owner.deleted {
      if owner.redone is None &&
        (
          !redo.contains(owner.id) ||
          self.redo_item(doc, owner, redo, deleting) is None
        ) {
        return None
      }
      guard doc.follow_redone(owner.id) is Some(latest) else { return None }
      parent = Nested(latest)
    }
  }
  let mut left = None
  let mut right = None
  if item.parent_sub is Some(key) {
    if item.right is Some(_) {
      left = Some(item.id)
      while left is Some(id) && doc.items[id].right is Some(next) {
        let neighbor = doc.items[next]
        if neighbor.redone is Some(_) ||
          contains_range(deleting, next) ||
          self.was_deleted(doc, next) {
          guard doc.follow_redone(next) is Some(latest) else { return None }
          left = Some(doc.clean_start(latest).id)
        } else {
          break
        }
      }
      if left is Some(id) && doc.items[id].right is Some(_) {
        return None
      }
    } else {
      left = doc.branch(parent).values.get(key)
    }
  } else {
    left = item.left
    right = Some(item.id)
    fn trace(start : Id?) -> Id? {
      let mut trace = start
      while trace is Some(id) {
        let entry = doc.items[id]
        if entry.parent == Some(parent) {
          return Some(id)
        }
        trace = entry.redone.map(fn(id) { doc.clean_start(id).id })
      }
      None
    }
    while left is Some(id) {
      if trace(left) is Some(found) {
        left = Some(found)
        break
      }
      left = doc.items[id].left
    }
    while right is Some(id) {
      if trace(right) is Some(found) {
        right = Some(found)
        break
      }
      right = doc.items[id].right
    }
  }
  if item.content is (Deleted(_) | Garbage(_)) {
    return None
  }
  let id = doc.insert_content(
    parent,
    item.parent_sub,
    left,
    right,
    item.content,
  )
  item.redone = Some(id)
  doc.find(id)
}

///|
fn[M] UndoManager::pop(self : UndoManager[M], undoing : Bool) -> Bool {
  guard self.mode == 0 else {
    abort("undo manager is already applying a change")
  }
  self.mode = if undoing { 1 } else { 2 }
  let stack = if undoing { self.undo_items } else { self.redo_items }
  let mut changed = false
  while stack.pop() is Some(entry) {
    let doc = entry.document
    let mut committed : Transaction? = None
    try! doc.transact(
      fn(transaction) {
        let to_delete : Array[Item] = []
        for original in doc.materialize_ranges(entry.inserted) {
          if doc.follow_redone(original.id) is Some(latest) {
            let item = doc.clean_start(latest)
            let length = original.content.length()
            if item.content.length() > length {
              doc.split(item, length) |> ignore
            }
            if !item.deleted &&
              item.parent is Some(parent) &&
              self.in_scope(doc, parent) {
              to_delete.push(item)
            }
          }
        }
        let redo : Set[Id] = Set([])
        for item in doc.materialize_ranges(entry.deleted) {
          if item.parent is Some(parent) &&
            self.in_scope(doc, parent) &&
            !contains_range(entry.inserted, item.id) {
            redo.add(item.id) |> ignore
          }
        }
        for id in redo {
          if self.redo_item(doc, doc.items[id], redo, entry.inserted) is Some(_) {
            changed = true
          }
        }
        for i = to_delete.length() - 1; i >= 0; i = i - 1 {
          doc.mark_deleted(to_delete[i])
          changed = true
        }
        committed = Some(transaction)
      },
      origin=self.origin,
    )
    if changed {
      let event : UndoEvent[M] = {
        meta: entry.meta,
        event_kind: if undoing {
          Undo
        } else {
          Redo
        },
        source: Some(self.origin),
      }
      for (_, callback) in self.popped_observers.to_array() {
        callback(event, committed.unwrap())
      }
      break
    }
  }
  self.mode = 0
  changed
}

///|
pub fn[M] UndoManager::undo(self : UndoManager[M]) -> Bool {
  self.pop(true)
}

///|
pub fn[M] UndoManager::redo(self : UndoManager[M]) -> Bool {
  self.pop(false)
}

///|
fn[M] UndoManager::clear(
  self : UndoManager[M],
  undo : Bool,
  redo : Bool,
) -> Unit {
  let u = undo && !self.undo_items.is_empty()
  let r = redo && !self.redo_items.is_empty()
  if undo {
    self.undo_items.clear()
  }
  if redo {
    self.redo_items.clear()
  }
  if u || r {
    for (_, callback) in self.cleared_observers.to_array() {
      callback(u, r)
    }
  }
}

///|
pub fn[M] UndoManager::clear_all(self : UndoManager[M]) -> Unit {
  self.clear(true, true)
}

///|
pub fn[M] UndoManager::clear_undo(self : UndoManager[M]) -> Unit {
  self.clear(true, false)
}

///|
pub fn[M] UndoManager::clear_redo(self : UndoManager[M]) -> Unit {
  self.clear(false, true)
}

///|
pub fn[M] UndoManager::observe_item_added(
  self : UndoManager[M],
  key : String,
  callback : (UndoEvent[M], Transaction) -> Unit,
) -> Unit {
  self.added_observers[key] = callback
}

///|
pub fn[M] UndoManager::unobserve_item_added(
  self : UndoManager[M],
  key : String,
) -> Bool {
  let found = self.added_observers.contains(key)
  self.added_observers.remove(key)
  found
}

///|
pub fn[M] UndoManager::observe_item_updated(
  self : UndoManager[M],
  key : String,
  callback : (UndoEvent[M], Transaction) -> Unit,
) -> Unit {
  self.updated_observers[key] = callback
}

///|
pub fn[M] UndoManager::unobserve_item_updated(
  self : UndoManager[M],
  key : String,
) -> Bool {
  let found = self.updated_observers.contains(key)
  self.updated_observers.remove(key)
  found
}

///|
pub fn[M] UndoManager::observe_item_popped(
  self : UndoManager[M],
  key : String,
  callback : (UndoEvent[M], Transaction) -> Unit,
) -> Unit {
  self.popped_observers[key] = callback
}

///|
pub fn[M] UndoManager::unobserve_item_popped(
  self : UndoManager[M],
  key : String,
) -> Bool {
  let found = self.popped_observers.contains(key)
  self.popped_observers.remove(key)
  found
}

///|
pub fn[M] UndoManager::observe_stack_cleared(
  self : UndoManager[M],
  key : String,
  callback : (Bool, Bool) -> Unit,
) -> Unit {
  self.cleared_observers[key] = callback
}

///|
pub fn[M] UndoManager::unobserve_stack_cleared(
  self : UndoManager[M],
  key : String,
) -> Bool {
  let found = self.cleared_observers.contains(key)
  self.cleared_observers.remove(key)
  found
}

///|
pub fn[M] UndoEvent::set_meta(self : UndoEvent[M], meta : M) -> Unit {
  self.meta = meta
}
