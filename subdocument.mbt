///|
pub struct SubdocsEvent {
  priv additions : ReadOnlyArray[Doc]
  priv removals : ReadOnlyArray[Doc]
  priv loads : ReadOnlyArray[Doc]
}

///|
pub fn SubdocsEvent::added(self : SubdocsEvent) -> ReadOnlyArray[Doc] {
  self.additions
}

///|
pub fn SubdocsEvent::removed(self : SubdocsEvent) -> ReadOnlyArray[Doc] {
  self.removals
}

///|
pub fn SubdocsEvent::loaded(self : SubdocsEvent) -> ReadOnlyArray[Doc] {
  self.loads
}

///|
pub fn Doc::guid(self : Doc) -> String {
  self.document_guid
}

///|
pub fn Doc::collection_id(self : Doc) -> String? {
  self.collection
}

///|
pub fn Doc::auto_load(self : Doc) -> Bool {
  self.auto_loading
}

///|
pub fn Doc::should_load(self : Doc) -> Bool {
  self.loading
}

///|
pub fn Doc::parent_doc(self : Doc) -> Doc? {
  self.owner.map(fn(p) { p.0 })
}

///|
pub fn Doc::subdocs(self : Doc) -> Array[Doc] {
  self.children_docs.values().to_array()
}

///|
pub fn Doc::subdoc_guids(self : Doc) -> Set[String] {
  Set::from_array(self.subdocs().map(Doc::guid))
}

///|
fn Doc::unloaded_copy(self : Doc) -> Doc {
  make_doc(
    self.client,
    self.document_guid,
    self.collection,
    self.auto_loading,
    false,
    self.wire_gc,
    self.wire_encoding,
    cleanup_enabled=self.cleanup_enabled,
  )
}

///|
fn Doc::wire_options(self : Doc) -> Any {
  let fields : Array[(String, Any)] = [
    ("gc", Bool(self.wire_gc)),
    ("encoding", Integer(self.wire_encoding.to_int64())),
    ("autoLoad", Bool(self.auto_loading)),
    ("shouldLoad", Bool(self.loading)),
  ]
  if self.collection is Some(collection) {
    fields.push(("collectionId", String(collection)))
  }
  Object(ReadOnlyArray::from_array(fields[:]))
}

///|
fn Reader::subdocument(self : Reader) -> Doc raise DecodeError {
  let guid = self.string()
  let options = self.any()
  let mut gc = true
  let mut encoding = 1
  let mut auto_load = false
  let mut collection = None
  if options is Object(fields) {
    for (key, value) in fields {
      match (key, value) {
        ("gc", Bool(value)) => gc = value
        ("encoding", Integer(1L)) => encoding = 1
        ("encoding", _) => encoding = 0
        ("autoLoad", Bool(value)) => auto_load = value
        ("collectionId", String(value)) => collection = Some(value)
        _ => ()
      }
    }
  }
  // Like Yrs, receiving shouldLoad does not request a load. autoLoad does.
  // The parent assigns its client ID at commit, before providers can edit it.
  make_doc(
    0UL,
    guid,
    collection,
    auto_load,
    auto_load,
    gc,
    encoding,
    cleanup_enabled=false,
  )
}

///|
fn Doc::check_subdocument(self : Doc, child : Doc) -> Unit {
  guard child.document_guid != "" else {
    abort("subdocuments require an explicit globally unique guid")
  }
  guard child.owner is None else {
    abort("document already belongs to a parent")
  }
  let mut ancestor = Some(self)
  while ancestor is Some(doc) {
    guard doc.identity != child.identity else { abort("subdocument cycle") }
    ancestor = doc.parent_doc()
  }
}

///|
pub fn MapRef::insert_doc(self : MapRef, key : String, child : Doc) -> Doc {
  self.doc.check_subdocument(child)
  self.doc.insert_content(
    self.name,
    Some(key),
    self.doc.branch(self.name).values.get(key),
    None,
    Subdocument(child),
  )
  |> ignore
  child
}

///|
pub fn ArrayRef::insert_doc(self : ArrayRef, index : Int32, child : Doc) -> Doc {
  self.doc.check_subdocument(child)
  let sequence : Text = { doc: self.doc, name: self.name, }
  let (left, right) = sequence.position(index)
  self.doc.insert_content(self.name, None, left, right, Subdocument(child))
  |> ignore
  child
}

