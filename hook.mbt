///|
/// Typed resolution of a live shared collection from a logical identity.
/// Descriptors contain no document reference and can resolve on any replica.
pub trait SharedRef {
  fn from_branch(Doc, BranchId) -> Self?
}

///|
/// Shared collections that can be created at the document root.
pub trait RootRef: SharedRef {
  fn get_or_insert_root(Doc, String) -> Self
}

///|
/// S is a phantom type: only the logical identity is stored, never a live handle.
#warnings("-unused_type_variable")
pub struct Hook[S] {
  priv identity : BranchId
}

///|
#warnings("-unused_type_variable")
pub struct Root[S] {
  name : String
}

///|
#warnings("-unused_type_variable")
pub struct Nested[S] {
  id : Id
}

///|
pub fn[S] Hook::Hook(id : BranchId) -> Hook[S] {
  { identity: id, }
}

///|
#warnings("-unused_trait_bound")
pub fn[S : RootRef] Root::Root(name : String) -> Root[S] {
  { name, }
}

///|
pub fn[S] Nested::Nested(id : Id) -> Nested[S] {
  { id, }
}

///|
pub fn[S] Hook::id(self : Hook[S]) -> BranchId {
  self.identity
}

///|
pub fn[S : SharedRef] Hook::get(self : Hook[S], doc : Doc) -> S? {
  S::from_branch(doc, self.identity)
}

///|
pub fn[S : SharedRef] Root::get(self : Root[S], doc : Doc) -> S? {
  S::from_branch(doc, Root(self.name))
}

///|
pub fn[S : RootRef] Root::get_or_create(self : Root[S], doc : Doc) -> S {
  S::get_or_insert_root(doc, self.name)
}

///|
pub fn[S : SharedRef] Nested::get(self : Nested[S], doc : Doc) -> S? {
  S::from_branch(doc, Nested(self.id))
}

///|
pub fn[S] Root::hook(self : Root[S]) -> Hook[S] {
  Hook(Root(self.name))
}

///|
pub fn[S] Nested::hook(self : Nested[S]) -> Hook[S] {
  Hook(Nested(self.id))
}

///|
pub fn[S] Hook::into_nested(self : Hook[S]) -> Nested[S]? {
  match self.identity {
    Nested(id) => Some(Nested(id))
    Root(_) => None
  }
}

///|
pub fn[S : RootRef] Hook::into_root(self : Hook[S]) -> Root[S]? {
  match self.identity {
    Root(name) => Some(Root(name))
    Nested(_) => None
  }
}

///|
fn BranchId::live_parent(self : BranchId, doc : Doc) -> Parent? {
  match self {
    Root(name) =>
      if doc.roots.contains(Root(name)) {
        Some(Root(name))
      } else {
        None
      }
    Nested(id) =>
      match doc.find(id) {
        Some({ content: Shared(_), deleted: false, .. }) => Some(Nested(id))
        _ => None
      }
  }
}

///|
pub impl SharedRef for Text with fn from_branch(doc, id) {
  id.live_parent(doc).map(fn(name) { ({ doc, name, } : Text) })
}

///|
pub fn Text::hook(self : Text) -> Hook[Text] {
  Hook(self.name.branch_id())
}

///|
pub impl SharedRef for ArrayRef with fn from_branch(doc, id) {
  id.live_parent(doc).map(fn(name) { ({ doc, name, } : ArrayRef) })
}

///|
pub fn ArrayRef::hook(self : ArrayRef) -> Hook[ArrayRef] {
  Hook(self.name.branch_id())
}

///|
pub impl SharedRef for MapRef with fn from_branch(doc, id) {
  id.live_parent(doc).map(fn(name) { ({ doc, name, } : MapRef) })
}

///|
pub fn MapRef::hook(self : MapRef) -> Hook[MapRef] {
  Hook(self.name.branch_id())
}

///|
pub impl SharedRef for XmlFragment with fn from_branch(doc, id) {
  id.live_parent(doc).map(fn(name) { ({ doc, name, } : XmlFragment) })
}

