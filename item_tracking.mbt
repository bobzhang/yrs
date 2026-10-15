///|
priv struct IdentityCounter {
  mut value : UInt64
}

///|
let identity_counter : IdentityCounter = { value: 0UL, }

///|
fn allocate_identity() -> UInt64 {
  identity_counter.value += 1UL
  identity_counter.value
}

///|
fn Doc::follow_redone(self : Doc, original : Id) -> Id? {
  let mut id = original
  while self.find(id) is Some(item) {
    if item.redone is Some(redone) {
      id = {
        client: redone.client,
        clock: redone.clock + id.clock - item.id.clock,
      }
    } else {
      return Some(id)
    }
  }
  None
}
