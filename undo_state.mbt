///|
/// Reconstruct a stack item against a loaded document. Retain deleted content
/// when persisting documents whose undo stacks will be restored later.
pub fn[M] StackItem::StackItem(
  doc : Doc,
  insertions~ : IdSet = IdSet(),
  deletions~ : IdSet = IdSet(),
  meta~ : M,
) -> StackItem[M] {
  {
    document: doc,
    inserted: insertions.ranges(),
    deleted: deletions.ranges(),
    meta,
  }
}

///|
fn[M] StackItem::copy(self : StackItem[M]) -> StackItem[M] {
  {
    document: self.document,
    inserted: self.inserted.copy(),
    deleted: self.deleted.copy(),
    meta: self.meta,
  }
}

///|
pub fn[M] StackItem::merge(
  self : StackItem[M],
  other : StackItem[M],
  merge_meta : (M, M) -> M,
) -> Unit {
  guard self.document.identity == other.document.identity else {
    abort("cannot merge undo items from different documents")
  }
  self.inserted = IdSet(ranges=self.inserted + other.inserted).ranges()
  self.deleted = IdSet(ranges=self.deleted + other.deleted).ranges()
  self.meta = merge_meta(self.meta, other.meta)
}

///|
/// Matches the Rust serde stack-item schema, with caller-defined metadata encoding.
pub fn[M] StackItem::to_json(
  self : StackItem[M],
  encode_meta : (M) -> Json,
) -> Json {
  {
    "doc": Json(self.document.guid()),
    "deletions": IdSet(ranges=self.deleted).to_json(),
    "insertions": IdSet(ranges=self.inserted).to_json(),
    "meta": encode_meta(self.meta),
  }
}

///|
pub fn[M] StackItem::from_json(
  json : Json,
  doc : Doc,
  decode_meta : (Json) -> M raise DecodeError,
) -> StackItem[M] raise DecodeError {
  guard json
    is {
      "doc": String(guid),
      "deletions": deletions,
      "insertions": insertions,
      "meta": meta,
      ..
    } else {
    raise InvalidData("invalid undo stack item")
  }
  guard guid == doc.guid() else {
    raise InvalidData("undo stack document GUID mismatch")
  }
  StackItem(
    doc,
    insertions=IdSet::from_json(insertions),
    deletions=IdSet::from_json(deletions),
    meta=decode_meta(meta),
  )
}

///|
pub fn[M] UndoEvent::changed_parent_types(
  self : UndoEvent[M],
) -> ReadOnlyArray[Out] {
  self.changed
}

///|
pub fn[M] UndoEvent::has_changed(self : UndoEvent[M], target : Out) -> Bool {
  guard target.location() is Some((doc, parent)) else { return false }
  self.changed
  .iter()
  .any(fn(value) {
    match value.location() {
      Some((other, location)) =>
        doc.identity == other.identity && parent == location
      None => false
    }
  })
}

///|
fn[M] UndoManager::remove_document(self : UndoManager[M], doc : Doc) -> Unit {
  self.scopes.remove(doc.identity)
  for stack in [self.undo_items, self.redo_items] {
    let keep = stack.filter(fn(entry) {
      entry.document.identity != doc.identity
    })
    stack.clear()
    for entry in keep {
      stack.push(entry)
    }
  }
}

///|
pub fn[M] StackItem::set_meta(self : StackItem[M], meta : M) -> Unit {
  self.meta = meta
}
