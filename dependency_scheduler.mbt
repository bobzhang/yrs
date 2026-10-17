///|
// Return the batch block that can supply this exact clock. State-vector
// watermarks cannot answer this question for sparse histories.
fn dependency_provider(batch : Array[RawItem], id : Id) -> Int32? {
  let index = for lo = 0, hi = batch.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let raw = batch[mid]
    if raw.id.client > id.client ||
      (raw.id.client == id.client && raw.id.clock <= id.clock) {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo - 1
  }
  guard index >= 0 else { return None }
  let raw = batch[index]
  if raw.id.client == id.client &&
    id.clock < raw.id.clock + raw.content.length().reinterpret_as_uint() {
    Some(index)
  } else {
    None
  }
}

///|
// Only retry a blocked item when its missing clock becomes available. The
// (round, position) queue preserves the former fixed-point scan order, including
// observable map/weak/subdocument side effects, without visiting blocked items
// on every round. Negative keys turn the max-priority queue into a min queue.
// Return attempts for deterministic complexity regression tests.
fn Doc::integrate_pending(self : Doc) -> Int32 {
  let batch = normalize_items(self.pending)
  let ready = @priority_queue.PriorityQueue([])
  let done = Array::make(batch.length(), false)
  let waiting : Map[Int32, Array[(Id, Int32)]] = Map([])
  for index in 0..<batch.length() {
    ready.push((0, -index))
  }
  let mut attempts = 0
  while ready.pop() is Some((negative_round, negative_index)) {
    let index = -negative_index
    attempts += 1
    match self.integrate_dependency(batch[index]) {
      None => done[index] = true
      Some(id) =>
        if dependency_provider(batch, id) is Some(provider) {
          let entries = waiting.get_or_init(provider, fn() { [] })
          entries.push((id, index))
        }
    }
    // A partially integrated raw block can already supply a waiting clock.
    // Wake those dependents even when a later slice remains blocked.
    if waiting.get(index) is Some(entries) {
      waiting.remove(index)
      let remaining = []
      for (id, dependent) in entries {
        if self.find(id) is Some(_) {
          let round = negative_round - (if dependent <= index { 1 } else { 0 })
          ready.push((round, -dependent))
        } else {
          remaining.push((id, dependent))
        }
      }
      if !remaining.is_empty() {
        waiting[index] = remaining
      }
    }
  }
  self.pending.clear()
  for index, raw in batch {
    if !done[index] {
      self.pending.push(raw)
    }
  }
  attempts
}
