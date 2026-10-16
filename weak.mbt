///|
/// A weak reference's two identity boundaries. Before includes a start identity
/// and excludes an end identity; After excludes the start and includes the end.
pub(all) struct LinkSource {
  start : StickyIndex
  end : StickyIndex
} derive(Eq, Debug)

///|
pub fn LinkSource::LinkSource(
  start : StickyIndex,
  end : StickyIndex,
) -> LinkSource {
  { start, end, }
}

///|
pub fn LinkSource::is_single(self : LinkSource) -> Bool {
  match (self.start.scope, self.end.scope) {
    (Relative(a), Relative(b)) => a == b
    _ => false
  }
}

///|
pub struct WeakPrelim {
  priv link : LinkSource
}

///|
pub fn WeakPrelim::WeakPrelim(source : LinkSource) -> WeakPrelim {
  { link: source, }
}

///|
pub fn WeakPrelim::source(self : WeakPrelim) -> LinkSource {
  self.link
}

///|
pub struct WeakRef {
  priv doc : Doc
  priv name : Parent
  priv link : LinkSource
}

///|
pub fn WeakRef::source(self : WeakRef) -> LinkSource {
  self.link
}

///|
pub fn WeakRef::start_id(self : WeakRef) -> Id? {
  self.link.start.id()
}

///|
pub fn WeakRef::end_id(self : WeakRef) -> Id? {
  self.link.end.id()
}

///|
pub fn WeakRef::as_prelim(self : WeakRef) -> WeakPrelim {
  WeakPrelim(self.link)
}

///|
pub fn WeakRef::branch_id(self : WeakRef) -> BranchId {
  self.name.branch_id()
}

///|
pub fn WeakRef::is_deleted(self : WeakRef) -> Bool {
  Out::WeakLink(self).is_deleted()
}

///|
pub(all) suberror QuoteError {
  OutOfBounds
} derive(Debug)

///|
pub(all) enum QuoteBound {
  Included(Int32)
  Excluded(Int32)
  Unbounded
} derive(Eq, Debug)

///|
fn Doc::quote(
  self : Doc,
  parent : Parent,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  fn boundary(
    bound : QuoteBound,
    is_start : Bool,
  ) -> StickyIndex raise QuoteError {
    let (index, assoc) = match bound {
      Unbounded =>
        return StickyIndex(
          scope=parent.index_scope(),
          assoc=if is_start { Before } else { After },
        )
      Included(i) => (i, if is_start { Before } else { After })
      Excluded(i) => (i, if is_start { After } else { Before })
    }
    guard index >= 0 else { raise OutOfBounds }
    let mut remaining = index
    let mut cursor = self.branch(parent).head
    while cursor is Some(id) {
      let item = self.items[id]
      if !item.deleted && item.content.offset_length(self) > 0 {
        if remaining < item.content.offset_length(self) {
          return StickyIndex(
            scope=Relative({
              client: id.client,
              clock: id.clock +
              item.content.block_offset(remaining, self).reinterpret_as_uint(),
            }),
            assoc~,
          )
        }
        remaining -= item.content.offset_length(self)
      }
      cursor = item.right
    }
    raise OutOfBounds
  }
  let from = boundary(start, true)
  let to = boundary(end, false)
  WeakPrelim(LinkSource(from, to))
}

///|
pub fn Text::quote(
  self : Text,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  self.doc.quote(self.name, start, end)
}

///|
pub fn ArrayRef::quote(
  self : ArrayRef,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  self.doc.quote(self.name, start, end)
}

///|
pub fn XmlText::quote(
  self : XmlText,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  self.doc.quote(self.name, start, end)
}

///|
pub fn XmlFragment::quote(
  self : XmlFragment,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  self.doc.quote(self.name, start, end)
}

///|
pub fn XmlElement::quote(
  self : XmlElement,
  start : QuoteBound,
  end : QuoteBound,
) -> WeakPrelim raise QuoteError {
  self.doc.quote(self.name, start, end)
}

///|
pub fn MapRef::link(self : MapRef, key : String) -> WeakPrelim? {
  self.doc.branch(self.name).values
  .get(key)
  .map(fn(id) {
    WeakPrelim(
      LinkSource(
        StickyIndex(scope=Relative(id), assoc=Before),
        StickyIndex(scope=Relative(id), assoc=After),
      ),
    )
  })
}

///|
fn LinkSource::parent(self : LinkSource, doc : Doc) -> Parent? {
  match self.start.scope {
    Relative(id) =>
      match doc.find(id) {
        Some(item) => item.parent
        None => None
      }
    Root(name) => Some(Root(name))
    Nested(id) => Some(Nested(id))
  }
}

///|
pub fn LinkSource::try_deref_value(self : LinkSource, doc : Doc) -> Out? {
  guard self.start.scope is Relative(id) && doc.find(id) is Some(item) else {
    return None
  }
  let mut current = item
  while current.right is Some(id) {
    current = doc.items[id]
  }
  if current.deleted {
    None
  } else {
    current.values(doc).last()
  }
}

