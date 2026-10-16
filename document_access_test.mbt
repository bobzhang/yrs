///|
test "root lookups do not create collections or change declared types" {
  let doc = @yrs.Doc(client_id=1UL)
  assert_true(doc.get("missing") is None)
  assert_true(doc.get_text("missing") is None)
  assert_true(doc.get_map("missing") is None)
  assert_true(doc.get_array("missing") is None)
  assert_true(doc.get_xml_fragment("missing") is None)
  assert_true(doc.root_refs().is_empty())
  doc.get_or_insert_map("value").insert("key", Bool(true))
  assert_true(doc.get_text("value") is Some(_))
  assert_true(doc.get("value") is Some(Map(_)))
  assert_true(doc.ptr_eq(doc))
  assert_false(doc.ptr_eq(@yrs.Doc(client_id=1UL)))
}

///|
test "pruned dependencies and early deletions can be saved and restored" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("text")
  text.insert(0, "hello")
  let first = source.encode_state_as_update_v1()
  let state = source.state_vector()
  text.insert(5, " world")
  let tail = source.encode_diff_v1(state)
  let target = @yrs.Doc(client_id=2UL)
  target.apply_update_v1(tail)
  assert_true(target.has_missing_updates())
  assert_true(
    @yrs.Update::decode_v1(target.encode_diff_v1(@yrs.StateVector())).is_empty(),
  )
  let retained = target.prune_pending().unwrap()
  assert_false(target.has_missing_updates())
  assert_true(target.prune_pending() is None)
  target.apply_update_v1(first)
  assert_eq(target.get_text("text").unwrap().get_string(), "hello")
  target.apply_update(retained)
  assert_eq(target.get_text("text").unwrap().get_string(), "hello world")
  let final_state = source.state_vector()
  text.remove_range(0, 2)
  let early_delete = source.encode_diff_v1(final_state)
  let blank = @yrs.Doc(client_id=3UL)
  blank.apply_update_v1(early_delete)
  assert_true(blank.has_missing_updates())
  assert_true(
    @yrs.Update::decode_v1(blank.encode_diff_v1(@yrs.StateVector()))
    .delete_set()
    .is_empty(),
  )
  let deleted = blank.prune_pending().unwrap()
  assert_eq(deleted.delete_set().ranges(), [(1UL, 0U, 2U)])
  assert_false(blank.has_missing_updates())
  blank.apply_update_v1(first)
  assert_eq(blank.get_text("text").unwrap().get_string(), "hello")
  blank.apply_update(deleted)
  assert_eq(blank.get_text("text").unwrap().get_string(), "llo")
}

///|
test "transaction metadata and array block identities exclude transient insertions" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("items")
  array.insert_range(0, [Integer(1L), Integer(2L), Integer(3L)])
  let results = []
  array.observe("ids", fn(e, _) {
    results.push((e.inserts().iter().to_array(), e.removes().iter().to_array()))
  })
  doc.transact(fn(tx) raise {
    assert_false(tx.has_changes())
    array.remove_range(1, 1)
    array.insert_range(1, [Integer(4L), Integer(5L)])
    array.remove_range(2, 1)
    assert_true(tx.has_changes())
    assert_eq(tx.insert_set().ranges(), [(1UL, 3U, 5U)])
    assert_eq(tx.delete_set().ranges(), [(1UL, 1U, 2U), (1UL, 4U, 5U)])
    assert_true(tx.cleanups().is_empty())
  })
  assert_eq(results, [
    ([{ client: 1UL, clock: 3U, }], [{ client: 1UL, clock: 1U, }]),
  ])
}

///|
test "explicit garbage collection respects whole block scope" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abcde")
  text.remove_range(0, 5)
  let before = doc.encode_state_as_update_v1()
  doc.gc(delete_set=@yrs.IdSet(ranges=[(1UL, 1U, 3U)]))
  assert_eq(doc.encode_state_as_update_v1(), before)
  doc.gc(delete_set=@yrs.IdSet(ranges=[(1UL, 0U, 5U)]))
  assert_false(doc.encode_state_as_update_v1() == before)
}

