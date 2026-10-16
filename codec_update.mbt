///|
/// Stream one update through arbitrary field codecs without integrating a Doc.
/// Expansion is bounded before iterating compressed block/value counts.
fn copy_update_fields(
  input : &Decoder,
  output : &Encoder,
  max_items : Int32,
) -> Unit raise DecodeError {
  guard max_items >= 0 else { raise InvalidData("negative decode budget") }
  let mut remaining = max_items
  fn reserve(value : UInt64) -> Int32 raise DecodeError {
    guard value <= remaining.to_uint64() else {
      raise InvalidData("update exceeds decode item budget")
    }
    remaining -= value.to_int()
    value.to_int()
  }
  fn count() -> Int32 raise DecodeError {
    let value = Read::read_var_uint(input)
    let n = reserve(value)
    Write::write_var_uint(output, value)
    n
  }
  fn raw_uint() -> UInt64 raise DecodeError {
    let value = Read::read_var_uint(input)
    Write::write_var_uint(output, value)
    value
  }
  fn string() -> Unit raise DecodeError {
    Write::write_string(output, Read::read_string(input))
  }
  fn left() -> Unit raise DecodeError {
    output.write_left_id(input.read_left_id())
  }
  fn length() -> UInt32 raise DecodeError {
    let n = input.read_len()
    output.write_len(n)
    n
  }
  for _ in 0..<count() {
    let blocks = count()
    output.write_client(input.read_client())
    codec_clock(raw_uint()) |> ignore
    for _ in 0..<blocks {
      let info = input.read_info().to_int()
      output.write_info(info.to_byte())
      if info == 10 {
        // Skip lengths live in the raw stream, including v2 (Yjs-compatible).
        codec_clock(raw_uint()) |> ignore
        continue
      }
      if info == 0 {
        length() |> ignore
        continue
      }
      if (info & 128) != 0 {
        left()
      }
      if (info & 64) != 0 {
        output.write_right_id(input.read_right_id())
      }
      if (info & 192) == 0 {
        let root = input.read_parent_info()
        output.write_parent_info(root)
        if root {
          string()
        } else {
          left()
        }
        if (info & 32) != 0 {
          string()
        }
      }
      match info & 31 {
        1 => length() |> ignore
        2 =>
          for _ in 0..<reserve(length().to_uint64()) {
            string()
          }
        3 => {
          let bytes = Read::read_buf(input)
          // EncoderV2.write_all adds a length itself. Emit raw bytes explicitly
          // to preserve the single-length content-buffer wire representation.
          Write::write_var_uint(output, bytes.length().to_uint64())
          for byte in bytes {
            Write::write_u8(output, byte)
          }
        }
        4 => string()
        5 => output.write_json(input.read_json())
        6 => {
          output.write_key(input.read_key())
          output.write_json(input.read_json())
        }
        7 => {
          let kind = input.read_type_ref()
          output.write_type_ref(kind)
          match kind.to_int() {
            3 => output.write_key(input.read_key())
            7 => copy_link_fields(input, output)
            0 | 1 | 2 | 4 | 5 | 6 | 9 | 15 => ()
            _ => raise InvalidData("unsupported shared type reference")
          }
        }
        8 =>
          for _ in 0..<reserve(length().to_uint64()) {
            output.write_any(input.read_any())
          }
        9 => {
          string()
          output.write_any(input.read_any())
        }
        _ => raise InvalidData("invalid content reference")
      }
    }
  }
  for _ in 0..<count() {
    input.reset_ds_cur_val()
    output.reset_ds_cur_val()
    raw_uint() |> ignore
    for _ in 0..<count() {
      let start = input.read_ds_clock()
      let length = input.read_ds_len()
      guard length <= 0xffff_ffffU - start else {
        raise InvalidData("invalid delete range")
      }
      output.write_ds_clock(start)
      output.write_ds_len(length)
    }
  }
}

///|
fn copy_link_fields(
  input : &Decoder,
  output : &Encoder,
) -> Unit raise DecodeError {
  let flags = Read::read_u8(input).to_int()
  guard flags < 64 else { raise InvalidData("invalid weak link flags") }
  Write::write_u8(output, flags.to_byte())
  fn scope(unbounded : Bool) -> Unit raise DecodeError {
    if unbounded && (flags & 32) != 0 {
      Write::write_string(output, Read::read_string(input))
    } else {
      Write::write_var_uint(output, Read::read_var_uint(input))
      Write::write_var_uint(
        output,
        codec_clock(Read::read_var_uint(input)).to_uint64(),
      )
    }
  }
  scope((flags & 8) != 0)
  if (flags & 16) != 0 || (flags & 1) != 0 {
    scope((flags & 16) != 0)
  }
}

///|
pub impl Encode for Update with fn encode(self, encoder) {
  // Updates own already-validated v1 bytes. No external input is parsed here.
  try! copy_update_fields(DecoderV1(self.wire), encoder, 0x7fff_ffff)
}

///|
pub impl Decode for Update with fn decode(decoder) {
  let encoder = EncoderV1()
  copy_update_fields(decoder, encoder, 1000000)
  Update::decode_v1(encoder.to_bytes())
}

///|
pub extend Update with Encode::{encode}

///|
pub extend Update with Decode::{decode}
