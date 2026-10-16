///|
priv struct RichPosition {
  doc : Doc
  parent : Parent
  mut left : Id?
  mut right : Id?
  attrs : Map[String, Any]
}

///|
fn update_attribute(
  attrs : Map[String, Any],
  key : String,
  value : Any,
) -> Unit {
  if value is Null {
    attrs.remove(key)
  } else {
    attrs[key] = value
  }
}

///|
fn Text::rich_position(self : Text, index : Int32) -> RichPosition {
  guard index >= 0 else { abort("negative text index") }
  let attrs : Map[String, Any] = Map([])
  let (start, previous, next) = self.position_start(index)
  let mut left = previous
  let mut right = next
  let mut remaining = index - start
  // Unlike plain insertion, rich-text positioning stops before tombstones
  // once the requested visible offset has been reached (Yrs find_position).
  while remaining > 0 && right is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      match item.content {
        Format(key, value) => update_attribute(attrs, key, value)
        _ => {
          let length = item.content.offset_length(self.doc)
          if remaining < length {
            let tail = self.doc.split(
              item,
              item.content.block_offset(remaining, self.doc),
            )
            left = Some(id)
            right = Some(tail.id)
            remaining = 0
            break
          }
          remaining -= length
        }
      }
    }
    left = right
    right = item.right
  }
  guard remaining == 0 else { abort("text index out of bounds") }
  { doc: self.doc, parent: self.name, left, right, attrs, }
}

///|
fn RichPosition::forward(self : RichPosition) -> Unit {
  if self.right is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted && item.content is Format(key, value) {
      update_attribute(self.attrs, key, value)
    }
    self.left = Some(id)
    self.right = item.right
  }
}

///|
fn RichPosition::insert(self : RichPosition, content : Content) -> Unit {
  let id = self.doc.insert_content(
    self.parent,
    None,
    self.left,
    self.right,
    content,
  )
  self.right = Some(id)
  self.forward()
}

///|
fn RichPosition::minimize(
  self : RichPosition,
  attrs : Map[String, Any],
) -> Unit {
  while self.right is Some(id) {
    let item = self.doc.items[id]
    if item.deleted ||
      (item.content is Format(key, value) && attrs.get(key) == Some(value)) {
      self.forward()
    } else {
      break
    }
  }
}

///|
fn sorted_attributes(attrs : Map[String, Any]) -> Array[(String, Any)] {
  let entries = attrs.to_array()
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  entries
}

///|
fn RichPosition::insert_attributes(
  self : RichPosition,
  attrs : Map[String, Any],
) -> Map[String, Any] {
  let negated : Map[String, Any] = Map([])
  for (key, value) in sorted_attributes(attrs) {
    let current = self.attrs.get(key).unwrap_or(Null)
    if current != value {
      negated[key] = current
      self.insert(Format(key, value))
    }
  }
  negated
}

///|
fn RichPosition::restore(self : RichPosition, attrs : Map[String, Any]) -> Unit {
  while self.right is Some(id) {
    let item = self.doc.items[id]
    if item.deleted {
      self.forward()
    } else if item.content is Format(key, value) &&
      attrs.get(key) == Some(value) {
      attrs.remove(key)
      self.forward()
    } else {
      break
    }
  }
  for (key, value) in sorted_attributes(attrs) {
    self.insert(Format(key, value))
  }
}

///|
fn Text::insert_formatted(
  self : Text,
  index : Int32,
  content : Content,
  attributes : Array[(String, Any)],
) -> Unit {
  self.doc.with_mutation(fn() {
    if content.length() == 0 {
      return
    }
    let pos = self.rich_position(index)
    pos.insert_formatted(content, attributes) |> ignore
  })
}

///|
pub fn Text::insert_with_attributes(
  self : Text,
  index : Int32,
  value : String,
  attributes : Array[(String, Any)],
) -> Unit {
  self.insert_formatted(index, Characters(value), attributes)
}

///|
pub fn Text::insert_embed(
  self : Text,
  index : Int32,
  value : Any,
  attributes~ : Array[(String, Any)] = [],
) -> Unit {
  self.insert_formatted(index, Embed(value), attributes)
}

