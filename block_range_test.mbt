///|
test "block ranges use half-open clocks including empty and maximum endpoints" {
  let r = @yrs.BlockRange(7UL, 2U, 8U)
  assert_eq(r.id(), { client: 7UL, clock: 2U, })
  assert_eq(r.last_id(), { client: 7UL, clock: 10U, })
  assert_eq(r.clock_range(), (2U, 10U))
  assert_eq(r.slice(3U).clock_range(), (5U, 10U))
  assert_eq(r.slice(8U).clock_range(), (10U, 10U))
  assert_true(r.contains(r.id()))
  assert_false(r.contains(r.last_id()))
  assert_false(r.contains({ client: 8UL, clock: 2U, }))
  assert_false(r.slice(8U).contains(r.last_id()))
  let end = @yrs.BlockRange(0UL, 0xfffffffeU, 1U)
  assert_eq(end.clock_end(), 0xffffffffU)
  assert_eq(end.slice(1U).id().clock, 0xffffffffU)
  assert_eq(end.slice(1U).last_id().clock, 0xffffffffU)
}

///|
test "panic block range slicing rejects unsigned underflow" {
  @yrs.BlockRange(1UL, 5U, 3U).slice(4U) |> ignore
}
