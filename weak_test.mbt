///|
fn weak(value : @yrs.Out) -> @yrs.WeakRef {
  guard value is WeakLink(link) else { abort("expected weak link") }
  link
}

///|
test "weak map links follow replacements removals and wire replay" {
  let doc = @yrs.Doc(client_id=1UL, skip_gc=false)
  let map = doc.get_or_insert_map("map")
  map.insert("source", Integer(1L))
  let link = weak(
    map.insert_input("link", WeakLink(map.link("source").unwrap())),
  )
  let events = []
  link.observe("watch", fn(e, _) {
    events.push(e.target().try_deref_value().map(fn(v) { v.to_json() }))
  })
  map.insert("source", Integer(2L))
  assert_eq(link.try_deref_value().unwrap().to_json(), Json(2))
  map.remove("source")
  assert_true(link.try_deref_value() is None)
  map.insert("source", Integer(3L))
  assert_eq(link.try_deref_value().unwrap().to_json(), Json(3))
  // Once a linked entry is deleted, upstream detaches its observation edges.
  assert_eq(events, [Some(Json(2)), None])
  for v2 in [false, true] {
    let peer = @yrs.Doc(client_id=2UL, skip_gc=false)
    if v2 {
      peer.apply_update_v2(doc.encode_state_as_update_v2())
    } else {
      peer.apply_update_v1(doc.encode_state_as_update_v1())
    }
    let remote = weak(peer.get_or_insert_map("map").get("link").unwrap())
    assert_eq(remote.try_deref_value().unwrap().to_json(), Json(3))
  }
  assert_true(link.unobserve("watch"))
  map.remove("link")
  assert_true(link.is_deleted())
  assert_eq(map.get("source").unwrap().to_json(), Json(3))
}

///|
test "text quotations track edits formatting and open boundaries" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  let links = doc.get_or_insert_map("links")
  text.insert(0, "abcde")
  text.format(0, 1, [("b", Bool(true))])
  text.format(1, 3, [("i", Bool(true))])
  let first = weak(
    links.insert_input("first", WeakLink(text.quote(Included(0), Included(1)))),
  )
  let middle = weak(
    links.insert_input("middle", WeakLink(text.quote(Included(2), Included(2)))),
  )
  let last = weak(
    links.insert_input("last", WeakLink(text.quote(Included(3), Unbounded))),
  )
  assert_eq(first.get_xml_string(), "<b>a</b><i>b</i>")
  assert_eq(middle.get_xml_string(), "<i>c</i>")
  assert_eq(last.get_xml_string(), "<i>d</i>e")
  let hits = Ref(0)
  middle.observe("change", fn(_, _) { hits.val += 1 })
  text.insert(2, "X")
  assert_eq(middle.get_string(), "c")
  assert_eq(hits.val, 0)
  text.remove_range(3, 1)
  assert_eq(middle.get_string(), "")
  assert_eq(hits.val, 1)
  text.insert(text.length(), "!")
  assert_eq(last.get_string(), "de!")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(doc.encode_state_as_update_v2())
  assert_eq(
    weak(peer.get_or_insert_map("links").get("last").unwrap()).get_string(),
    "de!",
  )
}

///|
test "array quotations propagate deep changes through weak chains and cycles" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("array")
  let map = doc.get_or_insert_map("map")
  let child = array.insert_map(0)
  let link = weak(
    map.insert_input("link", WeakLink(array.quote(Included(0), Included(0)))),
  )
  let transitive = weak(
    map.insert_input("transitive", WeakLink(map.link("link").unwrap())),
  )
  let paths = []
  transitive.observe_deep("deep", fn(events, _) {
    for e in events {
      paths.push(e.path().iter().map(fn(p) { p.to_json() }).to_array())
    }
  })
  child.insert("key", String("value"))
  assert_eq(paths, [[Json(0)]])
  assert_eq(link.unquote().map(fn(v) { v.to_json() }), [
    ({ "key": "value" } : Json),
  ])
  let direct = Ref(0)
  link.observe("delete", fn(_, _) { direct.val += 1 })
  array.remove(0)
  assert_true(link.unquote().is_empty())
  assert_eq(direct.val, 1)
  // Self-quotation forms an observer graph cycle without owning its target.
  array.insert(0, Value(Integer(7L))) |> ignore
  let self_link = weak(
    array.insert(0, WeakLink(array.quote(Unbounded, Unbounded))),
  )
  self_link.observe_deep("cycle", fn(_, _) { () })
  array.insert(1, Value(Integer(8L))) |> ignore
  assert_eq(array.length(), 3)
}

