///|
test "pending subdocument snapshots remain detached after gap integration" {
  for v2 in [false, true] {
    let source = @yrs.Doc(client_id=1UL, guid="source")
    let nested = source.get_or_insert_map("root").insert_map("nested")
    let prefix = source.encode_state_as_update_v2()
    let cut = source.state_vector()
    nested.insert_doc(
      "child",
      @yrs.Doc(client_id=8UL, guid="child", auto_load=true),
    )
    |> ignore
    let pending = @yrs.Doc(client_id=2UL, guid="pending")
    pending.apply_update_v2(source.encode_diff_v2(cut))
    let update = pending.pending_update().unwrap()
    let saved_v1 = update.encode_v1()
    let saved_v2 = update.encode_v2()
    pending.apply_update_v2(prefix)
    let original = pending.subdocs()[0]
    original.get_or_insert_text("child text").push("one")
    original.destroy()
    assert_eq(update.encode_v1(), saved_v1)
    assert_eq(update.encode_v2(), saved_v2)
    let target = @yrs.Doc(client_id=3UL, guid="target")
    if v2 {
      target.apply_update_v2(saved_v2)
    } else {
      target.apply_update_v1(saved_v1)
    }
    target.apply_update_v2(prefix)
    let child = target.subdocs()[0]
    assert_true(child.parent_doc().unwrap().ptr_eq(target))
    assert_false(child.ptr_eq(original))
    assert_true(child.should_load())
    assert_eq(child.get_or_insert_text("child text").get_string(), "")
  }
}

///|
test "retained subdocument transaction bytes survive load destroy and deletion" {
  let source = @yrs.Doc(client_id=1UL, guid="source")
  let saved : Array[@yrs.Transaction] = []
  source.observe_subdocs("keep", fn(_, tx) { saved.push(tx) })
  let child = source
    .get_or_insert_map("root")
    .insert_doc(
      "child",
      @yrs.Doc(client_id=2UL, guid="child", should_load=false),
    )
  let tx = saved[0]
  let v1 = tx.encode_update_v1()
  let v2 = tx.encode_update_v2()
  let encoder = @yrs.EncoderV2()
  tx.encode_update(encoder)
  let generic = encoder.to_bytes()
  child.load()
  child.destroy()
  source.get_or_insert_map("root").remove("child") |> ignore
  source.gc()
  assert_eq(tx.encode_update_v1(), v1)
  assert_eq(tx.encode_update_v2(), v2)
  let encoder = @yrs.EncoderV2()
  tx.encode_update(encoder)
  assert_eq(encoder.to_bytes(), generic)
  let restored = @yrs.Doc(client_id=3UL, guid="target")
  restored.apply_update_v2(generic)
  assert_eq(restored.subdocs().length(), 1)
}
