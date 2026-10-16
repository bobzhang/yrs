///|
/// Direct conversion of an output value, preserving the original value on
/// failure. Unlike FromAny deserialization, Rust-compatible integer casts to
/// Int and UInt retain the low 32 bits instead of rejecting narrowing.
pub(open) trait FromOut {
  fn try_from_out(Out) -> Result[Self, Out]
}

///|
pub fn[T : FromOut] Out::cast(self : Out) -> Result[T, Out] {
  T::try_from_out(self)
}

///|
fn[T : FromOut] cast_weak_value(value : Out?) -> Result[T, Out?] {
  match value {
    None => Err(None)
    Some(value) =>
      match value.cast() {
        Ok(value) => Ok(value)
        Err(original) => Err(Some(original))
      }
  }
}

///|
/// Resolve a map link, distinguishing a missing entry from a rejected value.
pub fn[T : FromOut] WeakRef::try_deref(self : WeakRef) -> Result[T, Out?] {
  cast_weak_value(self.try_deref_value())
}

///|
pub fn[T : FromOut] WeakPrelim::try_deref(
  self : WeakPrelim,
  doc : Doc,
) -> Result[T, Out?] {
  cast_weak_value(self.try_deref_value(doc))
}

///|
fn[T : FromAny] cast_primitive(value : Out) -> Result[T, Out] {
  guard value is Value(primitive) else { return Err(value) }
  Ok(from_any(primitive)) catch {
    _ => Err(value)
  }
}

///|
pub impl FromOut for Bool with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for String with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for Bytes with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for Int64 with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for Double with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for Float with fn try_from_out(value) {
  cast_primitive(value)
}

///|
pub impl FromOut for Int32 with fn try_from_out(value) {
  let number : Result[Int64, Out] = cast_primitive(value)
  number.map(Int64::to_int)
}

///|
pub impl FromOut for UInt32 with fn try_from_out(value) {
  let number : Result[Int64, Out] = cast_primitive(value)
  number.map(fn(n) { n.to_int().reinterpret_as_uint() })
}

///|
pub impl FromOut for Text with fn try_from_out(value) {
  match value {
    Text(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for ArrayRef with fn try_from_out(value) {
  match value {
    Array(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for MapRef with fn try_from_out(value) {
  match value {
    Map(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for XmlFragment with fn try_from_out(value) {
  match value {
    XmlFragment(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for XmlText with fn try_from_out(value) {
  match value {
    XmlText(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for XmlElement with fn try_from_out(value) {
  match value {
    XmlElement(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for WeakRef with fn try_from_out(value) {
  match value {
    WeakLink(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for Doc with fn try_from_out(value) {
  match value {
    Subdoc(value) => Ok(value)
    _ => Err(value)
  }
}

///|
pub impl FromOut for XmlNode with fn try_from_out(value) {
  match value {
    XmlElement(value) => Ok(Element(value))
    XmlFragment(value) => Ok(Fragment(value))
    XmlText(value) => Ok(Text(value))
    _ => Err(value)
  }
}

///|
pub extend Text with FromOut::{try_from_out}

///|
pub extend ArrayRef with FromOut::{try_from_out}

///|
pub extend MapRef with FromOut::{try_from_out}

///|
pub extend XmlFragment with FromOut::{try_from_out}

///|
pub extend XmlText with FromOut::{try_from_out}

///|
pub extend XmlElement with FromOut::{try_from_out}

///|
pub extend WeakRef with FromOut::{try_from_out}

///|
pub extend Doc with FromOut::{try_from_out}

///|
pub extend XmlNode with FromOut::{try_from_out}
