///|
/// Metadata indexed by CRDT identity ranges. Overlaps union their attributes.
pub struct IdMap[A] {
  priv clients : Map[UInt64, Array[AttrRange[A]]]
}

///|
pub fn[A] IdMap::IdMap() -> IdMap[A] {
  { clients: {}, }
}

///|
pub fn[A : Eq] IdMap::from_set(
  set : IdSet,
  attrs : Array[ContentAttribute[A]],
) -> IdMap[A] {
  let result = IdMap()
  // Upstream removes adjacent duplicates here, but retains insert's input order.
  let unique = []
  for attr in attrs {
    if unique.last() != Some(attr) {
      unique.push(attr)
    }
  }
  let attrs = ContentAttributes(values=unique)
  for client in set.client_ids() {
    result.clients[client] = set
      .get(client)
      .unwrap()
      .map(fn(r) { AttrRange(r.0, r.1, attrs~) })
  }
  result
}

///|
pub fn[A] IdMap::copy(self : IdMap[A]) -> IdMap[A] {
  let result = IdMap()
  for client, ranges in self.clients {
    result.clients[client] = ranges.copy()
  }
  result
}

///|
pub fn[A] IdMap::is_empty(self : IdMap[A]) -> Bool {
  self.clients.is_empty()
}

///|
pub fn[A] IdMap::contains(self : IdMap[A], id : Id) -> Bool {
  self.clients
  .get(id.client)
  .unwrap_or([])
  .any(fn(r) { r.start <= id.clock && id.clock < r.end })
}

///|
/// Snapshot iterator ordered by client ID, then clock.
pub fn[A] IdMap::iter(self : IdMap[A]) -> Iter[(UInt64, AttrRange[A])] {
  let clients = self.clients.to_array()
  clients.sort_by(fn(a, b) { a.0.compare(b.0) })
  let result = []
  for (client, ranges) in clients {
    for range in ranges {
      result.push((client, range))
    }
  }
  result.iter()
}

///|
fn[A : Eq] push_attr_range(
  output : Array[AttrRange[A]],
  start : UInt32,
  end : UInt32,
  attrs : ContentAttributes[A],
) -> Unit {
  if start >= end {
    return
  }
  if output.last() is Some(last) && last.end == start && last.attrs == attrs {
    output[output.length() - 1] = { start: last.start, end, attrs: last.attrs, }
  } else {
    output.push({ start, end, attrs, })
  }
}

///|
// Sweep sorted boundaries; mode 0 is union, 1 intersection, 2 difference.
fn[A : Eq] combine_attr_ranges(
  a : Array[AttrRange[A]],
  b : Array[AttrRange[A]],
  mode : Int32,
) -> Array[AttrRange[A]] {
  let points = []
  for ranges in [a, b] {
    for r in ranges {
      points.push(r.start)
      points.push(r.end)
    }
  }
  points.sort()
  let output = []
  let mut i = 0
  let mut j = 0
  for p in 1..<points.length() {
    let start = points[p - 1]
    let end = points[p]
    if start == end {
      continue
    }
    while i < a.length() && a[i].end <= start {
      i += 1
    }
    while j < b.length() && b[j].end <= start {
      j += 1
    }
    let left = if i < a.length() && a[i].start <= start {
      Some(a[i].attrs)
    } else {
      None
    }
    let right = if j < b.length() && b[j].start <= start {
      Some(b[j].attrs)
    } else {
      None
    }
    let attrs = match (left, right) {
      (Some(l), Some(r)) => if mode == 2 { None } else { Some(l.merge(r)) }
      (Some(l), None) => if mode == 1 { None } else { Some(l) }
      (None, Some(r)) => if mode == 0 { Some(r) } else { None }
      _ => None
    }
    if attrs is Some(attrs) {
      push_attr_range(output, start, end, attrs)
    }
  }
  output
}

