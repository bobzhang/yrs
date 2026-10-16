///|
/// Shared-type metadata used by update codecs. XmlHook and Undefined preserve
/// legacy/untyped descriptors even when no concrete collection handle exists.
pub(all) enum TypeRef {
  Array
  Map
  Text
  XmlElement(String)
  XmlFragment
  XmlHook
  XmlText
  WeakLink(LinkSource)
  SubDoc
  Undefined
} derive(Eq, Debug)

///|
pub fn TypeRef::kind(self : TypeRef) -> Byte {
  (match self {
    Array => 0
    Map => 1
    Text => 2
    XmlElement(_) => 3
    XmlFragment => 4
    XmlHook => 5
    XmlText => 6
    WeakLink(_) => 7
    SubDoc => 9
    Undefined => 15
  }).to_byte()
}

///|
/// Primitive values have no shared-type descriptor.
pub fn Out::type_ref(self : Out) -> TypeRef? {
  Some(
    match self {
      Value(_) => return None
      Array(_) => Array
      Map(_) => Map
      Text(_) => Text
      XmlElement(value) => XmlElement(value.tag())
      XmlFragment(_) => XmlFragment
      XmlText(_) => XmlText
      WeakLink(value) => WeakLink(value.source())
      Subdoc(_) => SubDoc
      UndefinedRef(value) =>
        match value.type_ref() {
          5 => XmlHook
          9 => SubDoc
          _ => Undefined
        }
    },
  )
}

///|
pub impl Encode for TypeRef with fn encode(self, encoder) {
  encoder.write_type_ref(self.kind())
  match self {
    XmlElement(name) => encoder.write_key(name)
    WeakLink(link) => {
      let single = link.is_single()
      let mut flags = if single { 0 } else { 1 }
      if link.start.assoc == After {
        flags = flags | 2
      }
      if link.end.assoc == After {
        flags = flags | 4
      }
      if !link.start.is_relative() {
        flags = flags | 8
      }
      if !link.end.is_relative() {
        flags = flags | 16
      }
      if link.start.is_root() || link.end.is_root() {
        flags = flags | 32
      }
      Write::write_u8(encoder, flags.to_byte())
      fn scope(index : StickyIndex) -> Unit {
        match index.scope {
          Root(name) => Write::write_string(encoder, name)
          Relative(id) | Nested(id) => {
            Write::write_var_uint(encoder, id.client)
            Write::write_var_uint(encoder, id.clock.to_uint64())
          }
        }
      }
      scope(link.start)
      if !single || !link.end.is_relative() {
        scope(link.end)
      }
    }
    _ => ()
  }
}

///|
pub impl Decode for TypeRef with fn decode(decoder) {
  match decoder.read_type_ref().to_int() {
    0 => Array
    1 => Map
    2 => Text
    3 => XmlElement(decoder.read_key())
    4 => XmlFragment
    5 => XmlHook
    6 => XmlText
    7 => {
      let flags = Read::read_u8(decoder).to_int()
      guard flags < 64 else { raise InvalidData("invalid weak link flags") }
      fn scope(unbounded : Bool) -> IndexScope raise DecodeError {
        if unbounded && (flags & 32) != 0 {
          Root(Read::read_string(decoder))
        } else {
          let id : Id = {
            client: Read::read_var_uint(decoder),
            clock: codec_clock(Read::read_var_uint(decoder)),
          }
          if unbounded {
            Nested(id)
          } else {
            Relative(id)
          }
        }
      }
      let start = scope((flags & 8) != 0)
      let end = if (flags & 16) != 0 {
        scope(true)
      } else if (flags & 1) == 0 {
        start
      } else {
        scope(false)
      }
      WeakLink(
        LinkSource(
          StickyIndex(
            scope=start,
            assoc=if (flags & 2) != 0 { After } else { Before },
          ),
          StickyIndex(
            scope=end,
            assoc=if (flags & 4) != 0 { After } else { Before },
          ),
        ),
      )
    }
    9 => SubDoc
    15 => Undefined
    _ => raise InvalidData("unsupported shared type reference")
  }
}

///|
pub extend TypeRef with Eq::{equal, not_equal}

///|
pub extend TypeRef with Debug::{to_repr}

///|
pub extend TypeRef with Encode::{encode, encode_v1, encode_v2}

///|
pub extend TypeRef with Decode::{decode, decode_v1, decode_v2}
