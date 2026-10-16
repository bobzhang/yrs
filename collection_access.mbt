///|
pub fn ArrayRef::get(self : ArrayRef, index : Int32) -> Out? {
  if index < 0 {
    return None
  }
  let mut remaining = index
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted && !(item.content is Format(_, _)) {
      let length = item.content.length()
      if remaining < length {
        return item.values(self.doc).get(remaining)
      }
      remaining -= length
    }
    cursor = item.right
  }
  None
}

///|
pub fn ArrayRef::iter(self : ArrayRef) -> Iter[Out] {
  self.to_array().iter()
}

///|
pub fn ArrayRef::push_back(self : ArrayRef, value : In) -> Out {
  self.insert(self.length(), value)
}

///|
pub fn ArrayRef::push_front(self : ArrayRef, value : In) -> Out {
  self.insert(0, value)
}

///|
pub fn ArrayRef::remove(self : ArrayRef, index : Int32) -> Unit {
  self.remove_range(index, 1)
}

///|
pub fn MapRef::length(self : MapRef) -> Int32 {
  self.doc.branch(self.name).values
  .values()
  .filter(fn(id) { !self.doc.items[id].deleted })
  .count()
}

///|
pub fn MapRef::contains_key(self : MapRef, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
pub fn MapRef::keys(self : MapRef) -> Iter[String] {
  self.entries().iter().map(fn(entry) { entry.0 })
}

///|
pub fn MapRef::values(self : MapRef) -> Iter[Out] {
  self.entries().iter().map(fn(entry) { entry.1 })
}

///|
pub fn MapRef::iter(self : MapRef) -> Iter[(String, Out)] {
  self.entries().iter()
}

///|
/// Delete an entry and return its old handle. Shared contents are deleted too.
pub fn MapRef::remove_entry(self : MapRef, key : String) -> Out? {
  self.doc.with_mutation(fn() {
    let value = self.get(key)
    self.remove(key)
    value
  })
}

///|
pub fn MapRef::clear(self : MapRef) -> Unit {
  self.doc.with_mutation(fn() {
    for key in self.keys() {
      self.remove(key)
    }
  })
}

///|
/// Avoid allocating a new operation when the existing primitive value is equal.
pub fn MapRef::try_update(self : MapRef, key : String, value : Any) -> Bool {
  if self.doc.branch(self.name).values.get(key) is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted &&
      item.content is Values(values) &&
      values[values.length() - 1] == value {
      return false
    }
  }
  self.insert(key, value)
  true
}

///|
pub fn MapRef::get_or_init_array(self : MapRef, key : String) -> ArrayRef {
  self.get_or_init(key)
}

///|
pub fn MapRef::get_or_init_map(self : MapRef, key : String) -> MapRef {
  self.get_or_init(key)
}

///|
pub fn MapRef::get_or_init_text(self : MapRef, key : String) -> Text {
  self.get_or_init(key)
}

///|
pub fn MapRef::get_or_init_xml_fragment(
  self : MapRef,
  key : String,
) -> XmlFragment {
  self.get_or_init(key)
}

///|
pub fn MapRef::get_or_init_xml_text(self : MapRef, key : String) -> XmlText {
  self.get_or_init(key)
}
