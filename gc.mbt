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
    let blocks = self.clients.get(client).unwrap_or([])
    for i in first_block_after(blocks, start)..<blocks.length() {
      let item = blocks[i]
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
        if keep {
          self.has_keep_marks = true
        }
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
  if ranges.is_empty() {
    return
  }
  // Keep ownership is derived from all active managers, so clearing one
  // history cannot release another manager's retained content.
  if self.has_keep_marks {
    for item in self.items.values() {
      item.keep = false
    }
    self.has_keep_marks = false
  }
  for retained in self.undo_retention.values() {
    self.keep_ranges(retained(), true)
  }
  let pending : Array[(Item, Bool)] = []
  for (client, start, end) in ranges {
    let blocks = self.clients.get(client).unwrap_or([])
    for i in first_block_after(blocks, start)..<blocks.length() {
      let item = blocks[i]
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
      branch.position_hint = None
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
pub fn Transaction::gc(self : Transaction, delete_set? : IdSet) -> Unit {
  guard !self.closed else { abort("transaction is already closed") }
  guard !self.document.notifying_transaction else {
    abort("cannot collect inside a read-only observer")
  }
  if delete_set is Some(set) {
    let selected = []
    for (client, start, end) in set.ranges() {
      if self.document.find({ client, clock: start, }) is Some(first) {
        let mut cursor = start.to_uint64()
        for block in self.document.clients.get(client).unwrap_or([]) {
          if block.id.clock < first.id.clock {
            continue
          }
          cursor += block.content.length().to_uint64()
          if cursor > end.to_uint64() {
            break
          }
          selected.push(
            (
              client,
              block.id.clock,
              block.id.clock + block.content.length().reinterpret_as_uint(),
            ),
          )
        }
      }
    }
    self.document.collect_garbage(selected)
    return
  }
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
pub fn Doc::gc(self : Doc, delete_set? : IdSet) -> Unit {
  self.with_mutation(fn() { self.active_transaction.unwrap().gc(delete_set?) })
}
