///|
pub struct ArrayRef {
  priv doc : Doc
  priv name : String
}

///|
pub fn Doc::get_or_insert_array(self : Doc, name : String) -> ArrayRef {
  self.branch(name) |> ignore
  { doc: self, name, }
}

///|
pub fn ArrayRef::length(self : ArrayRef) -> Int32 {
  let sequence : Text = { doc: self.doc, name: self.name, }
  sequence.length()
}

///|
pub fn ArrayRef::to_array(self : ArrayRef) -> Array[Any] {
  let result = []
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      match item.content {
        Values(values) =>
          for value in values {
            result.push(value)
          }
        Binary(b) => result.push(Buffer(b))
        _ => ()
      }
    }
    cursor = item.right
  }
  result
}

///|
fn Doc::insert_content(
  self : Doc,
  name : String,
  key : String?,
  left : Id?,
  right : Id?,
  content : Content,
) -> Unit {
  let length = content.length()
  if length == 0 {
    return
  }
  let clock = self.state.get(self.client)
  guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
    abort("document clock exhausted")
  }
  let origin = left.map(fn(id) {
    let item = self.items[id]
    (
      {
        client: id.client,
        clock: id.clock + item.content.length().reinterpret_as_uint() - 1U,
      } : Id)
  })
  let raw : RawItem = {
    id: { client: self.client, clock, },
    origin,
    right_origin: right,
    parent: Some(name),
    parent_sub: key,
    content,
  }
  guard self.integrate(raw) else {
    abort("local insert has missing dependency")
  }
  self.settle()
}

///|
pub fn ArrayRef::insert_range(
  self : ArrayRef,
  index : Int32,
  values : Array[Any],
) -> Unit {
  let sequence : Text = { doc: self.doc, name: self.name, }
  let (left, right) = sequence.position(index)
  self.doc.insert_content(
    self.name,
    None,
    left,
    right,
    Values(ReadOnlyArray::from_array(values[:])),
  )
}

///|
pub fn ArrayRef::remove_range(
  self : ArrayRef,
  index : Int32,
  length : Int32,
) -> Unit {
  let sequence : Text = { doc: self.doc, name: self.name, }
  sequence.remove_range(index, length)
}

///|
pub struct MapRef {
  priv doc : Doc
  priv name : String
}

///|
pub fn Doc::get_or_insert_map(self : Doc, name : String) -> MapRef {
  self.branch(name) |> ignore
  { doc: self, name, }
}

///|
pub fn MapRef::insert(self : MapRef, key : String, value : Any) -> Unit {
  self.doc.insert_content(
    self.name,
    Some(key),
    self.doc.branch(self.name).values.get(key),
    None,
    Values([value]),
  )
}

///|
pub fn MapRef::get(self : MapRef, key : String) -> Any? {
  guard self.doc.branch(self.name).values.get(key) is Some(id) else {
    return None
  }
  let item = self.doc.items[id]
  if item.deleted {
    return None
  }
  match item.content {
    Values(values) => Some(values[values.length() - 1])
    Binary(b) => Some(Buffer(b))
    _ => None
  }
}

///|
pub fn MapRef::remove(self : MapRef, key : String) -> Unit {
  if self.doc.branch(self.name).values.get(key) is Some(id) {
    self.doc.mark_deleted(self.doc.items[id])
  }
}

///|
pub fn MapRef::entries(self : MapRef) -> Array[(String, Any)] {
  let entries = []
  for key, _ in self.doc.branch(self.name).values {
    if self.get(key) is Some(value) {
      entries.push((key, value))
    }
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  entries
}
