///|
test "historical text diffs retain deleted text and annotate original identities" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "abcd")
  let before = doc.snapshot()
  text.remove_range(1, 1)
  text.insert(1, "x")
  let after = doc.snapshot()
  text.remove_range(2, 1)
  let state = doc.encode_state_as_update_v1()
  let chunks = text.diff_range(@yrs.YChange::identity, hi=after, lo=before)
  assert_eq(chunks.map(fn(c) { (c.insert.to_string(), c.ychange) }), [
    ("a", None),
    (
      "b",
      Some(@yrs.YChange::{ kind: Removed, id: { client: 1UL, clock: 1U, }, }),
    ),
    ("x", Some(@yrs.YChange::{ kind: Added, id: { client: 1UL, clock: 4U, }, })),
    ("cd", None),
  ])
  assert_eq(
    text
    .diff_range(@yrs.YChange::identity, hi=before)
    .map(fn(c) { c.insert.to_string() })
    .join(""),
    "abcd",
  )
  assert_eq(doc.encode_state_as_update_v1(), state)
  assert_eq(
    text
    .diff(@yrs.YChange::identity)
    .map(fn(c) { c.insert.to_string() })
    .join(""),
    "axd",
  )
}

///|
test "historical formatting and snapshot cuts survive later block compaction" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "ab")
  let before = doc.snapshot()
  text.push("cd")
  text.format(1, 2, [("bold", Bool(true))])
  let bold = doc.snapshot()
  text.format(0, 4, [("bold", Null)])
  assert_eq(
    text
    .diff_range(@yrs.YChange::identity, hi=before)
    .map(fn(c) { c.insert.to_string() })
    .join(""),
    "ab",
  )
  let chunks = text.diff_range(@yrs.YChange::identity, hi=bold)
  assert_eq(chunks.map(fn(c) { (c.insert.to_string(), c.attributes) }), [
    ("a", []),
    ("bc", [("bold", @yrs.Any::Bool(true))]),
    ("d", []),
  ])
}

///|
test "formatting a UTF16 surrogate boundary matches Yjs replacement semantics" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "🦀")
  text.format(1, 1, [("bold", Bool(true))])
  assert_eq(text.get_string(), "��")
  assert_eq(
    text
    .diff(@yrs.YChange::identity)
    .map(fn(c) { (c.insert.to_string(), c.attributes) }),
    [("�", []), ("�", [("bold", @yrs.Any::Bool(true))])],
  )
  text.remove_range(1, 1)
  assert_eq(text.get_string(), "�")
}

///|
test "format cleanup option is local and preserved by unloaded copies" {
  let parent = @yrs.Doc(client_id=1UL)
  let child = @yrs.Doc(client_id=2UL, guid="child", cleanup_formatting=false)
  assert_true(parent.cleanup_formatting_enabled())
  assert_false(child.cleanup_formatting_enabled())
  parent.get_or_insert_map("root").insert_doc("child", child) |> ignore
  child.destroy()
  guard parent.get_or_insert_map("root").get("child")
    is Some(Subdoc(replacement)) else {
    fail("child")
  }
  assert_false(replacement.cleanup_formatting_enabled())
  let peer = @yrs.Doc(client_id=3UL)
  peer.apply_update_v1(parent.encode_state_as_update_v1())
  guard peer.get_or_insert_map("root").get("child") is Some(Subdoc(remote)) else {
    fail("child")
  }
  assert_false(remote.cleanup_formatting_enabled())
}
