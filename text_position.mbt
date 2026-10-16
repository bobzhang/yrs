///|
// A local edit leaves a hint at the inserted item's visible offset. Sequence
// mutation invalidates it; compaction moves it to the surviving merged item.
// Formatted text must scan its attributes from the beginning instead.
fn Text::position_start(self : Text, index : Int32) -> (Int32, Id?, Id?) {
  let branch = self.doc.branch(self.name)
  guard !branch.formatted && branch.position_hint is Some((hint, offset)) else {
    return (0, None, branch.head)
  }
  let mut item = hint
  let mut start = offset
  while start > index && item.left is Some(id) {
    item = self.doc.items[id]
    if !item.deleted {
      start -= item.content.offset_length(self.doc)
    }
  }
  // Rich-text removal stops before tombstones at an exact boundary. Plain
  // insertion will subsequently skip them. Preserve both positioning rules.
  if start == index {
    while item.left is Some(id) && self.doc.items[id].deleted {
      item = self.doc.items[id]
    }
  }
  (start, item.left, Some(item.id))
}
