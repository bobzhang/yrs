///|
/// Preserved compatibility branches for upstream XmlHook, SubDoc type-ref and
/// Undefined type-ref values. Real subdocuments use content reference 9.
pub struct UndefinedRef {
  priv doc : Doc
  priv name : Parent
  priv reference : Int32
}

///|
pub fn UndefinedRef::type_ref(self : UndefinedRef) -> Int32 {
  self.reference
}

///|
pub fn UndefinedRef::as_map(self : UndefinedRef) -> MapRef {
  { doc: self.doc, name: self.name, }
}

///|
pub fn UndefinedRef::as_array(self : UndefinedRef) -> ArrayRef {
  { doc: self.doc, name: self.name, }
}

///|
pub fn UndefinedRef::as_text(self : UndefinedRef) -> Text {
  { doc: self.doc, name: self.name, }
}

///|
fn UndefinedRef::infer_input(self : UndefinedRef) -> In {
  let branch = self.doc.branch(self.name)
  let has_map = !branch.values.is_empty()
  let has_list = branch.head is Some(_)
  let mut possible_text = false
  let mut cursor = branch.head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      possible_text = item.content is (Characters(_) | Embed(_) | Format(_, _))
      break
    }
    cursor = item.right
  }
  if possible_text {
    if has_map {
      Out::XmlText({ doc: self.doc, name: self.name, }).to_input()
    } else {
      Out::Text(self.as_text()).to_input()
    }
  } else if has_list && !has_map {
    Out::Array(self.as_array()).to_input()
  } else if has_list && has_map {
    abort("opaque mixed-content branch has no XML element tag")
  } else {
    Out::Map(self.as_map()).to_input()
  }
}
