///|
/// Shared types that can be initialized without additional configuration.
/// from_out must accept the value produced by default_prelim.
pub(open) trait DefaultPrelim: SharedRef {
  fn default_prelim() -> In
  fn from_out(Out) -> Self?
}

///|
/// Return an existing value of the requested type, or replace a missing/wrongly
/// typed entry with that type's empty preliminary value.
pub fn[T : DefaultPrelim] MapRef::get_or_init(self : MapRef, key : String) -> T {
  if self.get(key).bind(T::from_out) is Some(value) {
    return value
  }
  guard T::from_out(self.insert_input(key, T::default_prelim())) is Some(value) else {
    abort("DefaultPrelim conversion rejected its own preliminary value")
  }
  value
}

///|
pub impl DefaultPrelim for Text with fn default_prelim() {
  Text([])
}

///|
pub impl DefaultPrelim for Text with fn from_out(value) {
  match value {
    Text(value) => Some(value)
    _ => None
  }
}

///|
pub extend Text with DefaultPrelim::{default_prelim, from_out}

///|
pub impl DefaultPrelim for MapRef with fn default_prelim() {
  Map([])
}

///|
pub impl DefaultPrelim for MapRef with fn from_out(value) {
  match value {
    Map(value) => Some(value)
    _ => None
  }
}

///|
pub extend MapRef with DefaultPrelim::{default_prelim, from_out}

///|
pub impl DefaultPrelim for ArrayRef with fn default_prelim() {
  Array([])
}

///|
pub impl DefaultPrelim for ArrayRef with fn from_out(value) {
  match value {
    Array(value) => Some(value)
    _ => None
  }
}

///|
pub extend ArrayRef with DefaultPrelim::{default_prelim, from_out}

///|
pub impl DefaultPrelim for XmlFragment with fn default_prelim() {
  XmlFragment([])
}

///|
pub impl DefaultPrelim for XmlFragment with fn from_out(value) {
  match value {
    XmlFragment(value) => Some(value)
    _ => None
  }
}

///|
pub extend XmlFragment with DefaultPrelim::{default_prelim, from_out}

///|
pub impl DefaultPrelim for XmlText with fn default_prelim() {
  XmlText([], [])
}

///|
pub impl DefaultPrelim for XmlText with fn from_out(value) {
  match value {
    XmlText(value) => Some(value)
    _ => None
  }
}

///|
pub extend XmlText with DefaultPrelim::{default_prelim, from_out}
