///|
/// A grouped mutation scope. Metadata and encoded updates become stable when
/// the scope closes. Use Doc::transact to commit even when the action raises.
pub struct Transaction {
  priv cleaned : IdSet
  priv weak_changes : Set[Parent]
  priv changed_parents : Array[Out]
  priv mut sub_changed : Bool
  priv sub_added : Map[UInt64, Doc]
  priv sub_removed : Map[UInt64, Doc]
  priv sub_loaded : Map[UInt64, Doc]
  priv document : Doc
  priv mut before : StateVector?
  priv mut after : StateVector?
  priv source : Bytes?
  priv mut is_local : Bool
  priv added : Array[(UInt64, UInt32, UInt32)]
  priv capture_update : Bool
  priv merge_clients : Set[UInt64]
  priv sequences : Set[Parent]
  priv map_changes : Map[Parent, Map[String, (Id?, Out?)]]
  priv removed : Array[(UInt64, UInt32, UInt32)]
  priv mut encoded : Bytes?
  priv mut closed : Bool
}

///|
pub fn Transaction::doc(self : Transaction) -> Doc {
  self.document
}

///|
pub fn Transaction::origin(self : Transaction) -> Bytes? {
  self.source
}

///|
pub fn Transaction::is_local(self : Transaction) -> Bool {
  self.is_local
}

///|
pub fn Transaction::before_state(self : Transaction) -> StateVector {
  let state = match self.before {
    Some(state) => state
    None => {
      let state = self.document.state_vector()
      for (client, start, _) in self.added {
        state.clocks[client] = state.clocks
          .get(client)
          .map(fn(clock) { clock.min(start) })
          .unwrap_or(start)
      }
      self.before = Some(state)
      state
    }
  }
  StateVector(entries=state.entries())
}

///|
pub fn Transaction::after_state(self : Transaction) -> StateVector {
  let state = match self.after {
    Some(state) => state
    None => {
      let state = self.document.state_vector()
      for (client, _, end) in self.added {
        state.set_max(client, end)
      }
      self.after = Some(state)
      state
    }
  }
  StateVector(entries=state.entries())
}

///|
pub fn Transaction::insertions(
  self : Transaction,
) -> Array[(UInt64, UInt32, UInt32)] {
  Snapshot(deletions=self.added).deletions()
}

///|
pub fn Transaction::deletions(
  self : Transaction,
) -> Array[(UInt64, UInt32, UInt32)] {
  Snapshot(deletions=self.removed).deletions()
}

///|
pub fn Transaction::encode_update_v1(self : Transaction) -> Bytes {
  if self.encoded is Some(bytes) {
    return bytes
  }
  let before = self.before_state()
  let items = []
  for client, blocks in self.document.clients {
    if before.clocks.contains(client) &&
      self.document.state.get(client) <= before.get(client) {
      continue
    }
    let clock = before.get(client)
    for index in first_block_after(blocks, clock)..<blocks.length() {
      let item = blocks[index]
      items.push(
        (
          {
            id: item.id,
            origin: item.origin,
            right_origin: item.right_origin,
            parent: item.parent,
            parent_sub: item.parent_sub,
            content: item.content,
          } : RawItem).trim_start(clock),
      )
    }
  }
  encode_raw_update(items, Snapshot(deletions=self.removed).deletes)
}

///|
pub fn Transaction::encode_update_v2(
  self : Transaction,
) -> Bytes raise DecodeError {
  convert_update_v1_to_v2(self.encode_update_v1(), max_items=0x7fff_ffff)
}

///|
fn Doc::begin_transaction(
  self : Doc,
  origin : Bytes?,
  capture_update : Bool,
) -> Transaction {
  guard self.active_transaction is None && !self.notifying_transaction else {
    abort("document already has an active transaction")
  }
  let transaction : Transaction = {
    cleaned: IdSet(),
    weak_changes: Set([]),
    changed_parents: [],
    sub_changed: false,
    sub_added: {},
    sub_removed: {},
    sub_loaded: {},
    document: self,
    before: None,
    after: None,
    source: origin,
    is_local: true,
    added: [],
    capture_update,
    merge_clients: Set([]),
    sequences: Set([]),
    map_changes: {},
    removed: [],
    encoded: None,
    closed: false,
  }
  self.active_transaction = Some(transaction)
  transaction
}