///|
pub fn[A : Eq] IdMap::insert(
  self : IdMap[A],
  range : BlockRange,
  attrs : Array[ContentAttribute[A]],
) -> Unit {
  let end = range.end()
  if range.length == 0U || attrs.is_empty() {
    return
  }
  let ranges = self.clients.get(range.client).unwrap_or([])
  let attrs = ContentAttributes(values=attrs)
  // Match upstream's tail coalescing before combining overlapping attributes.
  if ranges.last() is Some(last) &&
    range.clock >= last.start &&
    range.clock <= last.end &&
    last.attrs == attrs {
    ranges[ranges.length() - 1] = AttrRange(
      last.start,
      last.end.max(end),
      attrs=last.attrs,
    )
    return
  }
  self.clients[range.client] = combine_attr_ranges(
    ranges,
    [AttrRange(range.clock, end, attrs~)],
    0,
  )
}

///|
pub fn[A : Eq] IdMap::remove(self : IdMap[A], range : BlockRange) -> Unit {
  let end = range.end()
  if range.length == 0U {
    return
  }
  if self.clients.get(range.client) is Some(ranges) {
    let remaining = combine_attr_ranges(
      ranges,
      [AttrRange(range.clock, end)],
      2,
    )
    if remaining.is_empty() {
      self.clients.remove(range.client)
    } else {
      self.clients[range.client] = remaining
    }
  }
}

///|
pub fn[A : Eq] IdMap::merge_with(self : IdMap[A], other : IdMap[A]) -> Unit {
  for client, ranges in other.clients {
    self.clients[client] = combine_attr_ranges(
      self.clients.get(client).unwrap_or([]),
      ranges,
      0,
    )
  }
}

///|
pub fn[A : Eq] IdMap::merge_many(maps : Array[IdMap[A]]) -> IdMap[A] {
  let result = IdMap()
  for map in maps {
    result.merge_with(map)
  }
  result
}

///|
/// Intersection retains shared identities and unions both maps' attributes.
pub fn[A : Eq] IdMap::intersect_with(self : IdMap[A], other : IdMap[A]) -> Unit {
  for (client, ranges) in self.clients.to_array() {
    let remaining = combine_attr_ranges(
      ranges,
      other.clients.get(client).unwrap_or([]),
      1,
    )
    if remaining.is_empty() {
      self.clients.remove(client)
    } else {
      self.clients[client] = remaining
    }
  }
}

///|
pub fn[A : Eq] IdMap::diff_with(self : IdMap[A], other : IdSet) -> Unit {
  for (client, start, end) in other.ranges() {
    self.remove(BlockRange(client, start, end - start))
  }
}

///|
pub fn[A : Eq, B] IdMap::diff_map_with(
  self : IdMap[A],
  other : IdMap[B],
) -> Unit {
  self.diff_with(other.as_id_set())
}

///|
pub fn[A] IdMap::filter(
  self : IdMap[A],
  predicate : (ReadOnlyArray[ContentAttribute[A]]) -> Bool,
) -> IdMap[A] {
  let result = IdMap()
  for client, ranges in self.clients {
    let selected = ranges.filter(fn(r) { predicate(r.attrs.values) })
    if !selected.is_empty() {
      result.clients[client] = selected
    }
  }
  result
}

///|
pub fn[A] IdMap::as_id_set(self : IdMap[A]) -> IdSet {
  IdSet(ranges=self.iter().map(fn(p) { (p.0, p.1.start, p.1.end) }).to_array())
}

///|
/// Covers the whole requested interval, including gaps with empty attributes.
pub fn[A] IdMap::attributions(
  self : IdMap[A],
  range : BlockRange,
) -> Array[AttrRange[A]] {
  let end = range.end()
  let result = []
  let mut cursor = range.clock
  for r in self.clients.get(range.client).unwrap_or([]) {
    if r.end <= cursor {
      continue
    }
    if r.start >= end {
      break
    }
    let start = r.start.max(cursor)
    if cursor < start {
      result.push(AttrRange(cursor, start))
    }
    let stop = r.end.min(end)
    result.push(AttrRange(start, stop, attrs=r.attrs))
    cursor = stop
    if cursor == end {
      break
    }
  }
  if cursor < end || result.is_empty() {
    result.push(AttrRange(cursor, end))
  }
  result
}

///|
pub impl[A : Eq] Eq for IdMap[A] with fn equal(self, other) {
  self.clients.length() == other.clients.length() &&
  self.clients.to_array().all(fn(p) { other.clients.get(p.0) == Some(p.1) })
}

///|
pub extend IdMap with Eq::{equal, not_equal}
