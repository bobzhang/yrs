///|
/// Write integrated document changes to an application-supplied field codec.
/// Pending blocks and early deletions are excluded, matching Rust's generic
/// ReadTxn::encode_diff. Use the v1/v2 state-update helpers to forward pending data.
pub fn Doc::encode_diff(
  self : Doc,
  remote : StateVector,
  encoder : &Encoder,
) -> Unit {
  try! copy_update_fields(
    DecoderV1(self.encode_diff_v1(remote)),
    encoder,
    0x7fff_ffff,
  )
}

///|
/// Write the integrated state through a generic encoder. Like pinned Rust's
/// generic method, this omits pending data; its v1/v2 convenience methods also
/// merge pending updates. The distinction matters for out-of-order delivery.
pub fn Doc::encode_state_as_update(
  self : Doc,
  remote : StateVector,
  encoder : &Encoder,
) -> Unit {
  self.encode_diff(remote, encoder)
}

///|
/// Write retained historical state through a generic encoder. GC must be off.
pub fn Doc::encode_state_from_snapshot(
  self : Doc,
  snapshot : Snapshot,
  encoder : &Encoder,
) -> Unit raise DecodeError {
  copy_update_fields(
    DecoderV1(self.encode_state_from_snapshot_v1(snapshot)),
    encoder,
    0x7fff_ffff,
  )
}

///|
/// Write just this transaction's insertions and deletions through a field codec.
pub fn Transaction::encode_update(
  self : Transaction,
  encoder : &Encoder,
) -> Unit {
  try! copy_update_fields(
    DecoderV1(self.encode_update_v1()),
    encoder,
    0x7fff_ffff,
  )
}