///|
pub fn XmlFragment::hook(self : XmlFragment) -> Hook[XmlFragment] {
  Hook(self.name.branch_id())
}

///|
pub impl SharedRef for XmlText with fn from_branch(doc, id) {
  id.live_parent(doc).map(fn(name) { ({ doc, name, } : XmlText) })
}

///|
pub fn XmlText::hook(self : XmlText) -> Hook[XmlText] {
  Hook(self.name.branch_id())
}

///|
pub impl RootRef for Text with fn get_or_insert_root(doc, name) {
  doc.get_or_insert_text(name)
}

///|
pub impl RootRef for ArrayRef with fn get_or_insert_root(doc, name) {
  doc.get_or_insert_array(name)
}

///|
pub impl RootRef for MapRef with fn get_or_insert_root(doc, name) {
  doc.get_or_insert_map(name)
}

///|
pub impl RootRef for XmlFragment with fn get_or_insert_root(doc, name) {
  doc.get_or_insert_xml_fragment(name)
}

///|
pub impl SharedRef for XmlElement with fn from_branch(doc, id) {
  guard id.live_parent(doc) is Some(name) else { return None }
  guard doc.event_kind(name) is Some(SharedXmlElement(tag)) else { return None }
  Some({ doc, name, tag, })
}

///|
pub fn XmlElement::hook(self : XmlElement) -> Hook[XmlElement] {
  Hook(self.name.branch_id())
}

///|
pub impl SharedRef for WeakRef with fn from_branch(doc, id) {
  guard id.live_parent(doc) is Some(name) else { return None }
  guard doc.event_kind(name) is Some(SharedWeak(link)) else { return None }
  Some({ doc, name, link, })
}

///|
pub fn WeakRef::hook(self : WeakRef) -> Hook[WeakRef] {
  Hook(self.name.branch_id())
}

///|
pub extend Hook with Eq::{equal, not_equal}

///|
pub extend Hook with Debug::{to_repr}

///|
pub extend Root with Eq::{equal, not_equal}

///|
pub extend Root with Debug::{to_repr}

///|
pub extend Nested with Eq::{equal, not_equal}

///|
pub extend Nested with Debug::{to_repr}

///|
pub extend Text with SharedRef::{from_branch}

///|
pub extend ArrayRef with SharedRef::{from_branch}

///|
pub extend MapRef with SharedRef::{from_branch}

///|
pub extend XmlFragment with SharedRef::{from_branch}

///|
pub extend XmlText with SharedRef::{from_branch}

///|
pub extend XmlElement with SharedRef::{from_branch}

///|
pub extend WeakRef with SharedRef::{from_branch}

///|
pub extend Text with RootRef::{get_or_insert_root}

///|
pub extend ArrayRef with RootRef::{get_or_insert_root}

///|
pub extend MapRef with RootRef::{get_or_insert_root}

///|
pub extend XmlFragment with RootRef::{get_or_insert_root}

///|
pub impl[S] Eq for Hook[S] with fn equal(self, other) {
  self.identity == other.identity
}

///|
pub impl[S] Debug for Hook[S] with fn to_repr(self) {
  self.identity.to_repr()
}

///|
pub impl[S] Eq for Root[S] with fn equal(self, other) {
  self.name == other.name
}

///|
pub impl[S] Debug for Root[S] with fn to_repr(self) {
  Debug::to_repr(self.name)
}

///|
pub impl[S] Eq for Nested[S] with fn equal(self, other) {
  self.id == other.id
}

///|
pub impl[S] Debug for Nested[S] with fn to_repr(self) {
  self.id.to_repr()
}

///|
pub impl[S] Hash for Hook[S] with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.identity, hasher)
}

///|
pub extend Hook with Hash::{hash, hash_combine}

///|
pub impl[S] Hash for Root[S] with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.name, hasher)
}

///|
pub extend Root with Hash::{hash, hash_combine}

///|
pub impl[S] Hash for Nested[S] with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.id, hasher)
}

///|
pub extend Nested with Hash::{hash, hash_combine}
