///|
/// Detached input values. Shared collections are inserted as independent copies.
pub(all) enum In {
  Value(Any)
  Array(ReadOnlyArray[In])
  Map(ReadOnlyArray[(String, In)])
  Text(ReadOnlyArray[TextDelta])
  XmlElement(String, ReadOnlyArray[(String, In)], ReadOnlyArray[In])
  XmlFragment(ReadOnlyArray[In])
  XmlText(ReadOnlyArray[TextDelta], ReadOnlyArray[(String, In)])
  Subdoc(Doc)
  WeakLink(WeakPrelim)
}

///|
/// Input delta for Text::apply_delta. Retain/delete lengths use the document's
/// offset mode; inserted strings become text and other values become embeds.
pub type TextDelta = DeltaOf[In]

///|
pub fn Out::to_input(self : Out) -> In {
  fn text(value : Text) -> ReadOnlyArray[TextDelta] {
    ReadOnlyArray::from_array(
      value
      .to_delta()
      .map(fn(d) { TextDelta::Inserted(d.insert.to_input(), d.attributes) })[:],
    )
  }
  fn entries(value : MapRef) -> ReadOnlyArray[(String, In)] {
    ReadOnlyArray::from_array(
      value.entries().map(fn(e) { (e.0, e.1.to_input()) })[:],
    )
  }
  fn xml_attributes(value : MapRef) -> ReadOnlyArray[(String, In)] {
    ReadOnlyArray::from_array(
      value.entries().map(fn(e) { (e.0, In::Value(String(e.1.to_string()))) }),
    )
  }
  fn children(value : XmlFragment) -> ReadOnlyArray[In] {
    ReadOnlyArray::from_array(
      value
      .children()
      .map(fn(n) {
        match n {
          Element(e) => Out::XmlElement(e).to_input()
          Fragment(f) => Out::XmlFragment(f).to_input()
          Text(t) => Out::XmlText(t).to_input()
        }
      })[:],
    )
  }
  match self {
    Value(value) => Value(value)
    Array(value) =>
      Array(ReadOnlyArray::from_array(value.to_array().map(Out::to_input)[:]))
    Map(value) => Map(entries(value))
    Text(value) => Text(text(value))
    XmlElement(value) =>
      XmlElement(
        value.tag,
        xml_attributes(value.as_map()),
        children(value.as_fragment()),
      )
    XmlFragment(value) => XmlFragment(children(value))
    XmlText(value) =>
      XmlText(text(value.as_text()), xml_attributes(value.as_map()))
    Subdoc(value) => Subdoc(value.unloaded_copy())
    UndefinedRef(value) => value.infer_input()
    WeakLink(value) => WeakLink(value.as_prelim())
  }
}

///|
fn In::content(self : In, text : Bool) -> Content {
  match self {
    Value(String(value)) if text => Characters(TextContent(value))
    Value(value) =>
      if text {
        Embed(value)
      } else {
        Values(ContentBuffer([value]))
      }
    Array(_) => Shared(SharedArray)
    Map(_) => Shared(SharedMap)
    Text(_) => Shared(SharedText)
    XmlElement(tag, _, _) => Shared(SharedXmlElement(tag))
    XmlFragment(_) => Shared(SharedXmlFragment)
    XmlText(_, _) => Shared(SharedXmlText)
    Subdoc(child) => Subdocument(child)
    WeakLink(value) => Shared(SharedWeak(value.source()))
  }
}

///|
fn In::populate(self : In, doc : Doc, id : Id) -> Out {
  let name : Parent = Nested(id)
  fn entries(values : ReadOnlyArray[(String, In)]) -> Unit {
    let map : MapRef = { doc, name, }
    for (key, value) in values {
      map.insert_input(key, value) |> ignore
    }
  }
  fn children(values : ReadOnlyArray[In]) -> Unit {
    let array : ArrayRef = { doc, name, }
    for index in 0..<values.length() {
      array.insert(index, values[index]) |> ignore
    }
  }
  match self {
    Value(value) => Value(value)
    Subdoc(child) => Subdoc(child)
    WeakLink(value) => WeakLink({ doc, name, link: value.source(), })
    Array(values) => {
      children(values)
      Array({ doc, name, })
    }
    Map(values) => {
      entries(values)
      Map({ doc, name, })
    }
    Text(delta) => {
      let text : Text = { doc, name, }
      text.apply_delta(delta.iter().to_array())
      Text(text)
    }
    XmlElement(tag, attrs, values) => {
      entries(attrs)
      children(values)
      XmlElement({ doc, name, tag, })
    }
    XmlFragment(values) => {
      children(values)
      XmlFragment({ doc, name, })
    }
    XmlText(delta, attrs) => {
      entries(attrs)
      let text : Text = { doc, name, }
      text.apply_delta(delta.iter().to_array())
      XmlText({ doc, name, })
    }
  }
}

///|
pub fn ArrayRef::insert(self : ArrayRef, index : Int32, input : In) -> Out {
  self.doc.with_mutation(fn() {
    if input is Subdoc(child) {
      self.doc.check_subdocument(child)
    }
    let sequence : Text = { doc: self.doc, name: self.name, }
    let (left, right) = sequence.position(index)
    let id = self.doc.insert_content(
      self.name,
      None,
      left,
      right,
      input.content(false),
    )
    input.populate(self.doc, id)
  })
}

///|
pub fn MapRef::insert_input(self : MapRef, key : String, input : In) -> Out {
  self.doc.with_mutation(fn() {
    if input is Subdoc(child) {
      self.doc.check_subdocument(child)
    }
    let id = self.doc.insert_content(
      self.name,
      Some(key),
      self.doc.branch(self.name).values.get(key),
      None,
      input.content(false),
    )
    input.populate(self.doc, id)
  })
}

///|
/// Insert a primitive or shared collection as one embedded text element.
/// Omitted attributes inherit the surrounding formatting; an explicit array
/// replaces it. The returned handle refers to the newly integrated collection.
pub fn Text::insert_embed_input(
  self : Text,
  index : Int32,
  input : In,
  attributes? : Array[(String, Any)],
) -> Out {
  self.doc.with_mutation(fn() {
    if input is Subdoc(child) {
      self.doc.check_subdocument(child)
    }
    let pos = self.rich_position(index)
    let content = match input {
      Value(value) => Embed(value)
      _ => input.content(true)
    }
    let id = match attributes {
      Some(attrs) => pos.insert_formatted(content, attrs)
      None => {
        pos.insert(content)
        pos.left.unwrap()
      }
    }
    input.populate(self.doc, id)
  })
}

///|
pub fn Text::apply_delta(self : Text, delta : Array[TextDelta]) -> Unit {
  self.doc.with_mutation(fn() {
    let pos = self.rich_position(0)
    for op in delta {
      match op {
        Inserted(input, attributes) => {
          if input is Subdoc(child) {
            self.doc.check_subdocument(child)
          }
          let content = input.content(true)
          if content.length() == 0 {
            continue
          }
          let id = pos.insert_formatted(content, attributes.iter().to_array())
          input.populate(self.doc, id) |> ignore
        }
        Deleted(length) => pos.remove(length, cleanup_empty=true)
        Retain(length, attributes) => {
          guard length >= 0 else { abort("negative retain length") }
          pos.format(length, attributes.iter().to_array())
        }
      }
    }
  })
}
