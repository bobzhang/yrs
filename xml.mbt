///|
pub struct XmlFragment {
  priv doc : Doc
  priv name : Parent
}

///|
pub struct XmlElement {
  priv doc : Doc
  priv name : Parent
  priv tag : String
}

///|
pub struct XmlText {
  priv doc : Doc
  priv name : Parent
}

///|
pub(all) enum XmlNode {
  Element(XmlElement)
  Fragment(XmlFragment)
  Text(XmlText)
}

///|
fn Out::as_xml(self : Out) -> XmlNode? {
  match self {
    XmlElement(value) => Some(Element(value))
    XmlFragment(value) => Some(Fragment(value))
    XmlText(value) => Some(Text(value))
    _ => None
  }
}

///|
pub fn Doc::get_or_insert_xml_fragment(
  self : Doc,
  name : String,
) -> XmlFragment {
  let name : Parent = Root(name)
  self.register_kind(name, SharedXmlFragment)
  { doc: self, name, }
}

///|
pub fn XmlElement::tag(self : XmlElement) -> String {
  self.tag
}

///|
pub fn XmlElement::as_fragment(self : XmlElement) -> XmlFragment {
  { doc: self.doc, name: self.name, }
}

///|
pub fn XmlText::as_text(self : XmlText) -> Text {
  { doc: self.doc, name: self.name, }
}

///|
pub fn XmlFragment::children(self : XmlFragment) -> Array[XmlNode] {
  let sequence : ArrayRef = { doc: self.doc, name: self.name, }
  sequence.to_array().filter_map(Out::as_xml)
}

///|
pub fn XmlFragment::length(self : XmlFragment) -> Int32 {
  self.children().length()
}

///|
pub fn XmlFragment::remove_range(
  self : XmlFragment,
  index : Int32,
  length : Int32,
) -> Unit {
  let sequence : ArrayRef = { doc: self.doc, name: self.name, }
  sequence.remove_range(index, length)
}

///|
pub fn XmlFragment::insert_element(
  self : XmlFragment,
  index : Int32,
  tag : String,
) -> XmlElement {
  {
    doc: self.doc,
    name: Nested(self.insert_shared(index, SharedXmlElement(tag))),
    tag,
  }
}

///|
pub fn XmlFragment::insert_text(self : XmlFragment, index : Int32) -> XmlText {
  { doc: self.doc, name: Nested(self.insert_shared(index, SharedXmlText)), }
}

///|
pub fn XmlFragment::insert_fragment(
  self : XmlFragment,
  index : Int32,
) -> XmlFragment {
  { doc: self.doc, name: Nested(self.insert_shared(index, SharedXmlFragment)), }
}

///|
pub fn XmlNode::get_string(self : XmlNode) -> String {
  match self {
    Element(value) => value.get_string()
    Fragment(value) => value.get_string()
    Text(value) => value.get_string()
  }
}

///|
pub fn XmlFragment::get_string(self : XmlFragment) -> String {
  let out = StringBuilder()
  for child in self.children() {
    out.write_string(child.get_string())
  }
  out.to_string()
}

///|
/// Match upstream serialization: content and attribute values are not escaped.
pub fn XmlElement::get_string(self : XmlElement) -> String {
  let out = StringBuilder()
  out.write_string("<" + self.tag)
  for (key, value) in self.attributes() {
    out.write_string(" " + key + "=\"" + value.to_string() + "\"")
  }
  out.write_string(">")
  out.write_string(self.as_fragment().get_string())
  out.write_string("</" + self.tag + ">")
  out.to_string()
}

///|
pub fn XmlText::get_string(self : XmlText) -> String {
  xml_text_chunks(self.as_text().to_delta())
}

///|
fn xml_text_chunks(chunks : Array[TextChunk]) -> String {
  let out = StringBuilder()
  for chunk in chunks {
    for (tag, attrs) in chunk.attributes {
      out.write_string("<" + tag)
      if attrs is Object(fields) {
        let fields = fields.iter().to_array()
        fields.sort_by(fn(a, b) { a.0.compare(b.0) })
        for (key, value) in fields {
          out.write_string(" " + key + "=\"" + value.to_string() + "\"")
        }
      }
      out.write_string(">")
    }
    if chunk.insert is Value(value) {
      out.write_string(value.to_string())
    }
    for (tag, _) in chunk.attributes.iter().to_array().rev() {
      out.write_string("</" + tag + ">")
    }
  }
  out.to_string()
}

///|
pub fn Out::to_string(self : Out) -> String {
  match self {
    Value(value) => value.to_string()
    UndefinedRef(_) => ""
    WeakLink(value) => value.get_string()
    Subdoc(value) => "Doc(id: \{value.client_id()}, guid: \{value.guid()})"
    Text(value) => value.get_string()
    XmlElement(value) => value.get_string()
    XmlFragment(value) => value.get_string()
    XmlText(value) => value.get_string()
    Array(_) | Map(_) => self.to_any().to_string()
  }
}

