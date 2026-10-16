///|
test "lib0 values retain signed integers, floats, binary and Unicode" {
  let values : Array[@yrs.Any] = [
    Undefined,
    Null,
    Bool(false),
    Bool(true),
    Integer(-9223372036854775808L),
    Integer(9223372036854775807L),
    Integer(-65L),
    Integer(64L),
    Float(-0.0),
    Float(1.5),
    Float(1.1),
    String("中文🌍\ufeff"),
    Buffer(b"\x00\xff"),
    Array([Integer(1L), Null, String("a")]),
    Object([("name", String("MoonBit"))]),
  ]
  for value in values {
    let bytes = value.encode()
    assert_eq(@yrs.Any::decode(bytes), value)
    for len in 0..<bytes.length() {
      try @yrs.Any::decode(bytes[:len].to_owned()) catch {
        _ => ()
      } noraise {
        _ => fail("accepted truncated lib0 value")
      }
    }
  }
  assert_eq(@yrs.Any::decode(b"\x7d\x6a"), Integer(-42L))
  assert_eq(@yrs.Any::decode(b"\x7c\x3f\xc0\x00\x00"), Float(1.5))
}

///|
test "lib0 values compare objects without key order and numbers without representation" {
  let a : @yrs.Any = Object([("x", Integer(1L)), ("y", Array([Float(2.0)]))])
  let b : @yrs.Any = Object([("y", Array([Integer(2L)])), ("x", Float(1.0))])
  assert_eq(a, b)
  let duplicate : @yrs.Any = Object([
    ("x", Integer(0L)),
    ("x", Integer(1L)),
    ("y", Array([Integer(2L)])),
  ])
  assert_eq(duplicate, a)
  let precise : @yrs.Any = Integer(9007199254740993L)
  assert_false(precise == Float(9007199254740992.0))
}

///|
test "equivalent object attributes do not allocate redundant format markers" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert_with_attributes(0, "hello", [
    ("style", Object([("color", String("blue")), ("size", Integer(12L))])),
  ])
  let before = doc.state_vector().get(1UL)
  text.format(0, 5, [
    ("style", Object([("size", Float(12.0)), ("color", String("blue"))])),
  ])
  assert_eq(doc.state_vector().get(1UL), before)
}
