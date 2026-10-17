///|
fn dependency_block(
  client : UInt64,
  origin : Id?,
  clock~ : UInt32 = 0U,
) -> RawItem {
  {
    id: { client, clock, },
    origin,
    right_origin: None,
    parent: Some(Root("text")),
    parent_sub: None,
    content: Characters("x"),
  }
}

///|
test "dependency scheduling visits a reversed cross-client chain linearly" {
  for size in [32, 512, 8192] {
    let doc = Doc(client_id=100000UL)
    for client in 1..<(size + 1) {
      doc.pending.push(
        dependency_block(
          client.to_uint64(),
          if client == 1 {
            None
          } else {
            Some({ client: (client - 1).to_uint64(), clock: 0U, })
          },
        ),
      )
    }
    assert_eq(doc.integrate_pending(), 2 * size - 1)
    assert_eq(doc.pending.length(), 0)
    assert_eq(doc.get_or_insert_text("text").length(), size)
  }
}

///|
test "dependency scheduling preserves sparse independence and terminates cycles" {
  let doc = Doc(client_id=100UL)
  doc.pending.push(dependency_block(1UL, Some({ client: 2UL, clock: 0U, })))
  doc.pending.push(dependency_block(2UL, Some({ client: 1UL, clock: 0U, })))
  doc.pending.push(dependency_block(1UL, None, clock=10U))
  doc.pending.push(dependency_block(3UL, Some({ client: 1UL, clock: 10U, })))
  doc.pending.push(dependency_block(4UL, Some({ client: 99UL, clock: 0U, })))
  assert_eq(doc.integrate_pending(), 6)
  assert_eq(doc.pending.length(), 3)
  assert_eq(doc.get_or_insert_text("text").get_string(), "xx")
  assert_eq(doc.state_vector().get(1UL), 0U)
  doc.pending.push(dependency_block(99UL, None))
  assert_eq(doc.integrate_pending(), 4)
  assert_eq(doc.pending.length(), 2)
  assert_eq(doc.get_or_insert_text("text").length(), 4)
}
