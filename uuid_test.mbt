///|
test "UUID formatter uses network byte order and masks version and variant" {
  assert_eq(
    @yrs.uuid_v4_from(
      b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
    "00000000-0000-4000-8000-000000000000",
  )
  assert_eq(
    @yrs.uuid_v4_from(
      b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff",
    ),
    "ffffffff-ffff-4fff-bfff-ffffffffffff",
  )
  let source = b"\x01\x23\x45\x67\x89\xab\xcd\xef\xfe\xdc\xba\x98\x76\x54\x32\x10"
  let mut calls = 0
  let uuid = @yrs.uuid_v4(fn() {
    calls += 1
    source
  })
  assert_eq(calls, 1)
  assert_eq(uuid, "01234567-89ab-4def-bedc-ba9876543210")
  assert_eq(source[6], b'\xcd')
  assert_eq(source[8], b'\xfe')
}
