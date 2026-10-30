///|
test "wire string views preserve errors, offsets, and framed buffers" {
  for
    (bytes, offset) in [
      (b"", 0),
      (b"\x80", 1),
      (b"\x03ab", 1),
      (b"\x01\xff", 2),
      (b"\x02\xc2", 1),
      (b"\x02\xc2A", 3),
    ] {
    let reader : Reader = { bytes, offset: 0, }
    try reader.string() catch {
      InvalidData(message) => assert_eq(message, "invalid UTF-8")
    } noraise {
      _ => fail("accepted invalid input")
    }
    assert_eq(reader.offset, offset)
  }
  let reader : Reader = {
    bytes: b"\x00\x03\xef\xbb\xbf\x04\xf0\x9f\x8c\x99\x63",
    offset: 0,
  }
  assert_eq(reader.string(), "")
  assert_eq(reader.string(), "\u{feff}")
  assert_eq(reader.string(), "🌙")
  assert_eq(reader.offset, 10)
  assert_eq(reader.byte(), 99)
  reader.finish()
  let buffers : Reader = { bytes: b"\x02hi\x01x", offset: 0, }
  let first = buffers.buffer()
  assert_eq(buffers.buffer(), b"x")
  assert_eq(first, b"hi")
  buffers.finish()
}