///|
test "early deletions apply to local inserts and delayed nested descendants" {
  let source = @yrs.Doc(client_id=8UL)
  let text = source.get_or_insert_text("text")
  text.insert(0, "abc")
  let state = source.state_vector()
  text.remove_range(1, 1)
  let deletion = source.encode_diff_v1(state)
  let replay = @yrs.Doc(client_id=8UL)
  replay.apply_update_v1(deletion)
  let resumed = replay.get_or_insert_text("text")
  replay.transact(fn(_) raise {
    resumed.insert(0, "abc")
    assert_eq(resumed.get_string(), "ac")
    resumed.insert(2, "d")
  })
  assert_eq(resumed.get_string(), "acd")
  assert_false(replay.has_missing_updates())
  let parent = source.get_or_insert_map("root")
  let child = parent.insert_text("child")
  let parent_wire = source.encode_state_as_update_v1()
  let state = source.state_vector()
  child.insert(0, "late content")
  let child_wire = source.encode_diff_v1(state)
  let state = source.state_vector()
  parent.remove("child")
  let deletion = source.encode_diff_v1(state)
  let peer = @yrs.Doc(client_id=9UL)
  peer.apply_update_v1(deletion)
  peer.apply_update_v1(child_wire)
  peer.apply_update_v1(parent_wire)
  assert_eq(peer.get_or_insert_map("root").to_json(), {})
  assert_eq(peer.snapshot(), source.snapshot())
}

///|
test "root-key paths resolve nested shared collections and distinguish retained deleted map entries" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let array = root.insert_array("items")
  array.push_back(Value(Integer(1L))) |> ignore
  let map = array.insert_map(1)
  let text = map.insert_text("note")
  text.insert(0, "Moon")
  let path : Array[@yrs.PathSegment] = [
    Key("root"),
    Key("items"),
    Index(1),
    Key("note"),
  ]
  assert_eq(
    doc.get_type_from_path(path).unwrap().branch_id(),
    Some(text.hook().id()),
  )
  assert_true(doc.get_type_from_path([]) is None)
  assert_true(doc.get_type_from_path([Index(0)]) is None)
  assert_true(
    doc.get_type_from_path([Key("root"), Key("items"), Index(0)]) is None,
  )
  assert_true(doc.get_type_from_path([Key("missing")]) is None)
  array.remove(0)
  assert_true(doc.get_type_from_path(path) is None)
  assert_eq(
    doc
    .get_type_from_path([Key("root"), Key("items"), Index(0), Key("note")])
    .unwrap()
    .branch_id(),
    Some(text.hook().id()),
  )
  root.remove("items")
  let retained = doc.get_type_from_path([Key("root"), Key("items")]).unwrap()
  assert_true(retained.is_deleted())
  assert_true(
    doc.get_type_from_path([Key("root"), Key("items"), Index(0)]) is None,
  )
  doc.gc()
  assert_true(doc.get_type_from_path([Key("root"), Key("items")]) is None)
}

///|
test "pending inspection is owned read-only metadata and resolves after prefix delivery" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("note")
  text.insert(0, "A")
  let prefix = source.encode_state_as_update_v1()
  let known = source.state_vector()
  text.insert(1, "B")
  let suffix = source.encode_state_as_update_v1(remote=known)
  text.remove_range(0, 1)
  let deletion = source.encode_state_as_update_v1(remote=source.state_vector())
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(suffix)
  peer.apply_update_v1(deletion)
  let mut notifications = 0
  peer.observe_after_transaction("reads", fn(_) { notifications += 1 })
  let pending = peer.pending_update().unwrap()
  assert_eq(pending.insertions().ranges(), [(1UL, 1U, 2U)])
  assert_true(pending.delete_set().is_empty())
  let deleted = peer.pending_delete_set().unwrap()
  assert_eq(deleted.ranges(), [(1UL, 0U, 1U)])
  deleted.remove_range({ client: 1UL, clock: 0U, }, 1U)
  pending.merge(@yrs.Update::decode_v1(prefix))
  assert_eq(peer.pending_delete_set().unwrap().ranges(), [(1UL, 0U, 1U)])
  assert_eq(peer.pending_update().unwrap().insertions().ranges(), [
    (1UL, 1U, 2U),
  ])
  assert_eq(notifications, 0)
  peer.apply_update_v1(prefix)
  assert_true(peer.pending_update() is None)
  assert_true(peer.pending_delete_set() is None)
  assert_eq(peer.get_text("note").unwrap().get_string(), "B")
  assert_eq(notifications, 1)
}
