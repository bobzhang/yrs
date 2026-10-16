///|
/// Encode integrated changes only. Pending blocks and early deletions are omitted.
pub fn Doc::encode_diff_v1(self : Doc, remote : StateVector) -> Bytes {
  self.encode_document(remote, false)
}

///|
// Keep the public fallible signature for source compatibility.
#warnings("-unused_error_type")
pub fn Doc::encode_diff_v2(
  self : Doc,
  remote : StateVector,
) -> Bytes raise DecodeError {
  self.encode_document(remote, false, v2=true)
}

///|
/// Remove unresolved blocks and deletions, returning an update that can be saved
/// and applied later. Already integrated changes, including sparse ones, remain.
pub fn Doc::prune_pending(self : Doc) -> Update? {
  self.with_mutation(fn() {
    let known = self.integrated_ids()
    let all_deletions = []
    for client, ranges in self.deletes {
      for (start, end) in ranges {
        all_deletions.push((client, start, end))
      }
    }
    let pending_deletions = IdSet(ranges=all_deletions).diff(known)
    if self.pending.is_empty() && pending_deletions.is_empty() {
      return None
    }
    let result = Update::from_blocks(self.pending, pending_deletions)
    self.pending.clear()
    let retained = IdSet(ranges=all_deletions).intersect(known)
    self.deletes.clear()
    for (client, start, end) in retained.ranges() {
      self.add_delete(client, start, end)
    }
    Some(result)
  })
}

///|
fn Doc::integrated_ids(self : Doc) -> IdSet {
  let ranges = []
  for client, blocks in self.clients {
    for item in blocks {
      ranges.push(
        (
          client,
          item.id.clock,
          item.id.clock + item.content.length().reinterpret_as_uint(),
        ),
      )
    }
  }
  IdSet(ranges~)
}

///|
/// Whether unresolved blocks or early deletions are queued, matching Yrs's
/// pending-store check. has_missing_updates additionally detects clock gaps.
pub fn Doc::has_pending_updates(self : Doc) -> Bool {
  if !self.pending.is_empty() {
    return true
  }
  let deleted = []
  for client, ranges in self.deletes {
    for (start, end) in ranges {
      deleted.push((client, start, end))
    }
  }
  !IdSet(ranges=deleted).diff(self.integrated_ids()).is_empty()
}

///|
/// Inspect unresolved item blocks without draining or retrying them. Pending
/// deletions are exposed separately by pending_delete_set, as in Yrs Store.
pub fn Doc::pending_update(self : Doc) -> Update? {
  if self.pending.is_empty() {
    return None
  }
  Some(Update::from_blocks(self.pending, IdSet()))
}

///|
/// Return an owned copy of deletion ranges whose items have not arrived yet.
/// Reading this metadata does not start a transaction or notify observers.
pub fn Doc::pending_delete_set(self : Doc) -> IdSet? {
  let ranges = []
  for client, entries in self.deletes {
    for (start, end) in entries {
      ranges.push((client, start, end))
    }
  }
  let pending = IdSet(ranges~).diff(self.integrated_ids())
  if pending.is_empty() {
    None
  } else {
    Some(pending)
  }
}
