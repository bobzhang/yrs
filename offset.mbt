///|
/// User-facing text offsets. CRDT item clocks always count UTF-16 code units.
pub(all) enum OffsetKind {
  Utf16
  Bytes
} derive(Eq, Debug)

///|
pub extend OffsetKind with Eq::{equal, not_equal}

///|
pub extend OffsetKind with Debug::{to_repr}

///|
pub fn Doc::offset_kind(self : Doc) -> OffsetKind {
  if self.wire_encoding == 1 {
    Bytes
  } else {
    Utf16
  }
}

///|
fn utf8_width(c : Char) -> Int32 {
  let n = c.to_int()
  if n < 0x80 {
    1
  } else if n < 0x800 {
    2
  } else if n < 0x10000 {
    3
  } else {
    4
  }
}

///|
fn Content::offset_length(self : Content, doc : Doc) -> Int32 {
  if doc.wire_encoding == 1 && self is Characters(text) {
    text.utf8_length
  } else {
    self.visible_length()
  }
}

///|
fn Content::block_offset(self : Content, offset : Int32, doc : Doc) -> Int32 {
  if doc.wire_encoding == 1 && self is Characters(text) {
    let mut remaining = offset
    let mut clock = 0
    for c in text {
      if remaining == 0 {
        break
      }
      remaining -= utf8_width(c)
      guard remaining >= 0 else {
        abort("text offset is not a UTF-8 character boundary")
      }
      clock += if c.to_int() > 0xffff { 2 } else { 1 }
    }
    guard remaining == 0 else { abort("text offset out of bounds") }
    clock
  } else {
    offset
  }
}
