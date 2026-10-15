///|
/// A CRDT value is either an immutable lib0 value or a live shared-type handle.
pub(all) enum Out {
  Value(Any)
  Array(ArrayRef)
  Map(MapRef)
  Text(Text)
  XmlElement(XmlElement)
  XmlFragment(XmlFragment)
  XmlText(XmlText)
}

///|
fn Doc::shared_output(self : Doc, id : Id, kind : SharedKind) -> Out {
  let name : Parent = Nested(id)
  match kind {
    SharedArray => Array({ doc: self, name, })
    SharedMap => Map({ doc: self, name, })
    SharedText => Text({ doc: self, name, })
    SharedXmlElement(tag) => XmlElement({ doc: self, name, tag, })
    SharedXmlFragment => XmlFragment({ doc: self, name, })
    SharedXmlText => XmlText({ doc: self, name, })
  }
}

///|
pub fn Out::to_json(self : Out) -> Json {
  match self {
    Value(value) => value.to_json()
    Array(value) => value.to_json()
    Map(value) => value.to_json()
    Text(value) => Json(value.get_string())
    XmlElement(value) => Json(value.get_string())
    XmlFragment(value) => Json(value.get_string())
    XmlText(value) => Json(value.get_string())
  }
}

///|
pub fn ArrayRef::to_json(self : ArrayRef) -> Json {
  Json(self.to_array().map(Out::to_json))
}

///|
pub fn MapRef::to_json(self : MapRef) -> Json {
  let entries : Map[String, Json] = Map([])
  for (key, value) in self.entries() {
    entries[key] = value.to_json()
  }
  Json(entries)
}

///|
fn ArrayRef::insert_shared(
  self : ArrayRef,
  index : Int32,
  kind : SharedKind,
) -> Id {
  let sequence : Text = { doc: self.doc, name: self.name, }
  let (left, right) = sequence.position(index)
  self.doc.insert_content(self.name, None, left, right, Shared(kind))
}

///|
fn MapRef::insert_shared(self : MapRef, key : String, kind : SharedKind) -> Id {
  self.doc.insert_content(
    self.name,
    Some(key),
    self.doc.branch(self.name).values.get(key),
    None,
    Shared(kind),
  )
}

///|
pub fn ArrayRef::insert_text(self : ArrayRef, index : Int32) -> Text {
  { doc: self.doc, name: Nested(self.insert_shared(index, SharedText)), }
}

///|
pub fn ArrayRef::insert_array(self : ArrayRef, index : Int32) -> ArrayRef {
  { doc: self.doc, name: Nested(self.insert_shared(index, SharedArray)), }
}

///|
pub fn ArrayRef::insert_map(self : ArrayRef, index : Int32) -> MapRef {
  { doc: self.doc, name: Nested(self.insert_shared(index, SharedMap)), }
}

///|
pub fn MapRef::insert_text(self : MapRef, key : String) -> Text {
  { doc: self.doc, name: Nested(self.insert_shared(key, SharedText)), }
}

///|
pub fn MapRef::insert_array(self : MapRef, key : String) -> ArrayRef {
  { doc: self.doc, name: Nested(self.insert_shared(key, SharedArray)), }
}

///|
pub fn MapRef::insert_map(self : MapRef, key : String) -> MapRef {
  { doc: self.doc, name: Nested(self.insert_shared(key, SharedMap)), }
}
