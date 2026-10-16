///|
test "generic cursor codecs compose all scopes and associations" {
  let id : @yrs.Id = { client: 0x1f_ffff_ffff_ffffUL, clock: 0xffffffffU, }
  for scope in [@yrs.IndexScope::Root("\u{feff}🌙"), Relative(id), Nested(id)] {
    for assoc in [@yrs.Assoc::Before, After] {
      let cursor = @yrs.StickyIndex(scope~, assoc~)
      for v2 in [false, true] {
        let encoded = if v2 {
          @yrs.Encode::encode_v2(cursor)
        } else {
          @yrs.Encode::encode_v1(cursor)
        }
        assert_eq(
          encoded,
          if v2 {
            cursor.encode_v2()
          } else {
            cursor.encode_v1()
          },
        )
        let decoded : @yrs.StickyIndex = if v2 {
          @yrs.Decode::decode_v2(encoded)
        } else {
          @yrs.Decode::decode_v1(encoded)
        }
        assert_eq(decoded, cursor)
      }
    }
  }
  for byte in [0, 1, 63, 64, 65, 127] {
    let assoc = @yrs.Assoc::decode_v1(Bytes::from_array([byte.to_byte()]))
    assert_eq(assoc, if byte > 64 { @yrs.Assoc::Before } else { After })
  }
  try @yrs.Assoc::decode_v1(b"\x80\x02") catch {
    _ => ()
  } noraise {
    _ => fail("accepted association outside i8")
  }
  try @yrs.IndexScope::decode_v1(b"\x03") catch {
    _ => ()
  } noraise {
    _ => fail("accepted unknown scope")
  }
}
