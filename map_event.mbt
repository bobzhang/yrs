///|
pub(all) enum EntryChange {
  Inserted(Out)
  Updated(Out, Out)
  Removed(Out)
}

///|
pub fn EntryChange::to_json(self : EntryChange) -> Json {
  match self {
    Inserted(value) => { "action": "add", "new_value": value.to_json() }
    Updated(old, value) =>
      {
        "action": "update",
        "old_value": old.to_json(),
        "new_value": value.to_json(),
      }
    Removed(value) => { "action": "delete", "old_value": value.to_json() }
  }
}

///|
pub struct MapEvent {
  priv route : ReadOnlyArray[PathSegment]
  priv map : MapRef
  priv changes : ReadOnlyArray[(String, EntryChange)]
}

///|
pub fn MapEvent::target(self : MapEvent) -> MapRef {
  self.map
}

///|
pub fn MapEvent::keys(self : MapEvent) -> Map[String, EntryChange] {
  Map::from_array(self.changes.iter().to_array())
}

///|
pub fn MapEvent::to_json(self : MapEvent) -> Json {
  let result : Map[String, Json] = Map([])
  for (key, change) in self.changes {
    result[key] = change.to_json()
  }
  Json(result)
}

///|
pub fn MapRef::observe(
  self : MapRef,
  key : String,
  callback : (MapEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.map_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Map[String, (MapEvent, Transaction) -> Unit] = Map([])
      self.doc.map_observers[self.name] = observers
      observers
    }
  }
  observers[key] = callback
}

///|
pub fn MapRef::unobserve(self : MapRef, key : String) -> Bool {
  guard self.doc.map_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.contains(key)
  observers.remove(key)
  if observers.is_empty() {
    self.doc.map_observers.remove(self.name)
  }
  found
}

///|
fn Doc::touch_map(self : Doc, parent : Parent, key : String) -> Unit {
  guard self.active_transaction is Some(transaction) else { return }
  let changes = match transaction.map_changes.get(parent) {
    Some(changes) => changes
    None => {
      let changes : Map[String, (Id?, Out?)] = Map([])
      transaction.map_changes[parent] = changes
      changes
    }
  }
  if !changes.contains(key) {
    let map : MapRef = { doc: self, name: parent, }
    let old = map.get(key)
    let id = if old is Some(_) {
      self.branch(parent).values.get(key)
    } else {
      None
    }
    changes[key] = (id, old)
  }
}

///|
fn Transaction::map_events(self : Transaction) -> Array[MapEvent] {
  let events = []
  for parent, changed in self.map_changes {
    if parent is Nested(id) {
      if self.document.find(id) is Some(owner) && owner.deleted {
        continue
      }
      if self.added.any(fn(range) {
          range.0 == id.client && range.1 <= id.clock && id.clock < range.2
        }) {
        continue
      }
    }
    let map : MapRef = { doc: self.document, name: parent, }
    let changes : Array[(String, EntryChange)] = []
    for key, previous in changed {
      let current = map.get(key)
      let current_id = if current is Some(_) {
        self.document.branch(parent).values.get(key)
      } else {
        None
      }
      if current_id == previous.0 {
        continue
      }
      match (previous.1, current) {
        (None, Some(value)) => changes.push((key, Inserted(value)))
        (Some(old), Some(value)) => changes.push((key, Updated(old, value)))
        (Some(old), None) => changes.push((key, Removed(old)))
        (None, None) => ()
      }
    }
    changes.sort_by(fn(a, b) { a.0.compare(b.0) })
    events.push({
      route: [],
      map,
      changes: ReadOnlyArray::from_array(changes[:]),
    })
  }
  events
}
