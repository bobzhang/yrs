///|
pub fn XmlNode::as_out(self : XmlNode) -> Out {
  match self {
    Element(value) => XmlElement(value)
    Fragment(value) => XmlFragment(value)
    Text(value) => XmlText(value)
  }
}

///|
pub fn XmlNode::branch_id(self : XmlNode) -> BranchId {
  self.as_out().branch_id().unwrap()
}

///|
pub fn XmlNode::is_deleted(self : XmlNode) -> Bool {
  self.as_out().is_deleted()
}

///|
fn XmlNode::adjacent(self : XmlNode, forward : Bool) -> XmlNode? {
  let (doc, parent) = self.as_out().location().unwrap()
  guard parent is Nested(id) else { return None }
  let mut cursor = doc.find(id)
  while cursor is Some(item) {
    let next = if forward { item.right } else { item.left }
    guard next is Some(id) else { return None }
    cursor = doc.find(id)
    if cursor is Some(item) && !item.deleted && item.content is Shared(kind) {
      return doc.shared_output(id, kind).as_xml()
    }
  }
  None
}

///|
pub fn XmlNode::next_sibling(self : XmlNode) -> XmlNode? {
  self.adjacent(true)
}

///|
pub fn XmlNode::prev_sibling(self : XmlNode) -> XmlNode? {
  self.adjacent(false)
}

///|
/// Following siblings; backwards=true visits preceding siblings nearest first.
pub fn XmlNode::siblings(
  self : XmlNode,
  backwards~ : Bool = false,
) -> Iter[XmlNode] {
  let result = []
  let mut current = self.adjacent(!backwards)
  while current is Some(node) {
    result.push(node)
    current = node.adjacent(!backwards)
  }
  result.iter()
}

///|
pub fn XmlFragment::get(self : XmlFragment, index : Int32) -> XmlNode? {
  let array : ArrayRef = { doc: self.doc, name: self.name, }
  match array.get(index) {
    Some(value) => value.as_xml()
    None => None
  }
}

///|
pub fn XmlFragment::first_child(self : XmlFragment) -> XmlNode? {
  self.get(0)
}

///|
/// Depth-first traversal, excluding this fragment and deleted subtrees.
pub fn XmlFragment::successors(self : XmlFragment) -> Iter[XmlNode] {
  let result = []
  let pending = self.children().rev()
  while pending.pop() is Some(node) {
    result.push(node)
    let children = match node {
      Element(value) => value.as_fragment().children()
      Fragment(value) => value.children()
      Text(_) => []
    }
    for child in children.rev() {
      pending.push(child)
    }
  }
  result.iter()
}

///|
pub fn XmlFragment::insert(
  self : XmlFragment,
  index : Int32,
  value : In,
) -> XmlNode {
  guard value is (XmlElement(_, _, _) | XmlFragment(_) | XmlText(_, _)) else {
    abort("XML child must be an XML node")
  }
  let array : ArrayRef = { doc: self.doc, name: self.name, }
  array.insert(index, value).as_xml().unwrap()
}

///|
pub fn XmlFragment::push_back(self : XmlFragment, value : In) -> XmlNode {
  self.insert(self.length(), value)
}

///|
pub fn XmlFragment::push_front(self : XmlFragment, value : In) -> XmlNode {
  self.insert(0, value)
}

///|
pub fn XmlFragment::remove(self : XmlFragment, index : Int32) -> Unit {
  self.remove_range(index, 1)
}
