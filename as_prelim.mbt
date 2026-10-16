///|
/// Capture a value as detached input that can initialize a new shared value.
/// This is the MoonBit form of Yrs's AsPrelim: the associated preliminary
/// types are represented by In. Shared collections are deep copies; weak links
/// retain their source identities, and subdocuments retain their GUID/options
/// without copying their separately synchronized contents.
pub(open) trait AsPrelim {
  fn to_input(Self) -> In
}

///|
pub impl AsPrelim for Out with fn to_input(self) {
  self.to_input()
}

///|
pub impl AsPrelim for Any with fn to_input(self) {
  Value(self)
}

///|
pub extend Any with AsPrelim::{to_input}

///|
pub impl AsPrelim for ArrayRef with fn to_input(self) {
  Out::Array(self).to_input()
}

///|
pub extend ArrayRef with AsPrelim::{to_input}

///|
pub impl AsPrelim for MapRef with fn to_input(self) {
  Out::Map(self).to_input()
}

///|
pub extend MapRef with AsPrelim::{to_input}

///|
pub impl AsPrelim for Text with fn to_input(self) {
  Out::Text(self).to_input()
}

///|
pub extend Text with AsPrelim::{to_input}

///|
pub impl AsPrelim for XmlElement with fn to_input(self) {
  Out::XmlElement(self).to_input()
}

///|
pub extend XmlElement with AsPrelim::{to_input}

///|
pub impl AsPrelim for XmlFragment with fn to_input(self) {
  Out::XmlFragment(self).to_input()
}

///|
pub extend XmlFragment with AsPrelim::{to_input}

///|
pub impl AsPrelim for XmlText with fn to_input(self) {
  Out::XmlText(self).to_input()
}

///|
pub extend XmlText with AsPrelim::{to_input}

///|
pub impl AsPrelim for WeakRef with fn to_input(self) {
  WeakLink(self.as_prelim())
}

///|
pub extend WeakRef with AsPrelim::{to_input}

///|
pub impl AsPrelim for UndefinedRef with fn to_input(self) {
  self.infer_input()
}

///|
pub extend UndefinedRef with AsPrelim::{to_input}

///|
pub impl AsPrelim for XmlNode with fn to_input(self) {
  match self {
    Element(value) => value.to_input()
    Fragment(value) => value.to_input()
    Text(value) => value.to_input()
  }
}

///|
pub extend XmlNode with AsPrelim::{to_input}
