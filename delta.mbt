///|
/// A text edit with an application-selected insertion value. Delta and
/// TextDelta specialize this type to observed Out values and detached In values.
pub(all) enum DeltaOf[T] {
  Inserted(T, ReadOnlyArray[(String, Any)])
  Deleted(Int32)
  Retain(Int32, ReadOnlyArray[(String, Any)])
}

///|
/// Transform an inserted value once, preserving lengths and formatting.
/// Retain and delete operations do not invoke the callback.
pub fn[A, B] DeltaOf::map(
  self : DeltaOf[A],
  f : (A) -> B raise?,
) -> DeltaOf[B] raise? {
  match self {
    Inserted(value, attributes) => Inserted(f(value), attributes)
    Deleted(length) => Deleted(length)
    Retain(length, attributes) => Retain(length, attributes)
  }
}

///|
/// Copy inserted shared values into detached preliminary values for apply_delta.
pub fn Delta::to_input(self : Delta) -> TextDelta {
  self.map(Out::to_input)
}

///|
pub fn TextDelta::insert(value : In) -> TextDelta {
  Inserted(value, [])
}

///|
pub fn TextDelta::insert_with(
  value : In,
  attributes : ReadOnlyArray[(String, Any)],
) -> TextDelta {
  Inserted(value, attributes)
}

///|
pub fn TextDelta::retain(length : Int32) -> TextDelta {
  Retain(length, [])
}

///|
pub fn TextDelta::delete(length : Int32) -> TextDelta {
  Deleted(length)
}
