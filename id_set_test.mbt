///|
test "client lookup distinguishes missing clients and returns owned normalized ranges" {
  let ids = @yrs.IdSet(ranges=[
    (3UL, 20U, 30U),
    (1UL, 5U, 10U),
    (3UL, 0U, 5U),
    (2UL, 7U, 7U),
    (3UL, 3U, 10U),
  ])
  assert_eq(ids.get(0UL), None)
  assert_eq(ids.get(4UL), None)
  assert_eq(ids.get(1UL), Some([(5U, 10U)]))
  assert_eq(ids.get(2UL), Some([]))
  let ranges = ids.get(3UL).unwrap()
  assert_eq(ranges, [(0U, 10U), (20U, 30U)])
  ranges[0] = (1U, 2U)
  ranges.push((40U, 50U))
  assert_eq(ids.get(3UL), Some([(0U, 10U), (20U, 30U)]))
  ids.insert({ client: 3UL, clock: 30U, }, 5U)
  assert_eq(ranges, [(1U, 2U), (20U, 30U), (40U, 50U)])
}

///|
test "clock range algebra preserves holes and extreme clocks" {
  let a = @yrs.IdSet(ranges=[
    (1UL, 0U, 10U),
    (1UL, 20U, 30U),
    (2UL, 0xffff_fffeU, 0xffff_ffffU),
  ])
  let b = @yrs.IdSet(ranges=[(1UL, 5U, 25U)])
  assert_eq(a.diff(b).ranges(), [
    (1UL, 0U, 5U),
    (1UL, 25U, 30U),
    (2UL, 0xffff_fffeU, 0xffff_ffffU),
  ])
  assert_eq(a.intersect(b).ranges(), [(1UL, 5U, 10U), (1UL, 20U, 25U)])
  assert_eq(a.merge(b).ranges(), [
    (1UL, 0U, 30U),
    (2UL, 0xffff_fffeU, 0xffff_ffffU),
  ])
  for s in [a, b, a.diff(b), a.intersect(b), @yrs.IdSet()] {
    assert_eq(@yrs.IdSet::decode_v1(s.encode_v1()).ranges(), s.ranges())
    assert_eq(@yrs.IdSet::decode_v2(s.encode_v2()).ranges(), s.ranges())
    assert_eq(@yrs.IdSet::from_json(s.to_json()).ranges(), s.ranges())
  }
  assert_true(a.contains({ client: 2UL, clock: 0xffff_fffeU, }))
  assert_false(a.contains({ client: 2UL, clock: 0xffff_ffffU, }))
  a.diff_with(b)
  a.intersect_with(a)
  assert_eq(a.length(), 2)
  a.remove_range({ client: 1UL, clock: 0U, }, 30U)
  assert_eq(a.client_ids(), [2UL])
}

///|
test "empty client metadata survives codecs copies and union but not set subtraction" {
  let a = @yrs.IdSet()
  a.insert({ client: 7UL, clock: 10U, }, 0U)
  assert_false(a.is_empty())
  assert_eq(a.length(), 1)
  assert_eq(a.client_ids(), [7UL])
  assert_eq(a.get(7UL), Some([]))
  assert_eq(a.ranges(), [])
  assert_eq(a.encode_v1(), b"\x01\x07\x00")
  for
    copy in [
      @yrs.IdSet::decode_v1(a.encode_v1()),
      @yrs.IdSet::decode_v2(a.encode_v2()),
      @yrs.IdSet::from_json(a.to_json()),
      a.merge(@yrs.IdSet()),
    ] {
    assert_eq(copy.get(7UL), Some([]))
    assert_eq(copy.encode_v1(), a.encode_v1())
  }
  let b = @yrs.IdSet(ranges=[(8UL, 0U, 0U), (9UL, 1U, 3U)])
  a.merge_with(b)
  assert_eq(a.client_ids(), [7UL, 8UL, 9UL])
  a.remove_range({ client: 8UL, clock: 0U, }, 0U)
  assert_eq(a.client_ids(), [7UL, 9UL])
  assert_eq(a.diff(@yrs.IdSet()).client_ids(), [9UL])
  assert_eq(a.intersect(a).client_ids(), [9UL])
  assert_eq(a.client_ids(), [7UL, 9UL])
}

