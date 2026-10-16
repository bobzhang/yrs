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
