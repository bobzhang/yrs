///|
/// A named attribution value attached to CRDT identities.
pub(all) struct ContentAttribute[A] {
  name : String
  value : A
} derive(Eq, Debug)

///|
pub fn[A] ContentAttribute::ContentAttribute(
  name : String,
  value : A,
) -> ContentAttribute[A] {
  { name, value, }
}

///|
/// Attribute equality is independent of order, as in Yrs.
pub struct ContentAttributes[A] {
  priv values : ReadOnlyArray[ContentAttribute[A]]
} derive(Debug)

///|
pub fn[A] ContentAttributes::ContentAttributes(
  values~ : Array[ContentAttribute[A]] = [],
) -> ContentAttributes[A] {
  { values: ReadOnlyArray::from_array(values[:]), }
}

///|
pub fn[A] ContentAttributes::as_array(
  self : ContentAttributes[A],
) -> Array[ContentAttribute[A]] {
  self.values[:].to_owned()
}

///|
pub fn[A] ContentAttributes::length(self : ContentAttributes[A]) -> Int32 {
  self.values.length()
}

///|
pub impl[A : Eq] Eq for ContentAttributes[A] with fn equal(self, other) {
  self.values.length() == other.values.length() &&
  self.values.all(fn(a) { other.values.contains(a) })
}

///|
pub fn[A : Eq] ContentAttributes::merge(
  self : ContentAttributes[A],
  other : ContentAttributes[A],
) -> ContentAttributes[A] {
  let values = self.as_array()
  for attr in other.values {
    if !values.contains(attr) {
      values.push(attr)
    }
  }
  ContentAttributes(values~)
}

///|
/// An attributed half-open clock interval. The client is carried by IdMap.
pub(all) struct AttrRange[A] {
  start : UInt32
  end : UInt32
  attrs : ContentAttributes[A]
} derive(Eq, Debug)

///|
pub fn[A] AttrRange::AttrRange(
  start : UInt32,
  end : UInt32,
  attrs~ : ContentAttributes[A] = ContentAttributes(),
) -> AttrRange[A] {
  guard start <= end else { abort("reversed attribution range") }
  { start, end, attrs, }
}

///|
/// A contiguous interval of identities from one client.
pub(all) struct BlockRange {
  client : UInt64
  clock : UInt32
  length : UInt32
} derive(Eq, Debug)

///|
pub fn BlockRange::BlockRange(
  client : UInt64,
  clock : UInt32,
  length : UInt32,
) -> BlockRange {
  guard length <= 0xffff_ffffU - clock else { abort("clock range overflow") }
  { client, clock, length, }
}

///|
fn BlockRange::end(self : BlockRange) -> UInt32 {
  guard self.length <= 0xffff_ffffU - self.clock else {
    abort("clock range overflow")
  }
  self.clock + self.length
}

///|
pub extend ContentAttribute with Eq::{equal, not_equal}

///|
pub extend ContentAttribute with Debug::{to_repr}

///|
pub extend ContentAttributes with Eq::{equal, not_equal}

///|
pub extend ContentAttributes with Debug::{to_repr}

///|
pub extend AttrRange with Eq::{equal, not_equal}

///|
pub extend AttrRange with Debug::{to_repr}

///|
pub extend BlockRange with Eq::{equal, not_equal}

///|
pub extend BlockRange with Debug::{to_repr}
