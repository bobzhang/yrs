///|
test "concurrent insertion ordering and idempotent updates" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let ta = a.get_or_insert_text("note")
  let tb = b.get_or_insert_text("note")
  ta.insert(0, "Hello")
  b.apply_update_v1(a.encode_state_as_update_v1())
  ta.insert(5, " Moon")
  tb.insert(5, " Rust")
  let ua = a.encode_state_as_update_v1(remote=b.state_vector())
  let ub = b.encode_state_as_update_v1(remote=a.state_vector())
  a.apply_update_v1(ub)
  b.apply_update_v1(ua)
  a.apply_update_v1(ub)
  assert_eq(ta.get_string(), "Hello Moon Rust")
  assert_eq(tb.get_string(), ta.get_string())
  ta.remove_range(2, 7)
  b.apply_update_v1(a.encode_state_as_update_v1(remote=b.state_vector()))
  assert_eq(tb.get_string(), "Hen Rust")
}

///|
test "pending insertion and deletion resolve after dependencies arrive" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("x")
  text.insert(0, "abc")
  let first = a.encode_state_as_update_v1()
  let known = a.state_vector()
  text.insert(1, "Z")
  let second = a.encode_state_as_update_v1(remote=known)
  let known = a.state_vector()
  text.remove_range(0, 2)
  let third = a.encode_state_as_update_v1(remote=known)
  let b = @yrs.Doc(client_id=2UL)
  b.apply_update_v1(third)
  b.apply_update_v1(second)
  assert_eq(b.pending_items(), 1)
  b.apply_update_v1(first)
  assert_eq(b.get_or_insert_text("x").get_string(), "bc")
  assert_eq(b.pending_items(), 0)
}

///|
test "Unicode positions, partial blocks, and invalid update atomicity" {
  let a = @yrs.Doc(client_id=1UL)
  let text = a.get_or_insert_text("unicode")
  text.insert(0, "A🌍中文\ufeffZ")
  assert_eq(text.length(), 7)
  text.insert(3, "!")
  text.remove_range(1, 2)
  assert_eq(text.get_string(), "A!中文\ufeffZ")
  let update = a.encode_state_as_update_v1()
  for len in 0..<update.length() {
    let b = @yrs.Doc(client_id=2UL)
    try b.apply_update_v1(update[:len].to_owned()) catch {
      _ => assert_eq(b.state_vector().entries().length(), 0)
    } noraise {
      _ => fail("accepted truncated update")
    }
  }
  let b = @yrs.Doc(client_id=2UL)
  b.apply_update_v1(update)
  assert_eq(b.get_or_insert_text("unicode").get_string(), text.get_string())
}
