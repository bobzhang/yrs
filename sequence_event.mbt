///|
pub(all) enum Change {
  Added(ReadOnlyArray[Out])
  Removed(Int32)
  Retain(Int32)
}

///|
pub fn Change::to_json(self : Change) -> Json {
  match self {
    Added(values) =>
      { "insert": Json(values.iter().map(Out::to_json).to_array()) }
    Removed(count) => { "delete": Json(count) }
    Retain(count) => { "retain": Json(count) }
  }
}

///|
pub(all) enum Delta {
  Inserted(Out, ReadOnlyArray[(String, Any)])
  Deleted(Int32)
  Retain(Int32, ReadOnlyArray[(String, Any)])
}

///|
pub fn Delta::to_json(self : Delta) -> Json {
  let result : Map[String, Json] = Map([])
  let attributes = match self {
    Inserted(value, attributes) => {
      result["insert"] = value.to_json()
      attributes
    }
    Deleted(length) => {
      result["delete"] = Json(length)
      []
    }
    Retain(length, attributes) => {
      result["retain"] = Json(length)
      attributes
    }
  }
  if !attributes.is_empty() {
    let attrs : Map[String, Json] = Map([])
    for (key, value) in attributes {
      attrs[key] = value.to_json()
    }
    result["attributes"] = Json(attrs)
  }
  Json(result)
}

///|
pub struct TextEvent {
  priv route : ReadOnlyArray[PathSegment]
  priv text : Text
  priv changes : ReadOnlyArray[Delta]
}

///|
pub fn TextEvent::target(self : TextEvent) -> Text {
  self.text
}

///|
pub fn TextEvent::delta(self : TextEvent) -> ReadOnlyArray[Delta] {
  self.changes
}

///|
pub struct ArrayEvent {
  priv inserted_ids : ReadOnlyArray[Id]
  priv removed_ids : ReadOnlyArray[Id]
  priv route : ReadOnlyArray[PathSegment]
  priv array : ArrayRef
  priv changes : ReadOnlyArray[Change]
}

///|
pub fn ArrayEvent::target(self : ArrayEvent) -> ArrayRef {
  self.array
}

///|
pub fn ArrayEvent::delta(self : ArrayEvent) -> ReadOnlyArray[Change] {
  self.changes
}

///|
fn Transaction::has_added(self : Transaction, id : Id) -> Bool {
  self.added.any(fn(r) { r.0 == id.client && r.1 <= id.clock && id.clock < r.2 })
}

///|
fn Transaction::has_deleted(self : Transaction, id : Id) -> Bool {
  self.removed.any(fn(r) {
    r.0 == id.client && r.1 <= id.clock && id.clock < r.2
  })
}

///|
fn Transaction::observable(self : Transaction, parent : Parent) -> Bool {
  match parent {
    Root(_) => true
    Nested(id) =>
      !self.has_added(id) &&
      self.document.find(id).map(fn(item) { !item.deleted }).unwrap_or(false)
  }
}

///|
fn Item::values(self : Item, doc : Doc) -> Array[Out] {
  match self.content {
    Values(values) => values.iter().map(fn(v) { Out::Value(v) }).to_array()
    LegacyJson(values) =>
      values.iter().map(fn(value) { Out::Value(value) }).to_array()
    Binary(bytes) => [Value(Buffer(bytes))]
    Embed(value) => [Value(value)]
    Shared(kind) => [doc.shared_output(self.id, kind)]
    Subdocument(child) => [Subdoc(child)]
    _ => []
  }
}

///|
fn Transaction::array_delta(
  self : Transaction,
  parent : Parent,
) -> ReadOnlyArray[Change] {
  let result : Array[Change] = []
  let mut cursor = self.document.branch(parent).head
  fn push(change : Change) -> Unit {
    match (result.last(), change) {
      (Some(Retain(a)), Retain(b)) =>
        result[result.length() - 1] = Retain(a + b)
      (Some(Removed(a)), Removed(b)) =>
        result[result.length() - 1] = Removed(a + b)
      (Some(Added(a)), Added(b)) => {
        let values = a.iter().to_array()
        for value in b {
          values.push(value)
        }
        result[result.length() - 1] = Added(
          ReadOnlyArray::from_array(values[:]),
        )
      }
      _ => result.push(change)
    }
  }
  while cursor is Some(id) {
    let item = self.document.items[id]
    if item.content.offset_length(self.document) > 0 {
      if item.deleted {
        if !self.has_added(id) && self.has_deleted(id) {
          push(Removed(item.content.offset_length(self.document)))
        }
      } else if self.has_added(id) {
        push(Added(ReadOnlyArray::from_array(item.values(self.document)[:])))
      } else {
        push(Retain(item.content.offset_length(self.document)))
      }
    }
    cursor = item.right
  }
  if result.last() is Some(Retain(_)) {
    result.pop() |> ignore
  }
  ReadOnlyArray::from_array(result[:])
}

