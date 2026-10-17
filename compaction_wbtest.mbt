///|
test "adjacent appends compact without changing CRDT clocks or cursor offsets" {
  let doc = Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abc")
  let cursor = text.sticky_index(1).unwrap()
  for _ in 0..<1000 {
    text.insert(text.length(), "x")
  }
  assert_eq(doc.clients[1UL].length(), 1)
  assert_eq(doc.items.length(), 1)
  assert_eq(doc.state_vector().get(1UL), 1003U)
  assert_eq(cursor.get_offset(doc).unwrap().index, 1)
  text.remove_range(1, 2)
  let replica = Doc(client_id=2UL)
  replica.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(replica.get_or_insert_text("text").get_string(), text.get_string())
}

///|
test "compaction preserves origin-based integration after a block splits" {
  let a = Doc(client_id=1UL)
  let b = Doc(client_id=2UL)
  let text = a.get_or_insert_text("text")
  text.insert(0, "a")
  b.apply_update_v1(a.encode_state_as_update_v1())
  text.insert(1, "b")
  text.insert(2, "c")
  b.get_or_insert_text("text").insert(1, "!")
  a.apply_update_v1(b.encode_state_as_update_v1())
  b.apply_update_v1(a.encode_state_as_update_v1())
  assert_eq(text.get_string(), b.get_or_insert_text("text").get_string())
  assert_eq(text.get_string(), "abc!")
}

///|
// A full-history sweep is the previous compaction algorithm. A bounded commit
// must leave exactly the same fixed point, including block identities and wire
// representation; equal visible text alone would miss retained fragmentation.
fn assert_fully_compacted(doc : Doc) -> Unit raise {
  let count = doc.items.length()
  let wire = doc.encode_state_as_update_v2()
  let ranges = doc.clients
    .to_array()
    .map(fn(entry) { (entry.0, 0U, doc.next_clock(entry.0)) })
  doc.compact_ranges(ranges)
  assert_eq(doc.items.length(), count)
  assert_eq(doc.encode_state_as_update_v2(), wire)
}

///|
test "bounded compaction matches a full sweep under mixed edits GC undo and delivery" {
  for gc in [false, true] {
    for seed in [17U, 941U, 8389U] {
      let doc = Doc(client_id=1UL, skip_gc=!gc)
      let peer = Doc(client_id=2UL, skip_gc=!gc)
      let text = doc.get_or_insert_text("text")
      let array = doc.get_or_insert_array("array")
      let map = doc.get_or_insert_map("map")
      let undo : UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
      undo.expand_scope(Text(text))
      let mut random = seed
      let draw = fn(n : Int32) {
        random = random * 1664525U + 1013904223U
        ((random >> 8) % n.reinterpret_as_uint()).reinterpret_as_int()
      }
      for step in 0..<240 {
        undo.reset()
        match draw(9) {
          0 | 1 => text.insert(draw(text.length() + 1), "abc")
          2 =>
            if text.length() > 0 {
              let at = draw(text.length())
              text.remove_range(at, 1 + draw(text.length() - at))
            }
          3 => {
            array.insert_range(draw(array.length() + 1), [
              Integer(step.to_int64()),
              Null,
            ])
            if array.length() > 8 {
              array.remove_range(draw(array.length() - 1), 2)
            }
          }
          4 => map.insert("key", String("value"))
          5 => {
            map.insert_text("child").push("nested")
            map.remove("child")
          }
          6 => {
            undo.undo() |> ignore
            undo.redo() |> ignore
          }
          7 => {
            map.insert_input("link", WeakLink(text.quote(Unbounded, Unbounded)))
            |> ignore
            map.remove("link")
          }
          _ => {
            undo.clear_all()
            doc.gc()
          }
        }
        assert_fully_compacted(doc)
        if step % 7 == 0 {
          peer.apply_update_v2(doc.encode_state_as_update_v2())
          peer.get_or_insert_text("text").push("remote")
          let packet = peer.encode_state_as_update_v2()
          doc.apply_update_v2(packet)
          doc.apply_update_v2(packet)
          assert_fully_compacted(doc)
          assert_fully_compacted(peer)
          assert_eq(
            text.get_string(),
            peer.get_or_insert_text("text").get_string(),
          )
        }
      }
    }
  }
}

///|
test "bounded compaction bridges sparse clock gaps and tracks split-only transactions" {
  let source = Doc(client_id=1UL)
  source.get_or_insert_text("missing").push("prefix")
  let prefix = source.encode_state_as_update_v2()
  let cut = source.state_vector()
  source.get_or_insert_text("ready").push("abcdef")
  let target = Doc(client_id=2UL)
  target.apply_update_v2(source.encode_diff_v2(cut))
  assert_eq(target.state_vector().get(1UL), 0U)
  assert_fully_compacted(target)
  target.apply_update_v2(prefix)
  target.transact(fn(_) {
    let item = target.find({ client: 1UL, clock: 7U, }).unwrap()
    target.split(item, 2) |> ignore
  })
  assert_fully_compacted(target)
  assert_eq(target.get_or_insert_text("ready").get_string(), "abcdef")
}
