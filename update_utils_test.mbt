///|
test "incomplete updates survive relay and duplicate delivery" {
  for v2 in [false, true] {
    let a = @yrs.Doc(client_id=1UL)
    let b = @yrs.Doc(client_id=2UL)
    let c = @yrs.Doc(client_id=3UL)
    let text = a.get_or_insert_text("note")
    text.insert(0, "A")
    let prefix = a.encode_state_as_update_v1()
    let known = a.state_vector()
    text.insert(1, "B")
    let suffix = a.encode_state_as_update_v1(remote=known)
    for _ in 0..<30 {
      b.apply_update_v1(suffix)
    }
    assert_eq(b.state_vector().get(1UL), 0U)
    assert_eq(b.get_or_insert_text("note").get_string(), "")
    let ahead = @yrs.StateVector(entries=[(1UL, 100U)])
    if v2 {
      c.apply_update_v2(b.encode_state_as_update_v2(remote=ahead))
    } else {
      c.apply_update_v1(b.encode_state_as_update_v1(remote=ahead))
    }
    c.apply_update_v1(prefix)
    assert_eq(c.get_or_insert_text("note").get_string(), "AB")
    assert_eq(c.state_vector().get(1UL), 2U)
  }
}

///|
test "stateless merge preserves gaps and early deletions" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("note")
  text.insert(0, "A")
  let first = a.encode_state_as_update_v1()
  let after_first = a.state_vector()
  text.insert(1, "B")
  let second = a.encode_state_as_update_v1(remote=after_first)
  let after_second = a.state_vector()
  text.insert(2, "C")
  let third = a.encode_state_as_update_v1(remote=after_second)
  let merged = @yrs.merge_updates_v1([third, first, third])
  let state = @yrs.StateVector::decode_v1(
    @yrs.encode_state_vector_from_update_v1(merged),
  )
  assert_eq(state.get(1UL), 1U)
  let receiver = @yrs.Doc(client_id=2UL)
  receiver.apply_update_v1(merged)
  assert_eq(receiver.get_or_insert_text("note").get_string(), "A")
  receiver.apply_update_v1(second)
  assert_eq(receiver.get_or_insert_text("note").get_string(), "ABC")
  text.remove_range(1, 1)
  let deletion = a.encode_state_as_update_v1(remote=a.state_vector())
  let all = @yrs.merge_updates_v2([
    @yrs.convert_update_v1_to_v2(merged),
    @yrs.convert_update_v1_to_v2(second),
    @yrs.convert_update_v1_to_v2(deletion),
  ])
  let other = @yrs.Doc(client_id=3UL)
  other.apply_update_v2(all)
  assert_eq(other.get_or_insert_text("note").get_string(), "AC")
  assert_eq(
    @yrs.StateVector::decode_v1(@yrs.encode_state_vector_from_update_v2(all)).get(
      1UL,
    ),
    3U,
  )
  let tail = @yrs.diff_updates_v2(all, after_first.encode_v1())
  let restored = @yrs.Doc(client_id=4UL)
  restored.apply_update_v1(first)
  restored.apply_update_v2(tail)
  assert_eq(restored.get_or_insert_text("note").get_string(), "AC")
}

///|
test "independent blocks integrate past gaps and missing ranges fill in the middle" {
  let base = @yrs.Doc(client_id=100UL)
  base.get_or_insert_text("note").insert(0, "PQ")
  let source = @yrs.Doc(client_id=1UL)
  source.apply_update_v1(base.encode_state_as_update_v1())
  let text = source.get_or_insert_text("note")
  let updates : Array[Bytes] = []
  for (index, value) in [(1, "a"), (2, "b"), (1, "c"), (5, "d")] {
    let before = source.state_vector()
    text.insert(index, value)
    updates.push(source.encode_state_as_update_v1(remote=before))
  }
  let receiver = @yrs.Doc(client_id=2UL)
  receiver.apply_update_v1(base.encode_state_as_update_v1())
  receiver.apply_update_v1(updates[0])
  receiver.apply_update_v1(updates[3])
  assert_eq(receiver.get_or_insert_text("note").get_string(), "PaQd")
  assert_eq(receiver.state_vector().get(1UL), 1U)
  assert_true(receiver.has_missing_updates())
  receiver.apply_update_v1(updates[2])
  assert_eq(receiver.get_or_insert_text("note").get_string(), "PcaQd")
  assert_eq(receiver.state_vector().get(1UL), 1U)
  receiver.apply_update_v1(updates[1])
  assert_eq(receiver.get_or_insert_text("note").get_string(), "PcabQd")
  assert_eq(receiver.state_vector().get(1UL), 4U)
  assert_false(receiver.has_missing_updates())
  receiver.apply_update_v1(source.encode_state_as_update_v1())
  assert_eq(receiver.get_or_insert_text("note").get_string(), "PcabQd")
  let delayed = @yrs.Doc(client_id=3UL)
  delayed.apply_update_v1(base.encode_state_as_update_v1())
  delayed.apply_update_v1(updates[3])
  let before = source.state_vector()
  text.remove_range(0, text.length())
  delayed.apply_update_v1(source.encode_state_as_update_v1(remote=before))
  for update in updates {
    delayed.apply_update_v1(update)
  }
  assert_eq(delayed.get_or_insert_text("note").get_string(), "")
  assert_false(delayed.has_missing_updates())
}

///|
test "overflowing skip blocks are rejected before any document mutation" {
  let doc = @yrs.Doc(client_id=1UL)
  let update = b"\x01\x02\x02\x00\x04\x01\x04note\x01A\x0a\xff\xff\xff\xff\x0f\x00"
  try doc.apply_update_v1(update) catch {
    InvalidData(message) => assert_eq(message, "clock overflow")
  } noraise {
    _ => fail("accepted an overflowing skip")
  }
  assert_eq(doc.state_vector().get(2UL), 0U)
  assert_eq(doc.get_or_insert_text("note").get_string(), "")
}

///|
test "an early suffix cut inside a surrogate pair cannot replace the original character" {
  // Synthetic remote clock 1 bisects the two-clock scalar. Rust, unlike Yjs
  // 13.6.27, preserves the original full item when it arrives after this suffix.
  let source = @yrs.Doc(client_id=1UL)
  source.get_or_insert_text("text").insert(0, "🌙")
  let full = source.encode_state_as_update_v1()
  let remote = @yrs.StateVector(entries=[(1UL, 1U)]).encode_v1()
  let suffix = @yrs.diff_updates_v1(full, remote)
  for v2 in [false, true] {
    let receiver = @yrs.Doc(client_id=2UL)
    if v2 {
      receiver.apply_update_v2(@yrs.convert_update_v1_to_v2(suffix))
      receiver.apply_update_v2(@yrs.convert_update_v1_to_v2(full))
    } else {
      receiver.apply_update_v1(suffix)
      receiver.apply_update_v1(full)
    }
    assert_eq(receiver.get_or_insert_text("text").get_string(), "🌙")
    assert_eq(receiver.state_vector().get(1UL), 2U)
    assert_false(receiver.has_pending_updates())
  }
}
