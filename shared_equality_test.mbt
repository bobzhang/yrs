///|
test "shared values compare logical identities across replicas" {
  let a = @yrs.Doc(client_id=1UL, guid="same")
  let b = @yrs.Doc(client_id=2UL, guid="same")
  let different = @yrs.Doc(client_id=3UL, guid="different")
  assert_true(a == b)
  assert_false(a.ptr_eq(b))
  assert_false(a == different)
  let map = a.get_or_insert_map("root")
  let source = a.get_or_insert_text("source")
  source.insert(0, "quote")
  let inputs : Array[@yrs.In] = [
    Text([]),
    Array([]),
    Map([]),
    XmlFragment([]),
    XmlText([], []),
    XmlElement("p", [], []),
    WeakLink(source.quote(Unbounded, Unbounded)),
    Subdoc(@yrs.Doc(client_id=4UL, guid="child")),
  ]
  let values = inputs.mapi(fn(i, input) {
    map.insert_input(i.to_string(), input)
  })
  b.apply_update_v2(a.encode_state_as_update_v2())
  let remote = b.get_or_insert_map("root")
  for i, value in values {
    assert_true(value == remote.get(i.to_string()).unwrap())
    for j, other in values {
      assert_eq(value == other, i == j)
    }
  }
  assert_true(source == different.get_or_insert_text("source"))
  assert_false(source == different.get_or_insert_text("another"))
  assert_true(@yrs.Out::Value(Integer(1L)) == @yrs.Out::Value(Float(1.0)))
}

///|
test "undefined branch outputs retain instance equality until typed" {
  let source = @yrs.Doc(client_id=1UL)
  source.get_or_insert_text("unknown").insert(0, "value")
  let a = @yrs.Doc(client_id=2UL)
  let b = @yrs.Doc(client_id=3UL)
  let update = source.encode_state_as_update_v1()
  a.apply_update_v1(update)
  b.apply_update_v1(update)
  let first = a.get("unknown").unwrap()
  let again = a.get("unknown").unwrap()
  let peer = b.get("unknown").unwrap()
  guard first is UndefinedRef(_) else { fail("root should remain untyped") }
  assert_true(first == again)
  assert_false(first == peer)
}