///|
/// Request loading locally. Providers observe the parent's loaded event and
/// exchange this document's updates separately from the parent's updates.
pub fn Doc::load(self : Doc) -> Unit {
  if self.loading {
    return
  }
  self.loading = true
  if self.owner is Some((parent, _)) {
    parent.with_mutation(fn() {
      parent.active_transaction.unwrap().sub_loaded[self.identity] = self
    })
  }
}

///|
pub fn Doc::observe_subdocs(
  self : Doc,
  key : String,
  callback : (SubdocsEvent, Transaction) -> Unit,
) -> Unit {
  self.subdoc_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_subdocs(self : Doc, key : String) -> Bool {
  self.subdoc_observers.unsubscribe(key)
}

///|
pub fn Doc::observe_destroy(
  self : Doc,
  key : String,
  callback : (Doc) -> Unit,
) -> Unit {
  self.destroy_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_destroy(self : Doc, key : String) -> Bool {
  self.destroy_observers.unsubscribe(key)
}

///|
fn Doc::commit_subdocuments(self : Doc, txn : Transaction) -> Unit {
  if !txn.sub_changed &&
    txn.sub_added.is_empty() &&
    txn.sub_removed.is_empty() &&
    txn.sub_loaded.is_empty() {
    return
  }
  for child in txn.sub_added.values() {
    child.client = self.client
    if child.collection is None {
      child.collection = self.collection
    }
    self.children_docs[child.identity] = child
  }
  for identity in txn.sub_removed.keys() {
    self.children_docs.remove(identity)
  }
  let event : SubdocsEvent = {
    additions: ReadOnlyArray::from_array(txn.sub_added.values().to_array()[:]),
    removals: ReadOnlyArray::from_array(txn.sub_removed.values().to_array()[:]),
    loads: ReadOnlyArray::from_array(txn.sub_loaded.values().to_array()[:]),
  }
  self.subdoc_observers.trigger(fn(callback) { callback(event, txn) })
  // Removal unloads the old handle after observers have inspected it.
  for child in event.removals {
    child.destroy_contents()
  }
}

///|
fn Doc::destroy_contents(self : Doc) -> Unit {
  for child in self.subdocs() {
    child.destroy_contents()
  }
  self.children_docs.clear()
  if self.owner is Some((parent, id)) &&
    parent.items[id].content is Subdocument(current) &&
    current.identity == self.identity {
    let replacement = self.unloaded_copy()
    replacement.owner = Some((parent, id))
    parent.items[id].content = Subdocument(replacement)
  }
  self.owner = None
  self.destroy_observers.trigger(fn(callback) { callback(self) })
  self.destroy_observers.clear()
  self.subdoc_observers.clear()
  for observers in self.weak_observers.values() {
    observers.clear()
  }
  self.weak_observers.clear()
  for observers in self.deep_observers.values() {
    observers.clear()
  }
  self.deep_observers.clear()
  for observers in self.xml_observers.values() {
    observers.clear()
  }
  self.xml_observers.clear()
  for observers in self.xml_text_observers.values() {
    observers.clear()
  }
  self.xml_text_observers.clear()
  for observers in self.array_observers.values() {
    observers.clear()
  }
  self.array_observers.clear()
  for observers in self.text_observers.values() {
    observers.clear()
  }
  self.text_observers.clear()
  for observers in self.map_observers.values() {
    observers.clear()
  }
  self.map_observers.clear()
  self.before_observers.clear()
  self.after_observers.clear()
  self.undo_retention.clear()
  self.cleanup_observers.clear()
  self.update_v1_observers.clear()
  self.update_v2_observers.clear()
}

///|
/// Unload this handle. A live parent reference becomes a fresh, unloaded
/// document with the same GUID; persisted subdocument data is not erased.
pub fn Doc::destroy(self : Doc) -> Unit {
  if self.owner is Some((parent, id)) {
    parent.with_mutation(fn() {
      let item = parent.items[id]
      let replacement = self.unloaded_copy()
      replacement.owner = Some((parent, id))
      item.content = Subdocument(replacement)
      let txn = parent.active_transaction.unwrap()
      // Report replacement as removal plus addition while retaining identity
      // separation for documents sharing a GUID.
      txn.sub_removed[self.identity] = self
      if !item.deleted {
        txn.sub_added[replacement.identity] = replacement
      }
    })
  } else {
    self.destroy_contents()
  }
}

///|
/// Identity of this subdocument's owning item in its parent document.
pub fn Doc::branch_id(self : Doc) -> BranchId? {
  self.owner.map(fn(p) { BranchId::Nested(p.1) })
}
