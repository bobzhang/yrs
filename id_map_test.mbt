///|
test "attributions split overlaps union metadata and cover query gaps" {
  let alice = @yrs.ContentAttribute("author", "Alice")
  let bob = @yrs.ContentAttribute("author", "Bob")
  let map = @yrs.IdMap()
  map.insert(@yrs.BlockRange(1UL, 2U, 6U), [alice])
  map.insert(@yrs.BlockRange(1UL, 4U, 6U), [bob])
  let ranges = map.attributions(@yrs.BlockRange(1UL, 0U, 12U))
  assert_eq(
    ranges.map(fn(r) {
      (r.start, r.end, r.attrs.as_array().map(fn(a) { a.value }))
    }),
    [
      (0U, 2U, []),
      (2U, 4U, ["Alice"]),
      (4U, 8U, ["Alice", "Bob"]),
      (8U, 10U, ["Bob"]),
      (10U, 12U, []),
    ],
  )
  assert_true(map.contains({ client: 1UL, clock: 9U, }))
  assert_false(map.contains({ client: 1UL, clock: 10U, }))
  let copy = map.copy()
  map.remove(@yrs.BlockRange(1UL, 3U, 6U))
  assert_eq(map.as_id_set().ranges(), [(1UL, 2U, 3U), (1UL, 9U, 10U)])
  assert_eq(copy.as_id_set().ranges(), [(1UL, 2U, 10U)])
  let intersection = copy.copy()
  intersection.intersect_with(map)
  assert_true(intersection == map)
  intersection.diff_map_with(map)
  assert_true(intersection.is_empty())
  let filtered = copy.filter(fn(attrs) { attrs.contains(alice) })
  assert_eq(filtered.as_id_set().ranges(), [(1UL, 2U, 8U)])
  let selected = @yrs.IdMap::merge_many([map, filtered])
  assert_eq(selected.as_id_set().ranges(), [(1UL, 2U, 8U), (1UL, 9U, 10U)])
  let empty : @yrs.IdMap[String] = @yrs.IdMap()
  assert_eq(
    empty
    .attributions(@yrs.BlockRange(1UL, 7U, 0U))
    .map(fn(r) { (r.start, r.end) }),
    [(7U, 7U)],
  )
}

///|
test "attribution conversions retain empty clients until set subtraction" {
  let set = @yrs.IdSet(ranges=[(1UL, 9U, 9U), (2UL, 0U, 2U)])
  let map : @yrs.IdMap[String] = @yrs.IdMap::from_set(set, [])
  assert_eq(map.as_id_set().client_ids(), [1UL, 2UL])
  assert_eq(map.as_id_set().get(1UL), Some([]))
  let empty : @yrs.IdMap[String] = @yrs.IdMap::from_set(
    @yrs.IdSet(ranges=[(3UL, 0U, 0U)]),
    [],
  )
  map.merge_with(empty)
  assert_eq(map.as_id_set().client_ids(), [1UL, 2UL, 3UL])
  map.diff_with(@yrs.IdSet())
  assert_eq(map.as_id_set().client_ids(), [2UL])
  assert_eq(empty.as_id_set().client_ids(), [3UL])
  empty.diff_map_with((@yrs.IdMap() : @yrs.IdMap[Unit]))
  assert_true(empty.is_empty())
}

///|
test "attribution codecs preserve dictionaries empty values and detached snapshots" {
  let set = @yrs.IdSet(ranges=[(1UL, 0U, 3U), (2UL, 4U, 7U)])
  let map = @yrs.IdMap::from_set(set, [
    @yrs.ContentAttribute("标签🦀", "界"),
  ])
  let attrs = @yrs.ContentAttributes(values=[
    @yrs.ContentAttribute("author", "Alice"),
  ])
  let detached = attrs.as_array()
  detached.clear()
  assert_eq(attrs.length(), 1)
  fn encode(s : String) -> @yrs.Any {
    @yrs.Any::String(s)
  }
  fn decode(v : @yrs.Any) -> String raise @yrs.DecodeError {
    guard v is String(s) else { raise @yrs.DecodeError::InvalidData("string") }
    s
  }
  assert_true(@yrs.IdMap::decode_v1(map.encode_v1(encode), decode) == map)
  assert_true(@yrs.IdMap::decode_v2(map.encode_v2(encode), decode) == map)
  let empty_attrs : @yrs.IdMap[String] = @yrs.IdMap::from_set(set, [])
  assert_false(empty_attrs.is_empty())
  assert_true(empty_attrs.contains({ client: 2UL, clock: 5U, }))
  assert_true(
    @yrs.IdMap::decode_v2(empty_attrs.encode_v2(encode), decode) == empty_attrs,
  )
  let snapshot = map.iter()
  map.remove(@yrs.BlockRange(1UL, 0U, 3U))
  assert_eq(snapshot.count(), 2)
  for
    bad in [
      b"\x01\x01\x01\x00\x01\x01\x02", b"\x01\x01\x01\xff\xff\xff\xff\x0f\x01\x00",
    ] {
    let failed = try {
      @yrs.IdMap::decode_v1(bad, decode) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  let over_budget = try {
    @yrs.IdMap::decode_v1(empty_attrs.encode_v1(encode), decode, max_items=0)
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(over_budget)
}