///|
pub fn Text::format(
  self : Text,
  index : Int32,
  length : Int32,
  attributes : Array[(String, Any)],
) -> Unit {
  self.doc.with_mutation(fn() {
    guard length >= 0 else { abort("negative format length") }
    let pos = self.rich_position(index)
    pos.format(length, attributes)
  })
}

///|
fn Text::clean_format_gap(
  self : Text,
  from : Id?,
  until : Id?,
  before : Map[String, Any],
  after : Map[String, Any],
) -> Unit {
  let mut end = until
  while end is Some(id) {
    let item = self.doc.items[id]
    if item.content is Characters(_) || item.content is Embed(_) {
      break
    }
    if !item.deleted && item.content is Format(key, value) {
      update_attribute(after, key, value)
    }
    end = item.right
  }
  let mut cursor = from
  while cursor != end && cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted && item.content is Format(key, value) {
      if after.get(key).unwrap_or(Null) != value ||
        before.get(key).unwrap_or(Null) == value {
        self.doc.mark_deleted(item)
      }
    }
    cursor = item.right
  }
}

///|
fn Doc::cleanup_formatting(self : Doc) -> Unit {
  let full : Set[Parent] = Set([])
  for item in self.inserted_items {
    if !item.deleted &&
      item.content is Format(_, _) &&
      item.parent is Some(parent) {
      full.add(parent)
    }
  }
  let deleted = self.deleted_items[:].to_owned()
  deleted.sort_by(fn(a, b) { a.id.compare(b.id) })
  let contextless = []
  for item in deleted {
    if item.parent is Some(parent) &&
      self.branch(parent).formatted &&
      !full.contains(parent) {
      if item.content is Format(_, _) {
        full.add(parent)
      } else {
        contextless.push(item)
      }
    }
  }
  for item in contextless {
    self.cleanup_contextless(item)
  }
  for parent in full {
    let mut start = self.branch(parent).head
    let mut cursor = start
    let mut previous : Map[String, Any] = Map([])
    let current : Map[String, Any] = Map([])
    while cursor is Some(id) {
      let item = self.items[id]
      if !item.deleted {
        if item.content is Format(key, value) {
          update_attribute(current, key, value)
        } else {
          self.cleanup_remote_gap(start, cursor, previous, current)
          previous = Map::from_array(current.to_array())
          start = cursor
        }
      }
      cursor = item.right
    }
  }
}

///|
fn Doc::cleanup_contextless(self : Doc, from : Item) -> Unit {
  let mut item = from
  while item.right is Some(id) {
    let right = self.items[id]
    if !right.deleted && right.content.visible_length() > 0 {
      break
    }
    item = right
  }
  let seen : Set[String] = Set([])
  let mut cursor = Some(item.id)
  while cursor is Some(id) {
    let item = self.items[id]
    if !item.deleted && item.content.visible_length() > 0 {
      break
    }
    if !item.deleted && item.content is Format(key, _) {
      if seen.contains(key) {
        self.mark_deleted(item)
      } else {
        seen.add(key)
      }
    }
    cursor = item.left
  }
}

///|
fn Doc::cleanup_remote_gap(
  self : Doc,
  from : Id?,
  current_item : Id?,
  previous : Map[String, Any],
  current : Map[String, Any],
) -> Unit {
  let mut end = from
  let last : Map[String, Id] = Map([])
  while end is Some(id) {
    let item = self.items[id]
    if !item.deleted && item.content.visible_length() > 0 {
      break
    }
    if !item.deleted && item.content is Format(key, _) {
      last[key] = id
    }
    end = item.right
  }
  let mut reached_current = false
  let mut cursor = from
  while cursor != end && cursor is Some(id) {
    if cursor == current_item {
      reached_current = true
    }
    let item = self.items[id]
    if !item.deleted && item.content is Format(key, value) {
      let old = previous.get(key).unwrap_or(Null)
      if last.get(key) != Some(id) || old == value {
        self.mark_deleted(item)
        if !reached_current &&
          current.get(key).unwrap_or(Null) == value &&
          old != value {
          if value is Null {
            current.remove(key)
          } else {
            current[key] = old
          }
        }
      }
      if !reached_current && !item.deleted {
        update_attribute(current, key, value)
      }
    }
    cursor = item.right
  }
}

