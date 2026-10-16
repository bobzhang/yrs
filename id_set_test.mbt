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
