///|
fn LinkSource::write(self : LinkSource, writer : UpdateWriter) -> Unit {
  let single = self.is_single()
  let mut flags = if single { 0 } else { 1 }
  if self.start.assoc == After {
    flags = flags | 2
  }
  if self.end.assoc == After {
    flags = flags | 4
  }
  if !self.start.is_relative() {
    flags = flags | 8
  }
  if !self.end.is_relative() {
    flags = flags | 16
  }
  if self.start.is_root() || self.end.is_root() {
    flags = flags | 32
  }
  writer.raw.byte(flags)
  fn scope(index : StickyIndex) -> Unit {
    match index.scope {
      Relative(id) | Nested(id) => writer.raw.id(id)
      Root(name) => writer.string(name)
    }
  }
  scope(self.start)
  if !single || !self.end.is_relative() {
    scope(self.end)
  }
}

///|
fn LinkSource::read(reader : UpdateReader) -> LinkSource raise DecodeError {
  let flags = reader.raw.byte()
  guard flags < 64 else { raise InvalidData("invalid weak link flags") }
  fn scope(unbounded : Bool) -> IndexScope raise DecodeError {
    if unbounded {
      if (flags & 32) != 0 {
        Root(reader.string())
      } else {
        Nested(reader.raw.id())
      }
    } else {
      Relative(reader.raw.id())
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
  LinkSource(
    StickyIndex(
      scope=start,
      assoc=if (flags & 2) != 0 { After } else { Before },
    ),
    StickyIndex(scope=end, assoc=if (flags & 4) != 0 { After } else { Before }),
  )
}
