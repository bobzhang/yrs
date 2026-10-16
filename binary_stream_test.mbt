///|
struct ChunkSink {
  chunks : Array[Bytes]
}

///|
impl @yrs.Write for ChunkSink with fn write_all(self, bytes) {
  self.chunks.push(bytes)
}

///|
struct ChunkSource {
  chunks : Array[Bytes]
  mut chunk : Int32
  mut offset : Int32
}

///|
impl @yrs.Read for ChunkSource with fn read_exact(self, length) {
  let bytes = []
  for _ in 0..<length {
    while self.chunk < self.chunks.length() &&
          self.offset == self.chunks[self.chunk].length() {
      self.chunk += 1
      self.offset = 0
    }
    guard self.chunk < self.chunks.length() else {
      raise @yrs.DecodeError::InvalidData("end of chunks")
    }
    bytes.push(self.chunks[self.chunk][self.offset])
    self.offset += 1
  }
  Bytes::from_array(bytes)
}

///|
test "application streams inherit lib0 defaults across chunk boundaries" {
  let sink = ChunkSink::{ chunks: [], }
  @yrs.Write::write_u16(sink, 0xcafe)
  @yrs.Write::write_u32(sink, 0x89abcdefU)
  @yrs.Write::write_u32_be(sink, 0x89abcdefU)
  @yrs.Write::write_var_uint(sink, 0xffff_ffff_ffff_ffffUL)
  @yrs.Write::write_var_int(sink, -9223372036854775808L)
  @yrs.Write::write_var_signed(sink, (0L, true))
  @yrs.Write::write_string(sink, "\u{feff}Moon🌙\u{0}")
  @yrs.Write::write_f64(sink, -0.0)
  @yrs.Write::write_f32(sink, 1.5)
  let nested : @yrs.Any = Object([
    ("array", Array([Null, Integer(9223372036854775807L), String("🌙")])),
  ])
  nested.encode_to(sink)
  let reader = ChunkSource::{ chunks: sink.chunks, chunk: 0, offset: 0, }
  assert_eq(@yrs.Read::read_u16(reader), 0xcafe)
  assert_eq(@yrs.Read::read_u32(reader), 0x89abcdefU)
  assert_eq(@yrs.Read::read_u32_be(reader), 0x89abcdefU)
  assert_eq(@yrs.Read::read_var_uint(reader), 0xffff_ffff_ffff_ffffUL)
  assert_eq(@yrs.Read::read_var_int(reader), -9223372036854775808L)
  assert_eq(@yrs.Read::read_var_signed(reader), (0L, true))
  assert_eq(@yrs.Read::read_string(reader), "\u{feff}Moon🌙\u{0}")
  assert_eq(
    @yrs.Read::read_f64(reader).reinterpret_as_uint64(),
    0x8000_0000_0000_0000UL,
  )
  assert_eq(@yrs.Read::read_f32(reader), 1.5)
  assert_eq(@yrs.Any::decode_from(reader), nested)
}

///|
test "stream snapshots and failed fixed-width reads preserve ownership and position" {
  let writer = @yrs.ByteWriter()
  writer.write_u8(1)
  let snapshot = writer.to_bytes()
  writer.write_u8(2)
  assert_eq(snapshot, b"\x01")
  let reader = @yrs.Cursor(snapshot)
  try reader.read_u32() catch {
    _ => ()
  } noraise {
    _ => fail("accepted truncated integer")
  }
  assert_eq(reader.position(), 0)
  assert_eq(reader.remaining(), 1)
  assert_true(reader.has_content())
  assert_eq(reader.read_u8(), 1)
  assert_false(reader.has_content())
  assert_eq(reader.read_exact(0), b"")
  try reader.read_exact(-1) catch {
    _ => ()
  } noraise {
    _ => fail("accepted negative length")
  }
}

///|
test "lib0 stream rejects malformed integers lengths and Unicode" {
  for bytes in [b"\x80", b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02"] {
    try @yrs.Cursor(bytes).read_var_uint() catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid uint")
    }
  }
  for
    bytes in [
      b"\x80", b"\xbf\xff\xff\xff\xff\xff\xff\xff\xff\x02", b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x03",
    ] {
    try @yrs.Cursor(bytes).read_var_signed() catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid int")
    }
  }
  for bytes in [b"\x02x", b"\x01\xff", b"\xff\xff\xff\xff\x0f"] {
    try @yrs.Cursor(bytes).read_string() catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid string")
    }
  }
}