///|
test "empty delete clients survive update and snapshot metadata round trips" {
  let encoded = b"\x00\x01\x07\x00"
  let update = @yrs.Update::decode_v1(encoded)
  assert_false(update.is_empty())
  assert_eq(update.delete_set().get(7UL), Some([]))
  let copy = update.delete_set()
  copy.insert({ client: 7UL, clock: 0U, }, 1U)
  assert_eq(update.delete_set().get(7UL), Some([]))
  update.merge(@yrs.Update())
  assert_eq(update.encode_v1(), encoded)
  assert_eq(@yrs.merge_updates_v1([encoded, b"\x00\x00"]), encoded)
  assert_eq(@yrs.diff_updates_v1(encoded, b"\x00"), encoded)
  assert_eq(
    @yrs.Update::decode_v2(update.encode_v2()).delete_set().get(7UL),
    Some([]),
  )
  let snap = @yrs.Snapshot::decode_v1(b"\x01\x07\x00\x00")
  assert_eq(snap.encode_v1(), b"\x01\x07\x00\x00")
  assert_eq(
    @yrs.Snapshot::decode_v2(snap.encode_v2()).encode_v1(),
    snap.encode_v1(),
  )
}

///|
test "snapshot constructors and equality preserve owned empty-client metadata" {
  let ids = @yrs.IdSet(ranges=[(1UL, 0U, 0U), (2UL, 1U, 4U)])
  let snapshot = @yrs.Snapshot(delete_set=ids, deletions=[(3UL, 2U, 3U)])
  assert_eq(snapshot.delete_set().client_ids(), [1UL, 2UL, 3UL])
  let copy = snapshot.delete_set()
  copy.remove_range({ client: 1UL, clock: 0U, }, 0U)
  ids.insert({ client: 4UL, clock: 0U, }, 5U)
  assert_eq(snapshot.delete_set().client_ids(), [1UL, 2UL, 3UL])
  assert_false(snapshot == @yrs.Snapshot(deletions=snapshot.deletions()))
  assert_true(snapshot == @yrs.Snapshot::decode_v2(snapshot.encode_v2()))
}

///|
test "incremental ranges preserve membership across insertion orders and clock limits" {
  let inserts = [
    (0UL, 5U, 2U),
    (0UL, 1U, 2U),
    (0UL, 3U, 2U),
    (0UL, 2U, 4U),
    (0xffff_ffff_ffff_ffffUL, 0xffff_fff8U, 2U),
    (0xffff_ffff_ffff_ffffUL, 0xffff_fffcU, 3U),
    (0xffff_ffff_ffff_ffffUL, 0xffff_fffaU, 2U),
    (0xffff_ffff_ffff_fffeUL, 0xffff_ffffU, 0U),
  ]
  // Rotating either traversal direction exercises insertion before, inside,
  // and after existing ranges, including bridges between adjacent intervals.
  for offset in 0..<inserts.length() {
    for direction in [1, -1] {
      let ids = @yrs.IdSet()
      let points : Set[@yrs.Id] = Set([])
      let clients : Set[UInt64] = Set([])
      for step in 0..<inserts.length() {
        let index = (offset + direction * step + inserts.length()) %
          inserts.length()
        let (client, clock, length) = inserts[index]
        ids.insert({ client, clock, }, length)
        clients.add(client)
        for i in 0..<length.reinterpret_as_int() {
          points.add({ client, clock: clock + i.reinterpret_as_uint(), })
        }
        assert_eq(ids.length(), clients.length())
        for c in [0UL, 1UL, 0xffff_ffff_ffff_fffeUL, 0xffff_ffff_ffff_ffffUL] {
          for base in [0U, 0xffff_fff8U] {
            for i in 0..<8 {
              let id : @yrs.Id = {
                client: c,
                clock: base + i.reinterpret_as_uint(),
              }
              assert_eq(ids.contains(id), points.contains(id))
            }
          }
        }
      }
      assert_eq(ids.ranges(), [
        (0UL, 1U, 7U),
        (0xffff_ffff_ffff_ffffUL, 0xffff_fff8U, 0xffff_ffffU),
      ])
      assert_eq(ids.get(0xffff_ffff_ffff_fffeUL), Some([]))
    }
  }
}

///|
test "panic incremental clock range overflow" {
  @yrs.IdSet().insert({ client: 0UL, clock: 0xffff_ffffU, }, 1U)
}