///|
test "weak quotations reject missing anchors and preserve UTF16 slices" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  text.insert(0, "a界🦀z")
  let map = doc.get_or_insert_map("links")
  let link = weak(
    map.insert_input("link", WeakLink(text.quote(Included(1), Included(3)))),
  )
  assert_eq(link.get_string(), "界🦀")
  let failed = try {
    text.quote(Included(0), Excluded(5)) |> ignore
    false
  } catch {
    @yrs.QuoteError::OutOfBounds => true
  }
  assert_true(failed)
  let empty = weak(
    map.insert_input("empty", WeakLink(text.quote(Excluded(0), Included(0)))),
  )
  assert_eq(empty.get_string(), "")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(
    weak(peer.get_or_insert_map("links").get("link").unwrap()).get_string(),
    "界🦀",
  )
}

///|
test "unbounded weak observers survive empty sequences and either endpoint" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("text")
  let links = doc.get_or_insert_map("links")
  let link = weak(
    links.insert_input("quote", WeakLink(text.quote(Unbounded, Unbounded))),
  )
  let changes = []
  link.observe("open", fn(_, _) { changes.push(link.get_string()) })
  text.insert(0, "middle")
  text.insert(0, "left ")
  text.insert(text.length(), " right")
  text.remove_range(0, text.length())
  text.insert(0, "again")
  assert_eq(changes, ["middle", "left middle", "left middle right", "", "again"])
  links.remove("quote")
  text.insert(0, "unobserved ")
  assert_eq(changes.length(), 5)
}

///|
test "weak subscriptions attach after out-of-order anchor delivery" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("text")
  text.insert(0, "anchor")
  let anchor = source.encode_state_as_update_v1()
  let before = source.state_vector()
  let links = source.get_or_insert_map("links")
  links.insert_input("quote", WeakLink(text.quote(Included(0), Unbounded)))
  |> ignore
  let quote = source.encode_diff_v1(before)
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(quote)
  let link = weak(peer.get_or_insert_map("links").get("quote").unwrap())
  let changes = []
  link.observe("late", fn(_, _) { changes.push(link.get_string()) })
  peer.apply_update_v1(anchor)
  peer.get_or_insert_text("text").insert(6, "!")
  assert_eq(changes, ["anchor", "anchor!"])
  for version in 1..<=2 {
    let remote = @yrs.Doc(client_id=3UL)
    if version == 1 {
      remote.apply_update_v1(peer.encode_state_as_update_v1())
    } else {
      remote.apply_update_v2(peer.encode_state_as_update_v2())
    }
    let remote_link = weak(
      remote.get_or_insert_map("links").get("quote").unwrap(),
    )
    let hits = Ref(0)
    remote_link.observe("imported", fn(_, _) { hits.val += 1 })
    remote.get_or_insert_text("text").insert(7, "?")
    assert_eq(remote_link.get_string(), "anchor!?")
    assert_eq(hits.val, 1)
  }
}

///|
test "deep weak observers follow children inserted after an empty quotation" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("array")
  let links = doc.get_or_insert_map("links")
  let link = weak(
    links.insert_input("quote", WeakLink(array.quote(Unbounded, Unbounded))),
  )
  let paths = []
  link.observe_deep("children", fn(events, _) {
    for event in events {
      if event is Map(_) {
        paths.push(event.path().iter().map(fn(p) { p.to_json() }).to_array())
      }
    }
  })
  let child = array.insert_map(0)
  child.insert("ready", Bool(true))
  assert_eq(paths, [[Json(0)]])
  array.remove(0)
  let replacement = array.insert_map(0)
  replacement.insert("ready", Bool(false))
  assert_eq(paths, [[Json(0)], [Json(0)]])
}
