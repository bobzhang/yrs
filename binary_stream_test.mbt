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
  requests : Array[Int32]
  mut chunk : Int32
  mut offset : Int32
}

///|
impl @yrs.Read for ChunkSource with fn read_exact(self, length) {
  self.requests.push(length)
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
test "fixed-width writes emit one correctly ordered chunk per value" {
  let sink = ChunkSink::{ chunks: [], }
  @yrs.Write::write_u16(sink, 0xcafe)
  @yrs.Write::write_u32(sink, 0x89abcdefU)
  @yrs.Write::write_u32_be(sink, 0x89abcdefU)
  @yrs.Write::write_u64(sink, 0x0123456789abcdefUL)
  @yrs.Write::write_i64(sink, -9223372036854775808L)
  @yrs.Write::write_f32(sink, 1.5)
  @yrs.Write::write_f64(sink, -0.0)
  assert_eq(sink.chunks, [
    b"\xfe\xca", b"\xef\xcd\xab\x89", b"\x89\xab\xcd\xef", b"\x01\x23\x45\x67\x89\xab\xcd\xef",
    b"\x80\x00\x00\x00\x00\x00\x00\x00", b"\x3f\xc0\x00\x00", b"\x80\x00\x00\x00\x00\x00\x00\x00",
  ])
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
  let reader = ChunkSource::{
    chunks: sink.chunks,
    requests: [],
    chunk: 0,
    offset: 0,
  }
  assert_eq(@yrs.Read::read_u16(reader), 0xcafe)
  assert_eq(@yrs.Read::read_u32(reader), 0x89abcdefU)
  assert_eq(@yrs.Read::read_u32_be(reader), 0x89abcdefU)
  assert_eq(reader.requests, [2, 4, 4])
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

///|
test "fixed-width reads preserve unsigned boundaries and byte order" {
  for
    (bytes, expected) in [
      (b"\x00\x00", 0U),
      (b"\xff\x7f", 0x7fffU),
      (b"\x00\x80", 0x8000U),
      (b"\xff\xff", 0xffffU),
    ] {
    assert_eq(@yrs.Cursor(bytes).read_u16().to_uint(), expected)
  }
  for
    (bytes, little, big) in [
      (b"\x00\x00\x00\x00", 0U, 0U),
      (b"\xff\xff\xff\x7f", 0x7fffffffU, 0xffffff7fU),
      (b"\x00\x00\x00\x80", 0x80000000U, 0x00000080U),
      (b"\x80\x00\x00\x00", 0x00000080U, 0x80000000U),
      (b"\xff\xff\xff\xff", 0xffffffffU, 0xffffffffU),
    ] {
    assert_eq(@yrs.Cursor(bytes).read_u32(), little)
    assert_eq(@yrs.Cursor(bytes).read_u32_be(), big)
  }
}

///|
test "truncated fixed-width reads preserve cursor position" {
  for (width, big_endian) in [(2, false), (4, false), (4, true)] {
    for length in 0..<width {
      let reader = @yrs.Cursor(Bytes::make(length, b'\xff'))
      try {
        if width == 2 {
          reader.read_u16() |> ignore
        } else if big_endian {
          reader.read_u32_be() |> ignore
        } else {
          reader.read_u32() |> ignore
        }
      } catch {
        @yrs.InvalidData(message) => assert_eq(message, "truncated binary")
      } noraise {
        _ => fail("accepted truncated integer")
      }
      assert_eq(reader.position(), 0)
      assert_eq(reader.remaining(), length)
    }
  }
}
