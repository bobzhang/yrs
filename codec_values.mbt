///|
pub impl Encode for StateVector with fn encode(self, encoder) {
  Write::write_var_uint(encoder, self.clocks.length().to_uint64())
  for (client, clock) in self.entries() {
    Write::write_var_uint(encoder, client)
    Write::write_var_uint(encoder, clock.to_uint64())
  }
}

///|
pub impl Decode for StateVector with fn decode(decoder) {
  let count = codec_count(decoder)
  let result = StateVector()
  for _ in 0..<count {
    let client = Read::read_var_uint(decoder)
    result.clocks[client] = codec_clock(Read::read_var_uint(decoder))
  }
  result
}

///|
pub impl Encode for IdSet with fn encode(self, encoder) {
  let clients = self.client_ids()
  Write::write_var_uint(encoder, clients.length().to_uint64())
  for client in clients {
    encoder.reset_ds_cur_val()
    Write::write_var_uint(encoder, client)
    let ranges = self.get(client).unwrap()
    Write::write_var_uint(encoder, ranges.length().to_uint64())
    for (start, end) in ranges {
      encoder.write_ds_clock(start)
      encoder.write_ds_len(end - start)
    }
  }
}

///|
pub impl Decode for IdSet with fn decode(decoder) {
  let count = codec_count(decoder)
  let result = IdSet()
  for _ in 0..<count {
    decoder.reset_ds_cur_val()
    let client = Read::read_var_uint(decoder)
    result.clients.add(client)
    let count = codec_count(decoder)
    for _ in 0..<count {
      let start = decoder.read_ds_clock()
      let length = decoder.read_ds_len()
      guard length <= 0xffff_ffffU - start else {
        raise InvalidData("clock range overflow")
      }
      result.ranges.push((client, start, start + length))
    }
  }
  result.ranges = normalize_id_ranges(result.ranges)
  result
}

///|
pub impl Encode for Snapshot with fn encode(self, encoder) {
  let clients = self.deletes.keys().to_array()
  clients.sort_by(fn(a, b) { b.compare(a) })
  Write::write_var_uint(encoder, clients.length().to_uint64())
  for client in clients {
    encoder.reset_ds_cur_val()
    Write::write_var_uint(encoder, client)
    let ranges = self.deletes[client]
    Write::write_var_uint(encoder, ranges.length().to_uint64())
    for (start, end) in ranges {
      encoder.write_ds_clock(start)
      encoder.write_ds_len(end - start)
    }
  }
  self.state.encode(encoder)
}

///|
pub impl Decode for Snapshot with fn decode(decoder) {
  let delete_set = IdSet::decode(decoder)
  let state = StateVector::decode(decoder)
  Snapshot(state~, delete_set~)
}

///|
fn codec_count(decoder : &Decoder) -> Int32 raise DecodeError {
  let count = Read::read_var_uint(decoder)
  guard count <= decoder.read_to_end().length().to_uint64() else {
    raise InvalidData("length exceeds remaining bytes")
  }
  count.to_int()
}

///|
pub extend StateVector with Encode::{encode}

///|
pub extend StateVector with Decode::{decode}

///|
pub extend IdSet with Encode::{encode}

///|
pub extend IdSet with Decode::{decode}

///|
pub extend Snapshot with Encode::{encode}

///|
pub extend Snapshot with Decode::{decode}