///|
pub fn Any::to_string(self : Any) -> String {
  match self {
    Undefined => "undefined"
    Null => "null"
    Bool(value) => value.to_string()
    Integer(value) => value.to_string()
    Float(value) => value.to_string()
    String(value) => value
    Array(values) =>
      "[" + values.iter().to_array().map(Any::to_string).join(", ") + "]"
    Object(fields) =>
      "{" +
      fields
      .iter()
      .to_array()
      .map(fn(pair) { pair.0 + ": " + pair.1.to_string() })
      .join(", ") +
      "}"
    Buffer(bytes) => {
      let out = StringBuilder()
      out.write_string("0x")
      let digits = "0123456789abcdef"
      for byte in bytes {
        out.write_char(digits[byte.to_int() / 16].to_int().unsafe_to_char())
        out.write_char(digits[byte.to_int() % 16].to_int().unsafe_to_char())
      }
      out.to_string()
    }
  }
}

///|
fn Doc::xml_parent(self : Doc, name : Parent) -> XmlNode? {
  guard name is Nested(id) &&
    self.items.get(id) is Some(item) &&
    item.parent is Some(parent) else {
    return None
  }
  match parent {
    Root(_) => Some(Fragment({ doc: self, name: parent, }))
    Nested(id) =>
      match self.items.get(id) {
        Some({ content: Shared(kind), .. }) =>
          self.shared_output(id, kind).as_xml()
        _ => None
      }
  }
}

///|
pub fn XmlNode::parent(self : XmlNode) -> XmlNode? {
  match self {
    Element(value) => value.parent()
    Fragment(value) => value.parent()
    Text(value) => value.parent()
  }
}

///|
pub fn XmlElement::as_map(self : XmlElement) -> MapRef {
  { doc: self.doc, name: self.name, }
}

///|
pub fn XmlElement::insert_attribute(
  self : XmlElement,
  key : String,
  value : Any,
) -> Unit {
  self.as_map().insert(key, value)
}

///|
pub fn XmlElement::remove_attribute(self : XmlElement, key : String) -> Unit {
  self.as_map().remove(key)
}

///|
pub fn XmlElement::get_attribute(self : XmlElement, key : String) -> Out? {
  self.as_map().get(key)
}

///|
pub fn XmlElement::attributes(self : XmlElement) -> Array[(String, Out)] {
  self.as_map().entries()
}

///|
pub fn XmlElement::parent(self : XmlElement) -> XmlNode? {
  self.doc.xml_parent(self.name)
}

///|
pub fn XmlFragment::as_map(self : XmlFragment) -> MapRef {
  { doc: self.doc, name: self.name, }
}

///|
pub fn XmlFragment::insert_attribute(
  self : XmlFragment,
  key : String,
  value : Any,
) -> Unit {
  self.as_map().insert(key, value)
}

///|
pub fn XmlFragment::remove_attribute(self : XmlFragment, key : String) -> Unit {
  self.as_map().remove(key)
}

///|
pub fn XmlFragment::get_attribute(self : XmlFragment, key : String) -> Out? {
  self.as_map().get(key)
}

///|
pub fn XmlFragment::attributes(self : XmlFragment) -> Array[(String, Out)] {
  self.as_map().entries()
}

///|
pub fn XmlFragment::parent(self : XmlFragment) -> XmlNode? {
  self.doc.xml_parent(self.name)
}

///|
pub fn XmlText::as_map(self : XmlText) -> MapRef {
  { doc: self.doc, name: self.name, }
}

///|
pub fn XmlText::insert_attribute(
  self : XmlText,
  key : String,
  value : Any,
) -> Unit {
  self.as_map().insert(key, value)
}

///|
pub fn XmlText::remove_attribute(self : XmlText, key : String) -> Unit {
  self.as_map().remove(key)
}

///|
pub fn XmlText::get_attribute(self : XmlText, key : String) -> Out? {
  self.as_map().get(key)
}

///|
pub fn XmlText::attributes(self : XmlText) -> Array[(String, Out)] {
  self.as_map().entries()
}

///|
pub fn XmlText::parent(self : XmlText) -> XmlNode? {
  self.doc.xml_parent(self.name)
}

///|
// Yrs XML uses Branch::index_to_ptr, which stops before deleted entries
// following the selected visible element. Arrays skip these entries instead.
fn XmlFragment::insert_shared(
  self : XmlFragment,
  index : Int32,
  kind : SharedKind,
) -> Id {
  guard index >= 0 && index <= self.length() else {
    abort("XML index out of bounds")
  }
  let mut remaining = index
  let mut left = None
  let mut right = self.doc.branch(self.name).head
  while remaining > 0 && right is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      remaining -= item.content.visible_length()
    }
    left = right
    right = item.right
  }
  self.doc.insert_content(self.name, None, left, right, Shared(kind))
}
