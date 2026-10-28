///|
pub(all) enum PathSegment {
  Key(String)
  Index(UInt32)
} derive(Eq, Debug)

///|
pub fn PathSegment::to_json(self : PathSegment) -> Json {
  match self {
    Key(key) => Json(key)
    Index(index) => Json(index)
  }
}

///|
pub(all) enum Event {
  Text(TextEvent)
  Array(ArrayEvent)
  Map(MapEvent)
  XmlFragment(XmlEvent)
  XmlText(XmlTextEvent)
  Weak(WeakEvent)
}

///|
pub struct XmlEvent {
  priv added_ids : ReadOnlyArray[Id]
  priv deleted_ids : ReadOnlyArray[Id]
  priv node : XmlNode
  priv route : ReadOnlyArray[PathSegment]
  priv changes : ReadOnlyArray[Change]
  priv entries : ReadOnlyArray[(String, EntryChange)]
  priv changed_children : Bool
}

///|
pub struct XmlTextEvent {
  priv text : XmlText
  priv route : ReadOnlyArray[PathSegment]
  priv changes : ReadOnlyArray[Delta]
  priv entries : ReadOnlyArray[(String, EntryChange)]
}

///|
pub fn XmlEvent::target(self : XmlEvent) -> XmlNode {
  self.node
}

///|
pub fn XmlTextEvent::target(self : XmlTextEvent) -> XmlText {
  self.text
}

///|
pub fn XmlEvent::children_changed(self : XmlEvent) -> Bool {
  self.changed_children
}

///|
pub fn XmlEvent::delta(self : XmlEvent) -> ReadOnlyArray[Change] {
  self.changes
}

///|
pub fn XmlTextEvent::delta(self : XmlTextEvent) -> ReadOnlyArray[Delta] {
  self.changes
}

///|
pub fn XmlEvent::keys(self : XmlEvent) -> Map[String, EntryChange] {
  Map::from_array(self.entries[:])
}

///|
pub fn XmlTextEvent::keys(self : XmlTextEvent) -> Map[String, EntryChange] {
  Map::from_array(self.entries[:])
}

///|
fn Doc::register_kind(self : Doc, parent : Parent, kind : SharedKind) -> Unit {
  let branch = self.branch(parent)
  if branch.kind is None {
    branch.kind = Some(kind)
  }
}

///|
fn Doc::event_kind(self : Doc, parent : Parent) -> SharedKind? {
  match parent {
    Root(_) => self.branch(parent).kind
    Nested(id) =>
      match self.find(id) {
        Some({ content: Shared(kind), .. }) => Some(kind)
        _ => None
      }
  }
}

///|
fn Doc::event_path(
  self : Doc,
  ancestor : Parent,
  descendant : Parent,
) -> ReadOnlyArray[PathSegment]? {
  let path : Array[PathSegment] = []
  let mut current = descendant
  while current != ancestor {
    guard current is Nested(id) else { return None }
    guard self.find(id) is Some(item) else { return None }
    guard item.parent is Some(parent) else { return None }
    if item.parent_sub is Some(key) {
      path.push(Key(key))
    } else {
      let mut index = 0U
      let mut cursor = self.branch(parent).head
      while cursor is Some(other) && other != id {
        let child = self.items[other]
        if !child.deleted {
          index += child.content.offset_length(self).reinterpret_as_uint()
        }
        cursor = child.right
      }
      path.push(Index(index))
    }
    current = parent
  }
  for i = 0; i < path.length() / 2; i = i + 1 {
    let other = path.length() - i - 1
    let value = path[i]
    path[i] = path[other]
    path[other] = value
  }
  Some(ReadOnlyArray::from_array(path[:]))
}

