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

///|
/// Resolve a root-key path through shared maps and sequences, as Yrs Store does.
/// Primitive values and subdocuments are not shared branches. Retained deleted
/// map values can resolve; sequence indices count only visible values.
pub fn Doc::get_type_from_path(self : Doc, path : Array[PathSegment]) -> Out? {
  guard path.get(0) is Some(Key(root)) else { return None }
  let mut parent : Parent = Root(root)
  guard self.roots.contains(parent) else { return None }
  for i in 1..<path.length() {
    match path[i] {
      Key(key) => {
        guard self.roots.get(parent) is Some(branch) &&
          branch.values.get(key) is Some(id) &&
          self.items.get(id) is Some({ content: Shared(_), .. }) else {
          return None
        }
        parent = Nested(id)
      }
      Index(index) => {
        let sequence : ArrayRef = { doc: self, name: parent, }
        guard sequence.get(index.reinterpret_as_int()).bind(Out::branch_id)
          is Some(Nested(id)) &&
          self.find(id) is Some({ content: Shared(_), .. }) else {
          return None
        }
        parent = Nested(id)
      }
    }
  }
  parent.branch_id().get(self)
}
