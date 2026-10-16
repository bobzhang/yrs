///|
fn Content::joined(self : Content, other : Content) -> Content? {
  match (self, other) {
    (Characters(a), Characters(b)) => Some(Characters(a + b))
    (Values(a), Values(b)) =>
      Some(
        Values(
          ReadOnlyArray::from_array(
            (a.iter().to_array() + b.iter().to_array())[:],
          ),
        ),
      )
    (LegacyJson(a), LegacyJson(b)) =>
      Some(
        LegacyJson(
          ReadOnlyArray::from_array(
            (a.iter().to_array() + b.iter().to_array())[:],
          ),
        ),
      )
    (Deleted(a), Deleted(b)) if a <= 0x7fff_ffff - b => Some(Deleted(a + b))
    (Garbage(a), Garbage(b)) if a <= 0x7fff_ffff - b => Some(Garbage(a + b))
    _ => None
  }
}

///|
fn Doc::compact(self : Doc, transaction : Transaction) -> Unit {
  let clients = transaction.merge_clients
  for (client, _, _) in transaction.added {
    clients.add(client) |> ignore
  }
  for (client, _, _) in transaction.removed {
    clients.add(client) |> ignore
  }
  for client in clients {
    guard self.clients.get(client) is Some(blocks) else { continue }
    let mut index = blocks.length() - 1
    while index > 0 {
      let a = blocks[index - 1]
      let b = blocks[index]
      let end = a.id.clock + a.content.length().reinterpret_as_uint()
      if end == b.id.clock &&
        b.origin == Some({ client, clock: end - 1U, }) &&
        a.right_origin == b.right_origin &&
        a.right == Some(b.id) &&
        a.deleted == b.deleted &&
        !a.linked &&
        !b.linked &&
        a.redone is None &&
        b.redone is None &&
        a.parent == b.parent &&
        a.parent_sub == b.parent_sub &&
        a.content.joined(b.content) is Some(content) {
        if a.parent_sub is None && a.parent is Some(parent) {
          let branch = self.branch(parent)
          if branch.position_hint is Some((hint, offset)) && hint.id == b.id {
            branch.position_hint = Some(
              (a, offset - a.content.offset_length(self)),
            )
          }
        }
        a.keep = a.keep || b.keep
        a.content = content
        a.right = b.right
        if b.right is Some(right) {
          self.items[right].left = Some(a.id)
        }
        if a.parent is Some(parent) && a.parent_sub is Some(key) {
          let branch = self.branch(parent)
          if branch.values.get(key) == Some(b.id) {
            branch.values[key] = a.id
          }
          if branch.heads.get(key) == Some(b.id) {
            branch.heads[key] = a.id
          }
        }
        self.items.remove(b.id)
        blocks.remove(index) |> ignore
      }
      index -= 1
    }
  }
}
