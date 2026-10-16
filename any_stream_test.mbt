///|
test "lib0 values compose with stream framing and preserve trailing bytes" {
  let values : Array[@yrs.Any] = [
    Undefined,
    Null,
    Bool(true),
    Bool(false),
    Integer(-9223372036854775808L),
    Integer(9223372036854775807L),
    Integer(-65L),
    Float(-0.0),
    Float(1.25),
    Float(1.1),
    String("Moon🌙"),
    Buffer(b"\x00\xff"),
    Object([("nested", Array([Integer(4L), Undefined, Null]))]),
  ]
  let writer = @yrs.ByteWriter()
  for value in values {
    writer.write_u8(42)
    value.encode_to(writer)
  }
  writer.write_u8(99)
  let reader = @yrs.Cursor(writer.to_bytes())
  for value in values {
    assert_eq(reader.read_u8(), 42)
    assert_eq(@yrs.Any::decode_from(reader), value)
    let single = @yrs.ByteWriter()
    value.encode_to(single)
    assert_eq(single.to_bytes(), value.encode())
  }
  assert_eq(reader.read_u8(), 99)
  assert_false(reader.has_content())
}

///|
test "generic lib0 decoder rejects compressed expansion and truncation" {
  let nested : @yrs.Any = Array([Array([Integer(1L), Integer(2L)])])
  for budget in [0, 1, 2, 3] {
    try
      @yrs.Any::decode_from(@yrs.Cursor(nested.encode()), max_values=budget)
    catch {
      _ => ()
    } noraise {
      _ => fail("exceeded value budget")
    }
  }
  assert_eq(
    @yrs.Any::decode_from(@yrs.Cursor(nested.encode()), max_values=4),
    nested,
  )
  let writer = @yrs.ByteWriter()
  writer.write_u8(117)
  writer.write_var_uint(0xffff_ffff_ffff_ffffUL)
  try @yrs.Any::decode_from(@yrs.Cursor(writer.to_bytes())) catch {
    _ => ()
  } noraise {
    _ => fail("accepted amplified array")
  }
  let value : @yrs.Any = Object([
    ("record", Array([Integer(9223372036854775807L), Buffer(b"payload")])),
  ])
  let encoded = value.encode()
  for end in 0..<encoded.length() {
    try @yrs.Any::decode_from(@yrs.Cursor(encoded[:end].to_owned())) catch {
      _ => ()
    } noraise {
      _ => fail("accepted truncated value")
    }
  }
}

///|
test "Any casts retain the rejected input and collection iteration preserves keys" {
  let value : @yrs.Any = Integer(4294967297L)
  let cast : Result[Int32, @yrs.Any] = value.cast()
  assert_eq(cast, Ok(1))
  let failed : Result[Bool, @yrs.Any] = value.cast()
  assert_eq(failed, Err(value))
  let object : @yrs.Any = Object([
    ("a", Integer(1L)),
    ("a", Integer(2L)),
    ("b", Null),
  ])
  let entries = Map::from_array(object.try_iter().unwrap().to_array())
  assert_eq(entries[Some("a")], Integer(2L))
  assert_eq(entries[Some("b")], Null)
  let array : @yrs.Any = Array([Null, Undefined])
  assert_eq(array.try_into_iter().unwrap().to_array(), [
    (None, Null),
    (None, Undefined),
  ])
  assert_true(value.try_iter() is None)
}