///|
fn Doc::notify_collections(self : Doc, transaction : Transaction) -> Unit {
  let parents : Set[Parent] = Set([])
  let maps : Map[Parent, MapEvent] = Map([])
  for parent in transaction.weak_changes {
    parents.add(parent)
  }
  for parent in transaction.sequences {
    parents.add(parent) |> ignore
  }
  for event in transaction.map_events() {
    maps[event.map.name] = event
    parents.add(event.map.name) |> ignore
  }
  // Transaction metadata and undo still need changed ancestors without type
  // observers. Event deltas, however, can scan the whole sequence and nobody
  // consumes them when all collection registries are empty.
  let materialize_events = !self.weak_observers.is_empty() ||
    !self.deep_observers.is_empty() ||
    !self.text_observers.is_empty() ||
    !self.array_observers.is_empty() ||
    !self.map_observers.is_empty() ||
    !self.xml_observers.is_empty() ||
    !self.xml_text_observers.is_empty()
  let events : Array[(Parent, Event)] = []
  for parent in parents {
    if !transaction.observable(parent) {
      continue
    }
    let kind = self.event_kind(parent)
    if kind is None || kind is Some(SharedOpaque(_)) {
      continue
    }
    if !materialize_events {
      self.record_changed_ancestors(transaction, parent)
      continue
    }
    let entries = match maps.get(parent) {
      Some(event) => event.changes
      None => []
    }
    let event : Event = match kind {
      Some(SharedText) =>
        Text({
          text: { doc: self, name: parent, },
          route: [],
          changes: transaction.text_delta(parent),
        })
      Some(SharedArray) => {
        let (inserted_ids, removed_ids) = transaction.sequence_ids(parent)
        Array({
          inserted_ids,
          removed_ids,
          array: { doc: self, name: parent, },
          route: [],
          changes: transaction.array_delta(parent),
        })
      }
      Some(SharedMap) =>
        Map({ map: { doc: self, name: parent, }, route: [], changes: entries, })
      Some(SharedXmlText) =>
        XmlText({
          text: { doc: self, name: parent, },
          route: [],
          changes: transaction.text_delta(parent),
          entries,
        })
      Some(SharedXmlElement(tag)) => {
        let (added_ids, deleted_ids) = transaction.sequence_ids(parent)
        XmlFragment({
          added_ids,
          deleted_ids,
          node: Element({ doc: self, name: parent, tag, }),
          route: [],
          changes: transaction.array_delta(parent),
          entries,
          changed_children: transaction.sequences.contains(parent),
        })
      }
      Some(SharedXmlFragment) => {
        let (added_ids, deleted_ids) = transaction.sequence_ids(parent)
        XmlFragment({
          added_ids,
          deleted_ids,
          node: Fragment({ doc: self, name: parent, }),
          route: [],
          changes: transaction.array_delta(parent),
          entries,
          changed_children: transaction.sequences.contains(parent),
        })
      }
      Some(SharedWeak(link)) =>
        Weak({ weak: { doc: self, name: parent, link, }, route: [], })
      None | Some(SharedOpaque(_)) => continue
    }
    match event {
      Weak(event) =>
        if self.weak_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
      Text(event) =>
        if self.text_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
      Array(event) =>
        if self.array_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
      Map(event) =>
        if self.map_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
      XmlFragment(event) =>
        if self.xml_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
      XmlText(event) =>
        if self.xml_text_observers.get(parent) is Some(observers) {
          observers.trigger(fn(callback) { callback(event, transaction) })
        }
    }
    self.record_changed_ancestors(transaction, parent)
    events.push((parent, event))
  }
  for (ancestor, observers) in self.deep_observers.to_array() {
    let relevant : Array[Event] = []
    for (parent, event) in events {
      if self.event_ancestors(parent).contains(ancestor) {
        relevant.push(
          event.with_path(self.physical_event_path(ancestor, parent)),
        )
      }
    }
    if !relevant.is_empty() {
      relevant.sort_by(fn(a, b) { a.path().length().compare(b.path().length()) })
      let batch = ReadOnlyArray::from_array(relevant[:])
      observers.trigger(fn(callback) { callback(batch, transaction) })
    }
  }
}

