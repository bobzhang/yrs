///|
/// Direct cast with Rust-compatible numeric narrowing. A rejected cast returns
/// the original value; checked application deserialization uses from_any instead.
pub fn[T : FromOut] Any::cast(self : Any) -> Result[T, Any] {
  match Out::Value(self).cast() {
    Ok(value) => Ok(value)
    Err(_) => Err(self)
  }
}

///|
/// Visit array elements with None keys or object entries with Some(key).
/// Primitive values have no iterator. Returned values are owned snapshots.
pub fn Any::try_iter(self : Any) -> Iter[(String?, Any)]? {
  match self {
    Array(values) => Some(values.iter().map(fn(value) { (None, value) }))
    Object(entries) =>
      Some(
        Map::from_array(entries.iter().to_array())
        .iter()
        .map(fn(entry) { (Some(entry.0), entry.1) }),
      )
    _ => None
  }
}

///|
/// Ownership is managed by MoonBit; this has the same behavior as try_iter.
pub fn Any::try_into_iter(self : Any) -> Iter[(String?, Any)]? {
  self.try_iter()
}
