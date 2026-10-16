///|
/// Format 16 bytes in network byte order as a lowercase version-4 UUID.
/// The version and variant bits are set as in Yrs uuid_v4_from(u128).
/// Requires exactly 16 bytes; the input is not modified.
pub fn uuid_v4_from(value : Bytes) -> String {
  guard value.length() == 16 else {
    abort("UUID entropy must contain 16 bytes")
  }
  let result = StringBuilder()
  for i, byte in value {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      result.write_string("-")
    }
    let byte = if i == 6 {
      ((byte.to_int() & 15) | 64).to_byte()
    } else if i == 8 {
      ((byte.to_int() & 63) | 128).to_byte()
    } else {
      byte
    }
    result.write_string(byte.to_hex())
  }
  result.to_string()
}

///|
/// Obtain a version-4 UUID using 16 fresh bytes from the host's entropy source.
/// The callback is called once. Entropy is injected so every backend has the
/// same API without silently falling back to a deterministic pseudo-random seed.
pub fn uuid_v4(entropy : () -> Bytes) -> String {
  uuid_v4_from(entropy())
}
