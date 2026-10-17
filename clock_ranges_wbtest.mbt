///|
test "incremental clock ranges agree with batch normalization and point membership" {
  let doc = Doc(client_id=9UL)
  let ids = IdSet()
  let history : Array[(UInt64, UInt32, UInt32)] = []
  let mut random = 941U
  for step in 0..<3000 {
    random = random * 1664525U + 1013904223U
    let client = (random % 5U).to_uint64()
    let base = if step % 3 == 0 { 0xffff_ff00U } else { 0U }
    let start = base + (random >> 8) % 224U
    let length = (random >> 24) % 32U
    ids.insert({ client, clock: start, }, length)
    doc.add_delete(client, start, start + length)
    history.push((client, start, start + length))
    let expected = IdSet(ranges=history)
    assert_eq(ids.ranges(), expected.ranges())
    assert_eq(ids.client_ids(), expected.client_ids())
    let actual = []
    for c, ranges in doc.deletes {
      for (a, b) in ranges {
        actual.push((c, a, b))
      }
    }
    assert_eq(normalize_id_ranges(actual), expected.ranges())
    for clock in [start, start + length, base, base + 255U] {
      let id : Id = { client, clock, }
      assert_eq(ids.contains(id), contains_range(expected.ranges(), id))
    }
  }
}

///|
test "linear range algebra agrees with independent point sets across clients and holes" {
  let mut random = 8389U
  for _ in 0..<100 {
    let left = IdSet()
    let right = IdSet()
    let a : Set[Id] = Set([])
    let b : Set[Id] = Set([])
    for i in 0..<80 {
      random = random * 1664525U + 1013904223U
      let client = (random % 4U).to_uint64()
      let start = (random >> 8) % 120U
      let size = (random >> 16) % 8U
      let ids = if i % 2 == 0 { left } else { right }
      let points = if i % 2 == 0 { a } else { b }
      ids.insert({ client, clock: start, }, size)
      for j in 0..<size.reinterpret_as_int() {
        points.add({ client, clock: start + j.reinterpret_as_uint(), })
      }
    }
    let union = left.merge(right)
    let diff = left.diff(right)
    let intersect = left.intersect(right)
    for set in [union, diff, intersect] {
      assert_eq(set.ranges(), normalize_id_ranges(set.ranges()))
    }
    for client in 0..<4 {
      for clock in 0..<128 {
        let id : Id = {
          client: client.to_uint64(),
          clock: clock.reinterpret_as_uint(),
        }
        assert_eq(union.contains(id), a.contains(id) || b.contains(id))
        assert_eq(diff.contains(id), a.contains(id) && !b.contains(id))
        assert_eq(intersect.contains(id), a.contains(id) && b.contains(id))
      }
    }
  }
}
