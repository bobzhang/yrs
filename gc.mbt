///|
pub fn Doc::skip_gc(self : Doc) -> Bool {
  !self.wire_gc
}

///|
fn Doc::keep_ranges(
  self : Doc,
  ranges : Array[(UInt64, UInt32, UInt32)],
  keep : Bool,
) -> Unit {
  for (client, start, end) in ranges {
    for item in self.clients.get(client).unwrap_or([]) {
      if item.id.clock >= end {
        break
      }
      if item.id.clock + item.content.length().reinterpret_as_uint() <= start {
        continue
      }
      let mut cursor = Some(item)
      while cursor is Some(entry) {
        if entry.keep == keep {
          break
        }
        entry.keep = keep
        cursor = match entry.parent {
          Some(Nested(id)) => self.find(id)
          _ => None
        }
      }
    }
  }
}

///|
fn Doc::collect_garbage(
  self : Doc,
  ranges : Array[(UInt64, UInt32, UInt32)],
) -> Unit {
  // Keep ownership is derived from all active managers, so clearing one
  // history cannot release another manager's retained content.
  for item in self.items.values() {
    item.keep = false
  }
  for retained in self.undo_retention.values() {
    self.keep_ranges(retained(), true)
  }
  let pending : Array[(Item, Bool)] = []
  for (client, start, end) in ranges {
    for item in self.clients.get(client).unwrap_or([]) {
      if item.id.clock >= end {
        break
      }
      if item.id.clock + item.content.length().reinterpret_as_uint() > start {
        pending.push((item, false))
      }
    }
  }
  while pending.pop() is Some((item, parent_gc)) {
    if !item.deleted || item.keep || item.content is Garbage(_) {
      continue
    }
    if item.content is Shared(_) &&
      self.roots.get(Nested(item.id)) is Some(branch) {
      let seen : Set[Id] = Set([])
      let mut cursor = branch.head
      while cursor is Some(id) && !seen.contains(id) {
        seen.add(id)
        let child = self.items[id]
        pending.push((child, true))
        cursor = child.right
      }
      for id in branch.values.values() {
        let mut cursor = Some(id)
        while cursor is Some(id) && !seen.contains(id) {
          seen.add(id)
          let child = self.items[id]
          pending.push((child, true))
          cursor = child.left
        }
      }
      branch.head = None
      branch.values.clear()
      branch.heads.clear()
    }
    let length = item.content.length()
    item.content = if parent_gc { Garbage(length) } else { Deleted(length) }
    if self.active_transaction is Some(txn) {
      txn.merge_clients.add(item.id.client) |> ignore
    }
  }
}

///|
/// Collect deleted content not retained for undo, even when skip_gc is true.
/// Historical snapshots cannot reconstruct content once it has been collected.
pub fn Transaction::gc(self : Transaction) -> Unit {
  guard !self.closed else { abort("transaction is already closed") }
  let ranges = []
  for client, blocks in self.document.clients {
    for item in blocks {
      if item.deleted {
        ranges.push(
          (
            client,
            item.id.clock,
            item.id.clock + item.content.length().reinterpret_as_uint(),
          ),
        )
      }
    }
  }
  self.document.collect_garbage(ranges)
}

///|
pub fn Doc::gc(self : Doc) -> Unit {
  self.with_mutation(fn() { self.active_transaction.unwrap().gc() })
}
