///|
/// Documents compare by GUID, matching Yrs. Use ptr_eq to check whether two
/// handles refer to the same in-memory document instance.
pub impl Eq for Doc with fn equal(self, other) {
  self.document_guid == other.document_guid
}

///|
pub extend Doc with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for Text with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend Text with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for ArrayRef with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend ArrayRef with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for MapRef with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend MapRef with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for XmlElement with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend XmlElement with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for XmlFragment with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend XmlFragment with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for XmlText with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend XmlText with Eq::{equal, not_equal}

///|
// Shared handles compare logical branch identities, including across replicas.
pub impl Eq for WeakRef with fn equal(self, other) {
  self.name == other.name
}

///|
pub extend WeakRef with Eq::{equal, not_equal}

///|
// Rust's undefined branch pointers use instance identity, not logical identity.
pub impl Eq for UndefinedRef with fn equal(self, other) {
  self.doc.ptr_eq(other.doc) && self.name == other.name
}

///|
pub extend UndefinedRef with Eq::{equal, not_equal}

///|
pub extend Out with Eq::{equal, not_equal}

///|
pub extend XmlNode with Eq::{equal, not_equal}