///|
// Resolve cuts in sequence order, including tombstones. This keeps a quotation
// anchored when boundary characters are deleted or concurrent inserts arrive.
fn LinkSource::segments(
  self : LinkSource,
  doc : Doc,
) -> Array[(Item, Int32, Int32)] {
  guard self.parent(doc) is Some(parent) else { return [] }
  let items = []
  guard doc.roots.get(parent) is Some(branch) else { return [] }
  let mut cursor = branch.head
  let mut total = 0UL
  let mut begin = if self.start.scope is Relative(_) { None } else { Some(0UL) }
  let mut end = None
  while cursor is Some(id) {
    let item = doc.items[id]
    let length = item.content.length().to_uint64()
    for (boundary, first) in [(self.start, true), (self.end, false)] {
      if boundary.scope is Relative(at) &&
        at.client == id.client &&
        at.clock >= id.clock &&
        (at.clock - id.clock).to_uint64() < length {
        let cut = total +
          (at.clock - id.clock).to_uint64() +
          (if boundary.assoc == After { 1UL } else { 0UL })
        if first {
          begin = Some(cut)
        } else {
          end = Some(cut)
        }
      }
    }
    items.push((item, total))
    total += length
    cursor = item.right
  }
  if !(self.end.scope is Relative(_)) {
    end = Some(total)
  }
  guard begin is Some(begin) && end is Some(end) && begin <= end else {
    return []
  }
  let result = []
  for (item, offset) in items {
    let stop = offset + item.content.length().to_uint64()
    if offset < end && stop > begin {
      result.push(
        (
          item,
          ((if begin > offset { begin } else { offset }) - offset).to_int(),
          ((if end < stop { end } else { stop }) - offset).to_int(),
        ),
      )
    }
  }
  result
}

///|
pub fn LinkSource::unquote(self : LinkSource, doc : Doc) -> Array[Out] {
  if self.start.scope is Relative(id) &&
    doc.find(id) is Some({ parent_sub: Some(_), .. }) {
    return match self.try_deref_value(doc) {
      Some(v) => [v]
      None => []
    }
  }
  let result = []
  for (item, start, end) in self.segments(doc) {
    if !item.deleted {
      match item.content.slice(start, end) {
        Values(values) | LegacyJson(values) =>
          for v in values {
            result.push(Out::Value(v))
          }
        _ => result.append(item.values(doc))
      }
    }
  }
  result
}

///|
pub fn LinkSource::get_string(self : LinkSource, doc : Doc) -> String {
  let result = StringBuilder()
  for (item, start, end) in self.segments(doc) {
    if !item.deleted && item.content is Characters(text) {
      result.write_string(utf16_slice(text, start, end))
    }
  }
  result.to_string()
}

///|
pub fn WeakRef::try_deref_value(self : WeakRef) -> Out? {
  self.link.try_deref_value(self.doc)
}

///|
pub fn WeakRef::unquote(self : WeakRef) -> Array[Out] {
  self.link.unquote(self.doc)
}

///|
pub fn WeakRef::get_string(self : WeakRef) -> String {
  self.link.get_string(self.doc)
}

///|
pub fn WeakPrelim::try_deref_value(self : WeakPrelim, doc : Doc) -> Out? {
  self.link.try_deref_value(doc)
}

///|
pub fn WeakPrelim::unquote(self : WeakPrelim, doc : Doc) -> Array[Out] {
  self.link.unquote(doc)
}

///|
pub fn WeakPrelim::get_string(self : WeakPrelim, doc : Doc) -> String {
  self.link.get_string(doc)
}

///|
pub extend LinkSource with Eq::{equal, not_equal}

///|
pub extend LinkSource with Debug::{to_repr}

///|
pub extend QuoteBound with Eq::{equal, not_equal}

///|
pub extend QuoteBound with Debug::{to_repr}

///|
pub extend QuoteError with Debug::{to_repr}

///|
pub fn LinkSource::to_delta(self : LinkSource, doc : Doc) -> Array[TextChunk] {
  guard self.parent(doc) is Some(parent) else { return [] }
  let selected : Map[Id, (Int32, Int32)] = Map([])
  for (item, start, end) in self.segments(doc) {
    selected[item.id] = (start, end)
  }
  let attrs : Map[String, Any] = Map([])
  let result : Array[TextChunk] = []
  guard doc.roots.get(parent) is Some(branch) else { return [] }
  let mut cursor = branch.head
  let mut merge_text = false
  while cursor is Some(id) {
    let item = doc.items[id]
    if !item.deleted {
      if item.content is Format(key, value) {
        update_attribute(attrs, key, value)
        merge_text = false
      } else if selected.get(id) is Some((start, end)) {
        let attributes = ReadOnlyArray::from_array(sorted_attributes(attrs)[:])
        let output : Out? = match item.content {
          Characters(s) => Some(Value(String(utf16_slice(s, start, end))))
          Embed(value) => Some(Value(value))
          Shared(kind) => Some(doc.shared_output(id, kind))
          _ => None
        }
        if output is Some(insert) {
          if merge_text &&
            insert is Value(String(s)) &&
            result.last() is Some(previous) &&
            previous.insert is Value(String(prefix)) &&
            previous.attributes == attributes {
            result[result.length() - 1] = {
              insert: Value(String(prefix + s)),
              attributes,
            }
          } else {
            result.push({ insert, attributes, })
          }
          merge_text = item.content is Characters(_)
        }
      }
    }
    cursor = item.right
  }
  result
}

///|
pub fn LinkSource::to_xml_string(self : LinkSource, doc : Doc) -> String {
  xml_text_chunks(self.to_delta(doc))
}

///|
pub fn WeakRef::get_xml_string(self : WeakRef) -> String {
  self.link.to_xml_string(self.doc)
}

///|
pub fn WeakRef::to_delta(self : WeakRef) -> Array[TextChunk] {
  self.link.to_delta(self.doc)
}
