///|
test "state vector preserves 64 bit client IDs and 32 bit clocks" {
  let state = @yrs.StateVector(entries=[
    (0xffff_ffff_ffff_ffffUL, 0xffff_ffffU),
    (1UL, 128U),
  ])
  let bytes = state.encode_v1()
  let decoded = @yrs.StateVector::decode_v1(bytes)
  assert_eq(decoded.entries(), state.entries())
  assert_eq(decoded.get(42UL), 0U)
  for len in 0..<bytes.length() {
    try @yrs.StateVector::decode_v1(bytes[:len].to_owned()) catch {
      _ => ()
    } noraise {
      _ => fail("accepted a truncated state vector")
    }
  }
}

///|
test "state vector rejects overflow and forged length" {
  let malformed : Array[Bytes] = [
    b"\xff\xff\xff\x7a", b"\x01\x01\xff\xff\xff\xff\x10", b"\x01\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02\x00",
  ]
  for bytes in malformed {
    try @yrs.StateVector::decode_v1(bytes) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed vector")
    }
  }
}
