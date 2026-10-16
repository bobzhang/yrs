///|
pub(all) struct AwarenessEntry {
  clock : UInt32
  json : String
} derive(Debug, Eq)

///|
pub struct AwarenessUpdate {
  priv clients : Map[UInt64, AwarenessEntry]
}

///|
pub fn AwarenessUpdate::AwarenessUpdate(
  entries~ : Array[(UInt64, AwarenessEntry)] = [],
) -> AwarenessUpdate {
  { clients: Map::from_array(entries), }
}

///|
pub fn AwarenessUpdate::entries(
  self : AwarenessUpdate,
) -> Array[(UInt64, AwarenessEntry)] {
  let result = self.clients.to_array()
  result.sort_by(fn(a, b) { a.0.compare(b.0) })
  result
}

///|
pub fn AwarenessUpdate::encode_v1(self : AwarenessUpdate) -> Bytes {
  let out : Writer = { bytes: [], }
  out.uint(self.clients.length().to_uint64())
  for (client, entry) in self.entries() {
    out.uint(client)
    out.uint(entry.clock.to_uint64())
    out.string(entry.json)
  }
  out.finish()
}

///|
pub fn AwarenessUpdate::decode_v1(
  bytes : Bytes,
) -> AwarenessUpdate raise DecodeError {
  let input : Reader = { bytes, offset: 0, }
  let result = AwarenessUpdate()
  let count = input.count()
  for _ in 0..<count {
    let client = input.uint()
    result.clients[client] = { clock: input.clock(), json: input.string(), }
  }
  input.finish()
  result
}

///|
pub(all) struct AwarenessState {
  clock : UInt32
  last_updated : UInt64
  data : String?
} derive(Debug, Eq)

///|
pub(all) struct AwarenessSummary {
  added : ReadOnlyArray[UInt64]
  updated : ReadOnlyArray[UInt64]
  removed : ReadOnlyArray[UInt64]
} derive(Debug, Eq)

///|
pub fn AwarenessSummary::all_changes(self : AwarenessSummary) -> Array[UInt64] {
  let result = self.added.iter().to_array()
  for client in self.updated {
    result.push(client)
  }
  for client in self.removed {
    result.push(client)
  }
  result
}

///|
fn AwarenessSummary::is_empty(self : AwarenessSummary) -> Bool {
  self.added.is_empty() && self.updated.is_empty() && self.removed.is_empty()
}

///|
pub suberror AwarenessError {
  ClientNotFound(UInt64)
} derive(Debug)

///|
pub extend AwarenessError with Debug::{to_repr}

///|
/// Ephemeral presence state. Supply the host clock in milliseconds so the same
/// implementation works in browsers, native programs and deterministic tests.
pub struct Awareness {
  priv document : Doc
  priv states : Map[UInt64, AwarenessState]
  priv clock : () -> UInt64
  priv changes : Observer[String, (Awareness, AwarenessSummary, Bytes?) -> Unit]
  priv updates : Observer[String, (Awareness, AwarenessSummary, Bytes?) -> Unit]
  priv mut notifying_change : Bool
  priv mut notifying_update : Bool
}

///|
pub fn Awareness::Awareness(doc : Doc, clock~ : () -> UInt64) -> Awareness {
  {
    document: doc,
    states: {},
    clock,
    changes: Observer(),
    updates: Observer(),
    notifying_change: false,
    notifying_update: false,
  }
}

///|
pub fn Awareness::doc(self : Awareness) -> Doc {
  self.document
}

///|
pub fn Awareness::client_id(self : Awareness) -> UInt64 {
  self.document.client_id()
}

///|
pub fn Awareness::entries(self : Awareness) -> Array[(UInt64, AwarenessState)] {
  let result = self.states.to_array()
  result.sort_by(fn(a, b) { a.0.compare(b.0) })
  result
}

///|
pub fn Awareness::state_raw(self : Awareness, client : UInt64) -> String? {
  self.states.get(client).bind(fn(state) { state.data })
}

///|
pub fn Awareness::state(self : Awareness, client : UInt64) -> Json? {
  self
  .state_raw(client)
  .bind(fn(value) { Some(@json.parse(value)) catch { _ => None } })
}

///|
pub fn Awareness::local_state_raw(self : Awareness) -> String? {
  self.state_raw(self.client_id())
}

///|
pub fn Awareness::local_state(self : Awareness) -> Json? {
  self.state(self.client_id())
}

///|
pub fn Awareness::meta(self : Awareness, client : UInt64) -> (UInt32, UInt64)? {
  self.states.get(client).map(fn(state) { (state.clock, state.last_updated) })
}

///|
pub fn Awareness::on_change(
  self : Awareness,
  key : String,
  callback : (Awareness, AwarenessSummary, Bytes?) -> Unit,
) -> Unit {
  self.changes.subscribe(key, callback)
}

///|
pub fn Awareness::on_update(
  self : Awareness,
  key : String,
  callback : (Awareness, AwarenessSummary, Bytes?) -> Unit,
) -> Unit {
  self.updates.subscribe(key, callback)
}

///|
pub fn Awareness::unobserve_change(self : Awareness, key : String) -> Bool {
  self.changes.unsubscribe(key)
}

