///|
pub struct WeakEvent {
  priv weak : WeakRef
  priv route : ReadOnlyArray[PathSegment]
}

///|
pub fn WeakEvent::target(self : WeakEvent) -> WeakRef {
  self.weak
}

///|
pub fn WeakEvent::path(self : WeakEvent) -> ReadOnlyArray[PathSegment] {
  self.route
}

///|
pub fn WeakRef::observe(
  self : WeakRef,
  key : String,
  callback : (WeakEvent, Transaction) -> Unit,
) -> Unit {
  let observers = self.doc.weak_observers.get_or_init(self.name, fn() {
    Observer()
  })
  observers.subscribe(key, callback)
}

///|
pub fn WeakRef::unobserve(self : WeakRef, key : String) -> Bool {
  guard self.doc.weak_observers.get(self.name) is Some(observers) else {
    return false
  }
  let found = observers.unsubscribe(key)
  if observers.is_empty() {
    self.doc.weak_observers.remove(self.name)
  }
  found
}

///|
pub fn WeakRef::observe_deep(
  self : WeakRef,
  key : String,
  callback : (ReadOnlyArray[Event], Transaction) -> Unit,
) -> Unit {
  let view : Text = { doc: self.doc, name: self.name, }
  view.observe_deep(key, callback)
}

///|
pub fn WeakRef::unobserve_deep(self : WeakRef, key : String) -> Bool {
  let view : Text = { doc: self.doc, name: self.name, }
  view.unobserve_deep(key)
}
