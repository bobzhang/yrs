///|
struct AppEnvelope {
  name : String
  parent : @yrs.Id
  clock : @yrs.StateVector
  removed : @yrs.IdSet
  value : @yrs.Any
}

///|
impl @yrs.Encode for AppEnvelope with fn encode(self, encoder) {
  @yrs.Write::write_string(encoder, self.name)
  encoder.write_left_id(self.parent)
  self.clock.encode(encoder)
  self.removed.encode(encoder)
  encoder.write_any(self.value)
}

///|
impl @yrs.Decode for AppEnvelope with fn decode(decoder) {
  let name = @yrs.Read::read_string(decoder)
  let parent = decoder.read_left_id()
  let clock = @yrs.StateVector::decode(decoder)
  let removed = @yrs.IdSet::decode(decoder)
  let value = decoder.read_any()
  { name, parent, clock, removed, value, }
}

///|
test "application codec composes shared values across both wire versions" {
  let envelope = AppEnvelope::{
    name: "document🌙",
    parent: { client: 42UL, clock: 17U, },
    clock: @yrs.StateVector(entries=[(42UL, 100U), (51UL, 12U)]),
    removed: @yrs.IdSet(ranges=[(42UL, 1U, 3U), (42UL, 7U, 12U), (51UL, 9U, 9U)]),
    value: Buffer(b"\x00\xff"),
  }
  for v2 in [false, true] {
    let bytes = if v2 {
      @yrs.Encode::encode_v2(envelope)
    } else {
      @yrs.Encode::encode_v1(envelope)
    }
    let decoded : AppEnvelope = if v2 {
      @yrs.Decode::decode_v2(bytes)
    } else {
      @yrs.Decode::decode_v1(bytes)
    }
    assert_eq(decoded.name, envelope.name)
    assert_eq(decoded.parent, envelope.parent)
    assert_eq(decoded.clock.entries(), envelope.clock.entries())
    assert_eq(decoded.removed.encode_v1(), envelope.removed.encode_v1())
    assert_true(decoded.value == envelope.value)
    let snap = @yrs.Snapshot(state=envelope.clock, delete_set=envelope.removed)
    let encoded = if v2 {
      @yrs.Encode::encode_v2(snap)
    } else {
      @yrs.Encode::encode_v1(snap)
    }
    assert_eq(encoded, if v2 { snap.encode_v2() } else { snap.encode_v1() })
    let restored : @yrs.Snapshot = if v2 {
      @yrs.Decode::decode_v2(encoded)
    } else {
      @yrs.Decode::decode_v1(encoded)
    }
    assert_eq(restored.encode_v1(), snap.encode_v1())
  }
}

///|
test "v2 raw writer framing and non-consuming tail match pinned Rust" {
  let encoder = @yrs.EncoderV2()
  encoder.write_all(b"ab")
  encoder.write_buf(b"cd")
  encoder.write_u32(0x01020304U)
  let saved = encoder.to_bytes()
  encoder.write_u8(123)
  let decoder = @yrs.DecoderV2(saved)
  let expected = b"\x02ab\x02\x02cd\x04\x04\x03\x02\x01"
  assert_eq(decoder.read_to_end(), expected)
  assert_eq(decoder.read_to_end(), expected)
  assert_eq(decoder.read_buf(), b"ab")
  assert_eq(decoder.read_u8(), 2)
  assert_eq(decoder.read_buf(), b"cd")
  assert_eq(decoder.read_u8(), 4)
  assert_eq(decoder.read_u32(), 0x01020304U)
  assert_eq(decoder.read_to_end(), b"")
}

///|
test "v2 deletion delta overflow fails without wrapping clocks" {
  let encoder = @yrs.EncoderV2()
  encoder.write_ds_clock(0xffffffffU)
  encoder.write_var_uint(1UL)
  let decoder = @yrs.DecoderV2(encoder.to_bytes())
  assert_eq(decoder.read_ds_clock(), 0xffffffffU)
  try decoder.read_ds_clock() catch {
    _ => ()
  } noraise {
    _ => fail("wrapped deletion clock")
  }
  let decoder = @yrs.DecoderV2(encoder.to_bytes())
  assert_eq(decoder.read_ds_clock(), 0xffffffffU)
  try decoder.read_ds_len() catch {
    _ => ()
  } noraise {
    _ => fail("wrapped deletion range")
  }
}