///|
pub fn Awareness::unobserve_update(self : Awareness, key : String) -> Bool {
  self.updates.unsubscribe(key)
}

///|
fn Awareness::notify(
  self : Awareness,
  change : AwarenessSummary,
  update : AwarenessSummary,
  origin : Bytes?,
) -> Unit {
  if !change.is_empty() && !self.notifying_change {
    self.notifying_change = true
    self.changes.trigger(fn(callback) { callback(self, change, origin) })
    self.notifying_change = false
  }
  if !update.is_empty() && !self.notifying_update {
    self.notifying_update = true
    self.updates.trigger(fn(callback) { callback(self, update, origin) })
    self.notifying_update = false
  }
}

///|
pub fn Awareness::set_local_state_raw(self : Awareness, json : String) -> Unit {
  let client = self.client_id()
  let previous = self.states.get(client)
  self.states[client] = {
    clock: previous.map(fn(state) { state.clock + 1U }).unwrap_or(1U),
    last_updated: (self.clock)(),
    data: Some(json),
  }
  let old_data = previous.bind(fn(state) { state.data })
  let added : ReadOnlyArray[UInt64] = if old_data is None {
    [client]
  } else {
    []
  }
  let updated : ReadOnlyArray[UInt64] = if old_data is Some(_) {
    [client]
  } else {
    []
  }
  let changed : ReadOnlyArray[UInt64] = if old_data is Some(old) && old != json {
    [client]
  } else {
    []
  }
  self.notify(
    { added, updated: changed, removed: [], },
    { added, updated, removed: [], },
    None,
  )
}

///|
pub fn Awareness::set_local_state(self : Awareness, state : Json) -> Unit {
  self.set_local_state_raw(state.stringify())
}

///|
pub fn Awareness::remove_state(self : Awareness, client : UInt64) -> Unit {
  let previous = self.states.get(client)
  self.states[client] = match previous {
    Some(state) => { ..state, clock: state.clock + 1U, data: None, }
    None => { clock: 1U, last_updated: (self.clock)(), data: None, }
  }
  // Upstream also emits change events for an unknown client when observed.
  if previous is Some(_) || !self.changes.is_empty() {
    let event : AwarenessSummary = {
      added: [],
      updated: [],
      removed: [client],
    }
    self.notify(event, event, None)
  }
}

///|
pub fn Awareness::clean_local_state(self : Awareness) -> Unit {
  self.remove_state(self.client_id())
}

///|
pub fn Awareness::update(self : Awareness) -> AwarenessUpdate {
  let entries = self
    .entries()
    .filter_map(fn(pair) {
      match pair.1.data {
        Some(json) => Some((pair.0, { clock: pair.1.clock, json, }))
        None => None
      }
    })
  AwarenessUpdate(entries~)
}

///|
pub fn Awareness::update_with_clients(
  self : Awareness,
  clients : Array[UInt64],
) -> AwarenessUpdate raise AwarenessError {
  let result = AwarenessUpdate()
  for client in clients {
    guard self.states.get(client) is Some(state) else {
      raise ClientNotFound(client)
    }
    result.clients[client] = {
      clock: state.clock,
      json: state.data.unwrap_or("null"),
    }
  }
  result
}

///|
pub fn Awareness::apply_update(
  self : Awareness,
  update : AwarenessUpdate,
  origin? : Bytes,
) -> AwarenessSummary? {
  let now = (self.clock)()
  let added = []
  let updated = []
  let changed = []
  let removed = []
  for (client, entry) in update.entries() {
    let data = if entry.json == "null" { None } else { Some(entry.json) }
    let mut clock = entry.clock
    match self.states.get(client) {
      None => {
        self.states[client] = { clock, last_updated: now, data, }
        if data is Some(_) {
          added.push(client)
        }
      }
      Some(state) =>
        if state.clock < clock ||
          (state.clock == clock && data is None && state.data is Some(_)) {
          let mut next_data = data
          if data is None {
            if client == self.client_id() && state.data is Some(_) {
              clock += 1U
              next_data = state.data
            } else {
              removed.push(client)
            }
          } else {
            updated.push(client)
            if state.data is Some(_) && state.data != data {
              changed.push(client)
            }
          }
          self.states[client] = { clock, last_updated: now, data: next_data, }
        }
    }
  }
  let summary : AwarenessSummary = {
    added: ReadOnlyArray::from_array(added[:]),
    updated: ReadOnlyArray::from_array(updated[:]),
    removed: ReadOnlyArray::from_array(removed[:]),
  }
  if summary.is_empty() {
    None
  } else {
    self.notify(
      { ..summary, updated: ReadOnlyArray::from_array(changed[:]), },
      summary,
      origin,
    )
    Some(summary)
  }
}

///|
pub extend AwarenessEntry with Debug::{to_repr}

///|
pub extend AwarenessEntry with Eq::{equal, not_equal}

///|
pub extend AwarenessState with Debug::{to_repr}

///|
pub extend AwarenessState with Eq::{equal, not_equal}

///|
pub extend AwarenessSummary with Debug::{to_repr}

///|
pub extend AwarenessSummary with Eq::{equal, not_equal}
