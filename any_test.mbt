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
