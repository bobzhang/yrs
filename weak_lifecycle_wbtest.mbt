///|
test "empty quotation notification after deletion refers to its format marker" {
  let doc = Doc(client_id=1UL, skip_gc=false)
  let text = doc.get_or_insert_text("text")
  let map = doc.get_or_insert_map("links")
  text.insert(0, "abcdefghijklmnop")
  let value = map.insert_input(
    "t2",
    WeakLink(text.quote(Included(5), Unbounded)),
  )
  guard value is WeakLink(link) && link.branch_id() is Nested(link_id) else {
    fail("expected nested quotation")
  }
  for
    (format, at, length, attribute) in [
      (true, 38, 5, Bool(true)),
      (false, 82, 2, Null),
      (true, 6, 2, Null),
      (false, 72, 5, Null),
      (false, 66, 4, Null),
      (false, 77, 7, Null),
      (true, 50, 7, Bool(true)),
    ] {
    let index = at % text.length()
    let count = length.min(text.length() - index)
    if format {
      text.format(index, count, [("b", attribute)])
    } else {
      text.remove_range(index, count)
    }
  }
  assert_eq(text.get_string(), "ab")
  assert_eq(link.get_string(), "")
  let linked = doc.items
    .values()
    .filter(fn(item) { !item.deleted && item.links.contains(link_id) })
    .to_array()
  let removed_formats = []
  let events = Ref(0)
  link.observe("watch", fn(_, _) { events.val += 1 })
  doc.observe_after_transaction("cause", fn(txn) {
    for item in linked {
      if contains_range(txn.removed, item.id) {
        removed_formats.push(item.content is Format(_, _))
      }
    }
  })
  text.remove_range(1, 1)
  assert_eq(text.get_string(), "a")
  assert_eq(link.get_string(), "")
  assert_eq(events.val, 1)
  assert_false(removed_formats.is_empty())
  assert_true(removed_formats.all(fn(is_format) { is_format }))
}
