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
