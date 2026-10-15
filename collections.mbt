///|
pub struct ArrayRef {
  priv doc : Doc
  priv name : Parent
}

///|
pub fn Doc::get_or_insert_array(self : Doc, name : String) -> ArrayRef {
  let name = Root(name)
  self.branch(name) |> ignore
  { doc: self, name, }
}

///|
pub fn ArrayRef::length(self : ArrayRef) -> Int32 {
  let sequence : Text = { doc: self.doc, name: self.name, }
  sequence.length()
}

///|
pub fn ArrayRef::to_array(self : ArrayRef) -> Array[Out] {
  let result = []
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      match item.content {
        Values(values) =>
          for value in values {
            result.push(Value(value))
          }
        Binary(b) => result.push(Value(Buffer(b)))
        Shared(kind) => result.push(self.doc.shared_output(item.id, kind))
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
  name : Parent,
  key : String?,
  left : Id?,
  right : Id?,
  content : Content,
) -> Id {
  let length = content.length()
  guard length > 0 else { abort("empty item") }
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
  raw.id
}

///|
pub fn ArrayRef::insert_range(
  self : ArrayRef,
  index : Int32,
  values : Array[Any],
) -> Unit {
  let sequence : Text = { doc: self.doc, name: self.name, }
  let (left, right) = sequence.position(index)
  if values.is_empty() {
    return
  }
  self.doc.insert_content(
    self.name,
    None,
    left,
    right,
    Values(ReadOnlyArray::from_array(values[:])),
  )
  |> ignore
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
  priv name : Parent
}

///|
pub fn Doc::get_or_insert_map(self : Doc, name : String) -> MapRef {
  let name = Root(name)
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
  |> ignore
}

///|
pub fn MapRef::get(self : MapRef, key : String) -> Out? {
  guard self.doc.branch(self.name).values.get(key) is Some(id) else {
    return None
  }
  let item = self.doc.items[id]
  if item.deleted {
    return None
  }
  match item.content {
    Values(values) => Some(Value(values[values.length() - 1]))
    Binary(b) => Some(Value(Buffer(b)))
    Shared(kind) => Some(self.doc.shared_output(item.id, kind))
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
pub fn MapRef::entries(self : MapRef) -> Array[(String, Out)] {
  let entries = []
  for key, _ in self.doc.branch(self.name).values {
    if self.get(key) is Some(value) {
      entries.push((key, value))
    }
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  entries
}
