///|
/// Named subscriptions. Keys may be strings, byte origins, or another hashable
/// value. Dispatch order is unspecified. Removing a subscription takes effect
/// immediately, including during an active dispatch. New subscriptions and
/// replacements take effect on the next dispatch.
pub struct Observer[K, F] {
  priv callbacks : Map[K, Ref[F?]]
}

///|
pub fn[K : Hash + Eq, F] Observer::Observer() -> Observer[K, F] {
  { callbacks: Map([]), }
}

///|
/// Like Yrs, removed entries are drained after dispatch or before subscribing.
/// This predicate can remain true between unsubscribe and the next drain.
pub fn[K, F] Observer::has_subscribers(self : Observer[K, F]) -> Bool {
  !self.callbacks.is_empty()
}

///|
fn[K, F] Observer::drain_pending(self : Observer[K, F]) -> Unit {
  self.callbacks.retain(fn(_, cell) { cell.val is Some(_) })
}

///|
pub fn[K : Hash + Eq, F] Observer::subscribe(
  self : Observer[K, F],
  key : K,
  callback : F,
) -> Unit {
  self.drain_pending()
  self.callbacks[key] = Ref(Some(callback))
}

///|
/// Returns whether the key exists, including an entry awaiting removal.
pub fn[K : Hash + Eq, F] Observer::unsubscribe(
  self : Observer[K, F],
  key : K,
) -> Bool {
  guard self.callbacks.get(key) is Some(cell) else { return false }
  cell.val = None
  true
}

///|
pub fn[K, F] Observer::trigger(
  self : Observer[K, F],
  each : (F) -> Unit,
) -> Unit {
  let snapshot = self.callbacks.values().to_array()
  for cell in snapshot {
    if cell.val is Some(callback) {
      each(callback)
    }
  }
  self.drain_pending()
}

///|
fn[K, F] Observer::is_empty(self : Observer[K, F]) -> Bool {
  self.callbacks.is_empty()
}

///|
fn[K, F] Observer::clear(self : Observer[K, F]) -> Unit {
  for cell in self.callbacks.values() {
    cell.val = None
  }
  self.callbacks.clear()
}
