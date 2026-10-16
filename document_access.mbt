///|
/// Look up an existing root without creating or changing its declared type.
pub fn Doc::get(self : Doc, name : String) -> Out? {
  match self.roots.get(Root(name)) {
    Some({ kind: Some(SharedOpaque(5 | 9)), .. }) => None
    _ => BranchId::Root(name).get(self)
  }
}

///|
pub fn Doc::get_text(self : Doc, name : String) -> Text? {
  if self.roots.contains(Root(name)) {
    Some({ doc: self, name: Root(name), })
  } else {
    None
  }
}

///|
pub fn Doc::get_array(self : Doc, name : String) -> ArrayRef? {
  if self.roots.contains(Root(name)) {
    Some({ doc: self, name: Root(name), })
  } else {
    None
  }
}

///|
pub fn Doc::get_map(self : Doc, name : String) -> MapRef? {
  if self.roots.contains(Root(name)) {
    Some({ doc: self, name: Root(name), })
  } else {
    None
  }
}

///|
pub fn Doc::get_xml_fragment(self : Doc, name : String) -> XmlFragment? {
  if self.roots.contains(Root(name)) {
    Some({ doc: self, name: Root(name), })
  } else {
    None
  }
}

///|
pub fn Doc::ptr_eq(self : Doc, other : Doc) -> Bool {
  self.identity == other.identity
}

///|
pub fn Transaction::has_changes(self : Transaction) -> Bool {
  !self.added.is_empty() || !self.removed.is_empty()
}

///|
pub fn Transaction::insert_set(self : Transaction) -> IdSet {
  IdSet(ranges=self.added)
}

///|
pub fn Transaction::delete_set(self : Transaction) -> IdSet {
  IdSet(ranges=self.removed)
}

///|
pub fn Transaction::cleanups(self : Transaction) -> IdSet {
  IdSet(ranges=self.cleaned.ranges())
}
