///|
/// Encode integrated changes only. Pending blocks and early deletions are omitted.
pub fn Doc::encode_diff_v1(self : Doc, remote : StateVector) -> Bytes {
  self.encode_document(remote, false)
}

///|
pub fn Doc::encode_diff_v2(
  self : Doc,
  remote : StateVector,
) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(self.encode_diff_v1(remote), max_items=0x7fff_ffff)
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
    let result = try! Update::decode_v1(
      encode_raw_update(
        self.pending[:].to_owned(),
        Snapshot(deletions=pending_deletions.ranges()).deletes,
      ),
    )
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