///|
fn Doc::commit_transaction(self : Doc, transaction : Transaction) -> Unit {
  guard !transaction.closed else { return }
  self.notifying_transaction = true
  self.before_observers.trigger(fn(callback) { callback(transaction) })
  self.notify_collections(transaction)
  self.notifying_transaction = false
  if self.collect_deletes {
    if self.cleanup_enabled {
      let previous = transaction.removed.length()
      self.cleanup_formatting()
      for i in previous..<transaction.removed.length() {
        let (client, start, end) = transaction.removed[i]
        transaction.cleaned.insert({ client, clock: start, }, end - start)
      }
    }
    self.collect_deletes = false
    self.deleted_items.clear()
    self.inserted_items.clear()
  }
  // Rust's after-transaction callback receives a mutable transaction. Its
  // additional edits belong to this commit but do not repeat type observers.
  self.after_observers.trigger(fn(callback) { callback(transaction) })
  if self.wire_gc {
    self.collect_garbage(transaction.removed)
  }
  self.compact(transaction)
  if transaction.capture_update {
    transaction.before_state() |> ignore
    transaction.after_state() |> ignore
    transaction.encoded = Some(transaction.encode_update_v1())
  }
  transaction.closed = true
  self.notifying_transaction = true
  self.cleanup_observers.trigger(fn(callback) { callback(transaction) })
  if !transaction.added.is_empty() || !transaction.removed.is_empty() {
    self.update_v1_observers.trigger(fn(callback) {
      callback(transaction.encode_update_v1(), transaction)
    })
    if !self.update_v2_observers.is_empty() {
      let bytes = try! transaction.encode_update_v2()
      self.update_v2_observers.trigger(fn(callback) {
        callback(bytes, transaction)
      })
    }
  }
  self.commit_subdocuments(transaction)
  self.collect_deletes = false
  self.deleted_items.clear()
  self.inserted_items.clear()
  self.notifying_transaction = false
  self.active_transaction = None
}

///|
fn[T] Doc::with_mutation(self : Doc, action : () -> T) -> T {
  guard !self.notifying_transaction else {
    abort("cannot mutate a document inside its observer")
  }
  if self.active_transaction is Some(_) {
    return action()
  }
  let transaction = self.begin_transaction(
    None,
    !self.deep_observers.is_empty() ||
    !self.xml_observers.is_empty() ||
    !self.xml_text_observers.is_empty() ||
    !self.text_observers.is_empty() ||
    !self.array_observers.is_empty() ||
    !self.map_observers.is_empty() ||
    !self.before_observers.is_empty() ||
    !self.after_observers.is_empty() ||
    !self.cleanup_observers.is_empty() ||
    !self.update_v1_observers.is_empty() ||
    !self.update_v2_observers.is_empty(),
  )
  let result = action()
  self.commit_transaction(transaction)
  result
}

///|
/// Group mutations into one commit and one update event. A raised error commits
/// the edits already made, matching upstream transaction drop semantics.
pub fn[T] Doc::transact(
  self : Doc,
  action : (Transaction) -> T raise,
  origin? : Bytes,
) -> T raise {
  let transaction = self.begin_transaction(origin, true)
  errdefer self.commit_transaction(transaction)
  let result = action(transaction)
  self.commit_transaction(transaction)
  result
}

///|
pub fn Doc::observe_before_observer_calls(
  self : Doc,
  key : String,
  callback : (Transaction) -> Unit,
) -> Unit {
  self.before_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_before_observer_calls(self : Doc, key : String) -> Bool {
  self.before_observers.unsubscribe(key)
}

///|
pub fn Doc::observe_after_transaction(
  self : Doc,
  key : String,
  callback : (Transaction) -> Unit,
) -> Unit {
  self.after_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_after_transaction(self : Doc, key : String) -> Bool {
  self.after_observers.unsubscribe(key)
}

///|
pub fn Doc::observe_transaction_cleanup(
  self : Doc,
  key : String,
  callback : (Transaction) -> Unit,
) -> Unit {
  self.cleanup_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_transaction_cleanup(self : Doc, key : String) -> Bool {
  self.cleanup_observers.unsubscribe(key)
}

///|
pub fn Doc::observe_update_v1(
  self : Doc,
  key : String,
  callback : (Bytes, Transaction) -> Unit,
) -> Unit {
  self.update_v1_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_update_v1(self : Doc, key : String) -> Bool {
  self.update_v1_observers.unsubscribe(key)
}

///|
pub fn Doc::observe_update_v2(
  self : Doc,
  key : String,
  callback : (Bytes, Transaction) -> Unit,
) -> Unit {
  self.update_v2_observers.subscribe(key, callback)
}

///|
pub fn Doc::unobserve_update_v2(self : Doc, key : String) -> Bool {
  self.update_v2_observers.unsubscribe(key)
}

///|
/// Collections changed by this transaction and their ancestors. Ancestors may
/// occur more than once, matching the upstream event traversal.
pub fn Transaction::changed_parent_types(
  self : Transaction,
) -> ReadOnlyArray[Out] {
  ReadOnlyArray::from_array(self.changed_parents[:])
}
