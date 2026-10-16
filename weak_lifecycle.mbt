///|
fn Doc::materialize_weak(self : Doc, link : Id, source : LinkSource) -> Unit {
  for boundary in [source.start, source.end] {
    if boundary.id() is Some(id) && self.find(id) is None {
      self.pending_weak.add(link)
      return
    }
  }
  if self.pending_weak.contains(link) {
    self.pending_weak.remove(link)
    if self.active_transaction is Some(tx) {
      tx.weak_changes.add(Nested(link))
    }
  }
  if source.start.scope is Relative(id) &&
    self.find(id) is Some(item) &&
    item.parent_sub is Some(_) {
    let mut last = item
    while last.right is Some(id) {
      last = self.items[id]
    }
    last.links.add(link)
    last.linked = true
    return
  }
  if source.parent(self) is Some(parent) {
    self.branch(parent).weak_quotes.add(link)
  }
  let segments = source.segments(self)
  for (original, start, end) in segments {
    if start >= end {
      continue
    }
    let item = self.clean_start({
      client: original.id.client,
      clock: original.id.clock + start.reinterpret_as_uint(),
    })
    if end - start < item.content.length() {
      self.split(item, end - start) |> ignore
    }
    item.linked = true
    item.links.add(link)
  }
}

///|
fn Doc::unlink_weak(self : Doc, link : Id) -> Unit {
  self.pending_weak.remove(link)
  for branch in self.roots.values() {
    branch.weak_quotes.remove(link)
  }
  for item in self.items.values() {
    if item.links.contains(link) {
      item.links.remove(link)
      if item.links.is_empty() {
        item.linked = false
      }
    }
  }
}

///|
fn Doc::join_weak_links(self : Doc, item : Item) -> Unit {
  self.join_weak_neighbor_links(item)
  guard item.parent is Some(parent) else { return }
  // Neighbor edges disappear when the last quoted item is deleted, and there
  // is no neighbor at an unbounded endpoint. Retain quotation subscriptions at
  // the branch so these cases still notify and propagate deep changes.
  for link in self.branch(parent).weak_quotes {
    if self.find(link)
      is Some({ content: Shared(SharedWeak(source)), deleted: false, .. }) {
      for (quoted, start, end) in source.segments(self) {
        if quoted.id == item.id && start < end {
          item.linked = true
          item.links.add(link)
          break
        }
      }
    }
  }
}

///|
fn Doc::join_weak_neighbor_links(self : Doc, item : Item) -> Unit {
  guard item.left is Some(left) && item.right is Some(right) else { return }
  let left = self.items[left]
  let right = self.items[right]
  if !left.linked && !right.linked {
    return
  }
  item.linked = true
  for link in left.links {
    if right.links.contains(link) {
      item.links.add(link)
    } else if self.find(link)
      is Some({ content: Shared(SharedWeak(source)), .. }) &&
      source.end.assoc == Before {
      item.links.add(link)
    }
  }
  for link in right.links {
    if !left.links.contains(link) &&
      self.find(link) is Some({ content: Shared(SharedWeak(source)), .. }) &&
      source.start.assoc == After &&
      source.start.id() ==
      Some({
        client: left.id.client,
        clock: left.id.clock + left.content.length().reinterpret_as_uint() - 1U,
      }) {
      item.links.add(link)
    }
  }
}

///|
fn Doc::event_ancestors(self : Doc, parent : Parent) -> Array[Parent] {
  let pending = [parent]
  let seen : Set[Parent] = Set([])
  let result = []
  while pending.pop() is Some(current) {
    if seen.contains(current) {
      continue
    }
    seen.add(current)
    result.push(current)
    if current is Nested(id) && self.find(id) is Some(item) {
      if item.parent is Some(parent) {
        pending.push(parent)
      }
      for link in item.links {
        pending.push(Nested(link))
      }
    }
  }
  result
}

///|
fn Doc::physical_event_path(
  self : Doc,
  ancestor : Parent,
  descendant : Parent,
) -> ReadOnlyArray[PathSegment] {
  if self.event_path(ancestor, descendant) is Some(path) {
    return path
  }
  let mut root = descendant
  while root is Nested(id) &&
        self.find(id) is Some(item) &&
        item.parent is Some(parent) {
    root = parent
  }
  self.event_path(root, descendant).unwrap_or([])
}