///|
pub fn TextEvent::path(self : TextEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn ArrayEvent::path(self : ArrayEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn MapEvent::path(self : MapEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn XmlEvent::path(self : XmlEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn XmlTextEvent::path(self : XmlTextEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn Event::path(self : Event) -> ReadOnlyArray[PathSegment] {
  match self {
    Weak(event) => event.path()
    Text(event) => event.path()
    Array(event) => event.path()
    Map(event) => event.path()
    XmlFragment(event) => event.path()
    XmlText(event) => event.path()
  }
}

///|
pub fn Event::target(self : Event) -> Out {
  match self {
    Weak(event) => WeakLink(event.weak)
    Text(event) => Text(event.text)
    Array(event) => Array(event.array)
    Map(event) => Map(event.map)
    XmlFragment(event) =>
      match event.node {
        Element(n) => XmlElement(n)
        Fragment(n) => XmlFragment(n)
        Text(n) => XmlText(n)
      }
    XmlText(event) => XmlText(event.text)
  }
}

///|
fn Event::with_path(self : Event, path : ReadOnlyArray[PathSegment]) -> Event {
  match self {
    Weak(event) => Weak({ weak: event.weak, route: path, })
    Text(event) =>
      Text({ text: event.text, changes: event.changes, route: path, })
    Array(event) =>
      Array({
        inserted_ids: event.inserted_ids,
        removed_ids: event.removed_ids,
        array: event.array,
        changes: event.changes,
        route: path,
      })
    Map(event) => Map({ map: event.map, changes: event.changes, route: path, })
    XmlFragment(event) =>
      XmlFragment({
        added_ids: event.added_ids,
        deleted_ids: event.deleted_ids,
        node: event.node,
        changes: event.changes,
        route: path,
        entries: event.entries,
        changed_children: event.changed_children,
      })
    XmlText(event) =>
      XmlText({
        text: event.text,
        changes: event.changes,
        route: path,
        entries: event.entries,
      })
  }
}

///|
pub fn Text::observe_deep(
  self : Text,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn Text::unobserve_deep(self : Text, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn ArrayRef::observe_deep(
  self : ArrayRef,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn ArrayRef::unobserve_deep(self : ArrayRef, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn MapRef::observe_deep(
  self : MapRef,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn MapRef::unobserve_deep(self : MapRef, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlFragment::observe_deep(
  self : XmlFragment,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlFragment::unobserve_deep(self : XmlFragment, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlElement::observe_deep(
  self : XmlElement,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlElement::unobserve_deep(self : XmlElement, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlText::observe_deep(
  self : XmlText,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.deep_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[
        String,
        (ReadOnlyArray[Event], Transaction) -> Unit,
      ] = Observer()
      self.doc.deep_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlText::unobserve_deep(self : XmlText, key : String) -> Bool {
  guard self.doc.deep_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.deep_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlFragment::observe(
  self : XmlFragment,
  key : String,
  callback : (XmlEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.xml_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[String, (XmlEvent, Transaction) -> Unit] = Observer()
      self.doc.xml_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlFragment::unobserve(self : XmlFragment, key : String) -> Bool {
  guard self.doc.xml_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.xml_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlElement::observe(
  self : XmlElement,
  key : String,
  callback : (XmlEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.xml_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[String, (XmlEvent, Transaction) -> Unit] = Observer()
      self.doc.xml_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlElement::unobserve(self : XmlElement, key : String) -> Bool {
  guard self.doc.xml_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.xml_observers.remove(self.name)
  }
  found
}

///|
pub fn XmlText::observe(
  self : XmlText,
  key : String,
  callback : (XmlTextEvent, Transaction) -> Unit,
) -> Unit {
  let observers = match self.doc.xml_text_observers.get(self.name) {
    Some(observers) => observers
    None => {
      let observers : Observer[String, (XmlTextEvent, Transaction) -> Unit] = Observer()
      self.doc.xml_text_observers[self.name] = observers
      observers
    }
  }
  observers.subscribe(key, callback)
}

///|
pub fn XmlText::unobserve(self : XmlText, key : String) -> Bool {
  guard self.doc.xml_text_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.xml_text_observers.remove(self.name)
  }
  found
}

///|
pub extend PathSegment with Eq::{equal, not_equal}

///|
pub extend PathSegment with Debug::{to_repr}

///|
/// Inserted child block identities, excluding children also removed in this transaction.
pub fn XmlEvent::added(self : XmlEvent) -> ReadOnlyArray[Id] {
  self.added_ids
}

///|
/// Removed child block identities, excluding transient new children.
pub fn XmlEvent::deleted(self : XmlEvent) -> ReadOnlyArray[Id] {
  self.deleted_ids
}

///|
fn Doc::record_changed_ancestors(
  self : Doc,
  transaction : Transaction,
  parent : Parent,
) -> Unit {
  for location in self.event_ancestors(parent) {
    if location.branch_id().get(self) is Some(value) {
      transaction.changed_parents.push(value)
    }
  }
}
