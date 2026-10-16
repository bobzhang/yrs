///|
pub impl Encode for Assoc with fn encode(self, encoder) {
  Write::write_var_int(encoder, if self == Before { -1L } else { 0L })
}

///|
pub impl Decode for Assoc with fn decode(decoder) {
  let value = Read::read_var_int(decoder)
  guard value >= -128L && value <= 127L else {
    raise InvalidData("invalid association")
  }
  if value < 0L {
    Before
  } else {
    After
  }
}

///|
pub impl Encode for IndexScope with fn encode(self, encoder) {
  match self {
    Relative(id) | Nested(id) => {
      Write::write_var_uint(
        encoder,
        if self is Relative(_) {
          0UL
        } else {
          2UL
        },
      )
      Write::write_var_uint(encoder, id.client)
      Write::write_var_uint(encoder, id.clock.to_uint64())
    }
    Root(name) => {
      Write::write_var_uint(encoder, 1UL)
      Write::write_string(encoder, name)
    }
  }
}

///|
pub impl Decode for IndexScope with fn decode(decoder) {
  match Read::read_var_uint(decoder) {
    0UL =>
      Relative({
        client: Read::read_var_uint(decoder),
        clock: codec_clock(Read::read_var_uint(decoder)),
      })
    1UL => Root(Read::read_string(decoder))
    2UL =>
      Nested({
        client: Read::read_var_uint(decoder),
        clock: codec_clock(Read::read_var_uint(decoder)),
      })
    _ => raise InvalidData("invalid sticky index scope")
  }
}

///|
pub impl Encode for StickyIndex with fn encode(self, encoder) {
  self.scope.encode(encoder)
  self.assoc.encode(encoder)
}

///|
pub impl Decode for StickyIndex with fn decode(decoder) {
  let scope = IndexScope::decode(decoder)
  let assoc = Assoc::decode(decoder)
  StickyIndex(scope~, assoc~)
}

///|
pub extend Assoc with Encode::{encode, encode_v1, encode_v2}

///|
pub extend Assoc with Decode::{decode, decode_v1, decode_v2}

///|
pub extend IndexScope with Encode::{encode, encode_v1, encode_v2}

///|
pub extend IndexScope with Decode::{decode, decode_v1, decode_v2}

///|
pub extend StickyIndex with Encode::{encode}

///|
pub extend StickyIndex with Decode::{decode}