///|
fn Transaction::text_delta(
  self : Transaction,
  parent : Parent,
) -> ReadOnlyArray[Delta] {
  // Preserve the upstream delta assembler's formatting transitions. Comparing
  // only before/after attributes loses retained formatting after deleted marks.
  let result : Array[Delta] = []
  let old_attrs : Map[String, Any] = Map([])
  let current_attrs : Map[String, Any] = Map([])
  let attrs : Map[String, Any] = Map([])
  let mut action = 0 // 0 none, 1 insert, 2 retain, 3 delete
  let mut inserted : Out? = None
  let mut text = ""
  let mut count = 0
  fn flush() -> Unit {
    match action {
      1 => {
        result.push(
          Inserted(
            inserted.unwrap_or(Value(String(text))),
            ReadOnlyArray::from_array(sorted_attributes(current_attrs)[:]),
          ),
        )
        inserted = None
        text = ""
      }
      2 =>
        result.push(
          Retain(count, ReadOnlyArray::from_array(sorted_attributes(attrs)[:])),
        )
      3 => result.push(Deleted(count))
      _ => ()
    }
    action = 0
    count = 0
  }
  let mut cursor = self.document.branch(parent).head
  while cursor is Some(id) {
    let item = self.document.items[id]
    let added = self.has_added(id)
    let deleted = self.has_deleted(id)
    match item.content {
      Characters(value) =>
        if added {
          if !deleted {
            if action != 1 {
              flush()
              action = 1
            }
            text += value
          }
        } else if deleted {
          if action != 3 {
            flush()
            action = 3
          }
          count += item.content.offset_length(self.document)
        } else if !item.deleted {
          if action != 2 {
            flush()
            action = 2
          }
          count += item.content.offset_length(self.document)
        }
      Embed(_) | Shared(_) =>
        if added {
          if !deleted {
            flush()
            action = 1
            inserted = item.values(self.document).get(0)
            flush()
          }
        } else if deleted {
          if action != 3 {
            flush()
            action = 3
          }
          count += 1
        } else if !item.deleted {
          if action != 2 {
            flush()
            action = 2
          }
          count += 1
        }
      Format(key, value) => {
        if added {
          if !deleted && current_attrs.get(key) != Some(value) {
            if action == 2 {
              flush()
            }
            if old_attrs.get(key).unwrap_or(Null) == value {
              attrs.remove(key)
            } else {
              attrs[key] = value
            }
          }
        } else if deleted {
          old_attrs[key] = value
          let current = current_attrs.get(key).unwrap_or(Null)
          if current != value {
            if action == 2 {
              flush()
            }
            attrs[key] = current
          }
        } else if !item.deleted {
          old_attrs[key] = value
          if attrs.get(key) is Some(previous) && previous != value {
            if action == 2 {
              flush()
            }
            update_attribute(attrs, key, value)
          }
        }
        if !item.deleted {
          if action == 1 {
            flush()
          }
          update_attribute(current_attrs, key, value)
        }
      }
      _ => ()
    }
    cursor = item.right
  }
  flush()
  while result.last() is Some(Retain(_, attrs)) && attrs.is_empty() {
    result.pop() |> ignore
  }
  ReadOnlyArray::from_array(result[:])
}

///|
pub fn Text::observe(
  self : Text,
  key : String,
  callback : (TextEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.text_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Map[String, (TextEvent, Transaction) -> Unit] = Map([])
      self.doc.text_observers[self.name] = observers
      observers
    }
  }
  observers[key] = callback
}

///|
pub fn Text::unobserve(self : Text, key : String) -> Bool {
  guard self.doc.text_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.contains(key)
  observers.remove(key)
  if observers.is_empty() {
    self.doc.text_observers.remove(self.name)
  }
  found
}

///|
pub fn ArrayRef::observe(
  self : ArrayRef,
  key : String,
  callback : (ArrayEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.array_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Map[String, (ArrayEvent, Transaction) -> Unit] = Map([])
      self.doc.array_observers[self.name] = observers
      observers
    }
  }
  observers[key] = callback
}

///|
pub fn ArrayRef::unobserve(self : ArrayRef, key : String) -> Bool {
  guard self.doc.array_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.contains(key)
  observers.remove(key)
  if observers.is_empty() {
    self.doc.array_observers.remove(self.name)
  }
  found
}

///|
/// IDs of inserted blocks, before post-transaction block compaction.
pub fn ArrayEvent::inserts(self : ArrayEvent) -> ReadOnlyArray[Id] {
  self.inserted_ids
}

///|
pub fn ArrayEvent::removes(self : ArrayEvent) -> ReadOnlyArray[Id] {
  self.removed_ids
}

///|
fn Transaction::sequence_ids(
  self : Transaction,
  parent : Parent,
) -> (ReadOnlyArray[Id], ReadOnlyArray[Id]) {
  let added = []
  let removed = []
  let mut cursor = self.document.branch(parent).head
  while cursor is Some(id) {
    let item = self.document.items[id]
    if item.deleted {
      if self.has_deleted(id) && !self.has_added(id) {
        removed.push(id)
      }
    } else if self.has_added(id) {
      added.push(id)
    }
    cursor = item.right
  }
  (ReadOnlyArray::from_array(added[:]), ReadOnlyArray::from_array(removed[:]))
}