///|
pub(all) struct TextChunk {
  insert : Out
  attributes : ReadOnlyArray[(String, Any)]
}

///|
pub fn TextChunk::to_json(self : TextChunk) -> Json {
  let fields : Map[String, Json] = { "insert": self.insert.to_json() }
  if !self.attributes.is_empty() {
    let attrs : Map[String, Json] = Map([])
    for (key, value) in self.attributes {
      attrs[key] = value.to_json()
    }
    fields["attributes"] = Json(attrs)
  }
  Json(fields)
}

///|
pub fn Text::to_delta(self : Text) -> Array[TextChunk] {
  let result : Array[TextChunk] = []
  let attrs : Map[String, Any] = Map([])
  let mut merge_text = false
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    if !item.deleted {
      if item.content is Format(key, value) {
        merge_text = false
        update_attribute(attrs, key, value)
      } else {
        let attributes = ReadOnlyArray::from_array(sorted_attributes(attrs)[:])
        let output : Out? = match item.content {
          Characters(s) => Some(Value(String(s)))
          Embed(value) => Some(Value(value))
          Shared(kind) => Some(self.doc.shared_output(item.id, kind))
          _ => None
        }
        if output is Some(insert) {
          if merge_text &&
            item.content is Characters(_) &&
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
fn RichPosition::insert_formatted(
  pos : RichPosition,
  content : Content,
  attributes : Array[(String, Any)],
) -> Id {
  let attrs = Map::from_array(attributes)
  for key, _ in pos.attrs {
    if !attrs.contains(key) {
      attrs[key] = Null
    }
  }
  pos.minimize(attrs)
  let restore = pos.insert_attributes(attrs)
  pos.insert(content)
  let id = pos.left.unwrap()
  pos.restore(restore)
  id
}

///|
fn RichPosition::format(
  pos : RichPosition,
  length : Int32,
  attributes : Array[(String, Any)],
) -> Unit {
  let attrs = Map::from_array(attributes)
  pos.minimize(attrs)
  let restore = pos.insert_attributes(attrs)
  let mut remaining = length
  while pos.right is Some(id) {
    let item = pos.doc.items[id]
    if !(remaining > 0 ||
      (!restore.is_empty() && (item.deleted || item.content is Format(_, _)))) {
      break
    }
    if !item.deleted {
      match item.content {
        Format(key, value) =>
          if attrs.get(key) is Some(desired) {
            if desired == value {
              restore.remove(key)
            } else {
              restore[key] = value
            }
            pos.doc.mark_deleted(item)
          }
        _ => {
          let len = item.content.offset_length(pos.doc)
          if remaining < len {
            let tail = pos.doc.split(
              item,
              item.content.block_offset(remaining, pos.doc),
            )
            pos.left = Some(item.id)
            pos.right = Some(tail.id)
            break
          }
          remaining -= len
        }
      }
    }
    pos.forward()
  }
  pos.restore(restore)
}

///|
fn RichPosition::remove(
  pos : RichPosition,
  length : Int32,
  cleanup_empty~ : Bool = false,
) -> Unit {
  guard length >= 0 else { abort("negative deletion length") }
  let text : Text = { doc: pos.doc, name: pos.parent, }
  let start = pos.right
  let start_attrs = Map::from_array(pos.attrs.to_array())
  let mut remaining = length
  while remaining > 0 && pos.right is Some(id) {
    let item = pos.doc.items[id]
    if !item.deleted && item.content.offset_length(pos.doc) > 0 {
      if remaining < item.content.offset_length(pos.doc) {
        pos.doc.split(item, item.content.block_offset(remaining, pos.doc))
        |> ignore
      }
      remaining -= item.content.offset_length(pos.doc)
      pos.doc.mark_deleted(item)
    }
    pos.forward()
  }
  if cleanup_empty || !start_attrs.is_empty() {
    text.clean_format_gap(start, pos.right, start_attrs, pos.attrs)
  }
  guard remaining == 0 else { abort("text deletion out of bounds") }
}
