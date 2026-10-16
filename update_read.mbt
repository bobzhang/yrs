///|
fn read_update_fields(
  reader : UpdateReader,
) -> (Array[RawItem], IdSet, Bool) raise DecodeError {
  fn id(column : Int32) -> Id raise DecodeError {
    { client: reader.field(1), clock: codec_clock(reader.field(column)), }
  }
  fn length_count() -> Int32 raise DecodeError {
    let n = codec_clock(reader.field(8))
    guard n.to_uint64() <= reader.budget.to_uint64() else {
      raise InvalidData("update exceeds decode item budget")
    }
    reader.budget -= n.reinterpret_as_int()
    n.reinterpret_as_int()
  }
  let items = []
  let clients = reader.count()
  for _ in 0..<clients {
    let count = reader.count()
    let client = reader.field(1)
    let mut clock = reader.raw.clock()
    for _ in 0..<count {
      let info = codec_byte(reader.field(4)).to_int()
      let origin = if (info & 128) != 0 { Some(id(2)) } else { None }
      let right_origin = if (info & 64) != 0 { Some(id(3)) } else { None }
      let kind = info & 31
      if kind == 10 {
        let length = reader.raw.clock()
        guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
          raise InvalidData("clock overflow")
        }
        clock += length
        continue
      }
      let parent : Parent? = if kind != 0 &&
        kind != 10 &&
        origin is None &&
        right_origin is None {
        match reader.field(6) {
          1UL => Some(Root(reader.string()))
          0UL => Some(Nested(id(2)))
          _ => raise InvalidData("invalid parent discriminator")
        }
      } else {
        None
      }
      let parent_sub = if parent is Some(_) && (info & 32) != 0 {
        Some(reader.string())
      } else {
        None
      }
      // Deleted runs carry no per-clock payload. Keep each internal block within
      // signed indexing bounds while accepting the full unsigned wire range.
      if kind == 0 || kind == 1 {
        let length = codec_clock(reader.field(8))
        guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
          raise InvalidData("clock overflow")
        }
        let end = clock + length
        let mut left = origin
        while clock < end {
          let count = (end - clock).min(0x7fff_ffffU)
          items.push({
            id: { client, clock, },
            origin: if kind == 0 {
              None
            } else {
              left
            },
            right_origin,
            parent,
            parent_sub,
            content: if kind == 0 {
              Garbage(count.reinterpret_as_int())
            } else {
              Deleted(count.reinterpret_as_int())
            },
          })
          clock += count
          left = Some({ client, clock: clock - 1U, })
        }
        continue
      }
      let content = match kind {
        2 => {
          let values = []
          let count = length_count()
          for _ in 0..<count {
            let value = reader.string()
            values.push(
              if value == "undefined" {
                Any::Undefined
              } else {
                Any::from_json(
                  @json.parse(value) catch {
                    _ => raise InvalidData("invalid legacy JSON")
                  },
                )
              },
            )
          }
          LegacyJson(ReadOnlyArray::from_array(values[:]))
        }
        9 => Subdocument(decode_subdocument(reader.string(), reader.raw.any()))
        5 => Embed(reader.json())
        6 => Format(reader.key(), reader.json())
        7 =>
          Shared(
            match codec_byte(reader.field(7)).to_int() {
              0 => SharedArray
              1 => SharedMap
              2 => SharedText
              3 => SharedXmlElement(reader.key())
              4 => SharedXmlFragment
              6 => SharedXmlText
              7 => SharedWeak(LinkSource::read(reader))
              5 | 9 | 15 as reference => SharedOpaque(reference)
              _ => raise InvalidData("unsupported shared type")
            },
          )
        3 => Binary(reader.raw.buffer())
        8 => {
          let values = []
          let count = length_count()
          for _ in 0..<count {
            values.push(reader.raw.any())
          }
          Values(ReadOnlyArray::from_array(values[:]))
        }
        4 => Characters(reader.string())
        _ => raise InvalidData("unsupported item content")
      }
      let length = content.length()
      guard clock.to_uint64() + length.to_uint64() <= 0xffff_ffffUL else {
        raise InvalidData("clock overflow")
      }
      if length > 0 && kind != 10 {
        items.push({
          id: { client, clock, },
          origin,
          right_origin,
          parent,
          parent_sub,
          content,
        })
      }
      clock += length.reinterpret_as_uint()
    }
  }
  let deletion_ranges = []
  for _ in 0..<reader.count() {
    let client = reader.raw.uint()
    deletion_ranges.push((client, 0U, 0U))
    let ranges = reader.count()
    let mut previous = 0UL
    let v2 = !reader.columns.is_empty()
    for _ in 0..<ranges {
      let start = reader.raw.clock().to_uint64() +
        (if v2 { previous } else { 0UL })
      let length = reader.raw.clock().to_uint64() + (if v2 { 1UL } else { 0UL })
      guard start + length <= 0xffff_ffffUL else {
        raise InvalidData("clock range overflow")
      }
      deletion_ranges.push(
        (client, start.to_uint(), (start + length).to_uint()),
      )
      previous = start + length
    }
  }
  reader.finish()
  (items, IdSet(ranges=deletion_ranges), clients > 0)
}
