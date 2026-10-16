///|
test "decoded update inspection merging and application preserve sparse histories" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "hello")
  let first = @yrs.Update::decode_v1(doc.encode_state_as_update_v1())
  let old = doc.state_vector()
  text.insert(5, " world")
  let later = @yrs.Update::decode_v1(doc.encode_state_as_update_v1(remote=old))
  assert_true(later.state_vector().is_empty())
  assert_eq(later.state_vector_lower().get(1UL), 5U)
  assert_false(later.extends(@yrs.StateVector()))
  assert_true(later.extends(old))
  assert_eq(later.insertions().ranges(), [(1UL, 5U, 11U)])
  first.merge(later)
  assert_eq(first.state_vector().get(1UL), 11U)
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update(first)
  assert_eq(peer.get_or_insert_text("text").get_string(), "hello world")
  let roundtrip = @yrs.Update::decode_v2(first.encode_v2())
  assert_eq(roundtrip.state_vector(), first.state_vector())
  let third = @yrs.Doc(client_id=3UL)
  third.apply_update_v1(first.encode_diff_v1(@yrs.StateVector()))
  assert_eq(third.get_or_insert_text("text").get_string(), "hello world")
  text.remove_range(0, 5)
  let deletion = @yrs.Update::decode_v1(
    doc.encode_state_as_update_v1(remote=first.state_vector()),
  )
  assert_false(deletion.is_empty())
  assert_false(deletion.extends(first.state_vector()))
  assert_eq(deletion.delete_set().ranges(), [(1UL, 0U, 5U)])
  assert_false(
    @yrs.Update::decode_v1(b"\x01\x01\x01\x00\x0a\x03\x00").is_empty(),
  )
}

///|
test "state vector ordering and metadata v2 preserve boundaries and associations" {
  let a = @yrs.StateVector(entries=[(1UL, 5U)])
  let b = @yrs.StateVector(entries=[(2UL, 3U)])
  assert_true(a.partial_compare(b) is None)
  a.merge(b)
  assert_eq(a.partial_compare(b), Some(1))
  assert_true(a.contains({ client: 1UL, clock: 5U, }))
  a.set_min(1UL, 2U)
  a.inc_by(1UL, 1U)
  assert_eq(a.get(1UL), 3U)
  assert_eq(a.length(), 2)
  assert_eq(@yrs.StateVector::decode_v2(a.encode_v2()), a)
  for
    scope in [
      @yrs.IndexScope::Root("root"),
      Nested({ client: 1UL, clock: 4U, }),
      Relative({ client: 2UL, clock: 7U, }),
    ] {
    for assoc in [@yrs.Assoc::Before, After] {
      let index = @yrs.StickyIndex(scope~, assoc~)
      assert_eq(@yrs.StickyIndex::decode_v2(index.encode_v2()), index)
    }
  }
}
