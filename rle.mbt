///|
priv struct Column {
  reader : Reader
  kind : Int32
  mut count : UInt64
  mut last : UInt64
  mut delta : Int64
}

///|
fn Column::next(self : Column) -> UInt64 raise DecodeError {
  if self.count == 0UL {
    match self.kind {
      0 => {
        guard self.reader.offset < self.reader.bytes.length() else {
          raise InvalidData("truncated RLE column")
        }
        let negative = (self.reader.bytes[self.reader.offset].to_int() & 64) !=
          0
        let value = self.reader.signed()
        self.last = if negative {
          0UL - value.reinterpret_as_uint64()
        } else {
          value.reinterpret_as_uint64()
        }
        self.count = if negative {
          self.reader.clock().to_uint64() + 2UL
        } else {
          1UL
        }
      }
      1 => {
        let value = self.reader.signed()
        guard value >= -2147483648L && value <= 2147483647L else {
          raise InvalidData("difference column overflow")
        }
        self.delta = value >> 1
        self.count = if (value & 1L) != 0L {
          self.reader.clock().to_uint64() + 2UL
        } else {
          1UL
        }
      }
      _ => {
        self.last = self.reader.byte().to_uint64()
        self.count = if self.reader.offset == self.reader.bytes.length() {
          0xffff_ffff_ffff_ffffUL
        } else {
          self.reader.clock().to_uint64() + 1UL
        }
      }
    }
  }
  if self.kind == 1 {
    self.last = (self.last.to_uint().reinterpret_as_int() + self.delta.to_int())
      .reinterpret_as_uint()
      .to_uint64()
  }
  if self.count != 0xffff_ffff_ffff_ffffUL {
    self.count -= 1UL
  }
  self.last
}

///|
fn encode_column(
  values : Array[UInt64],
  kind : Int32,
) -> Bytes raise DecodeError {
  let writer : Writer = { bytes: [], }
  let mut i = 0
  let mut previous = 0U
  while i < values.length() {
    let value = values[i]
    let delta = value.to_uint().reinterpret_as_int() -
      previous.reinterpret_as_int()
    let mut count = 1
    while i + count < values.length() {
      let same = if kind == 1 {
        values[i + count].to_uint().reinterpret_as_int() -
        values[i + count - 1].to_uint().reinterpret_as_int() ==
        delta
      } else {
        values[i + count] == value
      }
      if !same {
        break
      }
      count += 1
    }
    match kind {
      0 => {
        guard value <= 0x7fff_ffff_ffff_ffffUL else {
          raise InvalidData("v2 unsigned column exceeds signed range")
        }
        if count > 1 && value == 0UL {
          writer.byte(64)
        } else {
          writer.signed(
            if count > 1 {
              -value.reinterpret_as_int64()
            } else {
              value.reinterpret_as_int64()
            },
          )
        }
        if count > 1 {
          writer.uint((count - 2).to_uint64())
        }
      }
      1 => {
        writer.signed(
          ((delta << 1) | (if count > 1 { 1 } else { 0 })).to_int64(),
        )
        if count > 1 {
          writer.uint((count - 2).to_uint64())
        }
      }
      _ => {
        writer.byte(value.to_int())
        if i + count < values.length() {
          writer.uint((count - 1).to_uint64())
        }
      }
    }
    previous = values[i + count - 1].to_uint()
    i += count
  }
  writer.finish()
}
