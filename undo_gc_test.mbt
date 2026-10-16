///|
fn undo_gc_tree(root : @yrs.MapRef, key : String) -> Unit {
  let child = root.insert_map(key)
  child.insert_text("title").insert(0, "hello")
  child.insert_array("list").insert_map(0).insert("done", Bool(false))
}

///|
test "remote parent deletion after undo and redo-history release remains encodable" {
  for skip_gc in [false, true] {
    for v2 in [false, true] {
      let a = @yrs.Doc(client_id=3UL, skip_gc~)
      let b = @yrs.Doc(client_id=2UL, skip_gc~)
      let ar = a.get_or_insert_map("root")
      let br = b.get_or_insert_map("root")
      let au : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL }, tracked_origins=[
        b"user",
      ])
      let bu : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL }, tracked_origins=[
        b"user",
      ])
      au.expand_scope(Map(ar))
      bu.expand_scope(Map(br))
      fn sync(source : @yrs.Doc, target : @yrs.Doc) -> Unit raise {
        if v2 {
          target.apply_update_v2(
            source.encode_state_as_update_v2(remote=target.state_vector()),
          )
        } else {
          target.apply_update_v1(
            source.encode_state_as_update_v1(remote=target.state_vector()),
          )
        }
      }
      a.transact(_ => undo_gc_tree(ar, "key2"), origin=b"user")
      sync(a, b)
      b.transact(
        _ => {
          let child = br.get_or_init_map("key2")
          child.get_or_init_text("title").insert(2, "!")
          let list = child.get_or_init_array("list")
          guard list.get(0) is Some(Map(row)) else { fail("nested row") }
          row.insert("done", Bool(true))
          list.push_back(Value(Integer(2L))) |> ignore
        },
        origin=b"user",
      )
      assert_true(au.undo())
      assert_true(bu.undo())
      // This local edit clears B's redo stack before A's deletion arrives.
      b.transact(_ => undo_gc_tree(br, "key1"), origin=b"user")
      assert_false(bu.can_redo())
      sync(a, b)
      assert_eq(br.to_json(), {
        "key1": { "title": "hello", "list": [{ "done": false }] },
      })
      for step in 0..<3 {
        let copy = @yrs.Doc(client_id=4UL, skip_gc~)
        sync(b, copy)
        assert_eq(copy.get_or_insert_map("root").to_json(), br.to_json())
        if step == 0 {
          assert_true(bu.undo())
          assert_eq(br.to_json(), {})
        } else if step == 1 {
          assert_true(bu.redo())
          assert_true(br.contains_key("key1"))
          assert_false(br.contains_key("key2"))
        }
      }
    }
  }
}
