///|
/// Stable collection identity; can be resolved on another replica of the document.
pub fn Out::branch_id(self : Out) -> BranchId? {
  self.location().map(fn(location) { location.1.branch_id() })
}

///|
pub fn BranchId::get(self : BranchId, doc : Doc) -> Out? {
  match self {
    Nested(id) =>
      match doc.find(id) {
        Some({ content: Shared(kind), .. }) => Some(doc.shared_output(id, kind))
        _ => None
      }
    Root(name) => {
      let parent : Parent = Root(name)
      guard doc.roots.get(parent) is Some(branch) else { return None }
      Some(
        match branch.kind {
          Some(SharedArray) => Array({ doc, name: parent, })
          Some(SharedMap) => Map({ doc, name: parent, })
          Some(SharedText) => Text({ doc, name: parent, })
          Some(SharedXmlElement(tag)) => XmlElement({ doc, name: parent, tag, })
          Some(SharedXmlFragment) => XmlFragment({ doc, name: parent, })
          Some(SharedXmlText) => XmlText({ doc, name: parent, })
          Some(SharedOpaque(reference)) =>
            UndefinedRef({ doc, name: parent, reference, })
          None => UndefinedRef({ doc, name: parent, reference: 15, })
        },
      )
    }
  }
}

///|
pub fn Out::is_deleted(self : Out) -> Bool {
  match self.location() {
    Some((doc, Nested(id))) =>
      doc.find(id).map(fn(item) { item.deleted }).unwrap_or(true)
    _ => false
  }
}

///|
pub fn Doc::root_refs(self : Doc) -> Array[(String, Out)] {
  let result = []
  for parent in self.roots.keys() {
    if parent is Root(name) {
      result.push((name, parent.branch_id().get(self).unwrap()))
    }
  }
  result
}
