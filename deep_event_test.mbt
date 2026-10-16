///|
test "deep paths are relative, use final sequence positions and survive later commits" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let list = root.insert_array("list")
  let row = list.insert_map(0)
  let title = row.insert_text("title")
  title.insert(0, "a")
  let root_paths : Array[Json] = []
  let list_paths : Array[Json] = []
  let retained : Array[@yrs.Event] = []
  root.observe_deep("root", fn(events, _) {
    for event in events {
      root_paths.push(
        Json(event.path().iter().map(@yrs.PathSegment::to_json).to_array()),
      )
      retained.push(event)
    }
  })
  list.observe_deep("list", fn(events, _) {
    for event in events {
      list_paths.push(
        Json(event.path().iter().map(@yrs.PathSegment::to_json).to_array()),
      )
    }
  })
  doc.transact(fn(_) {
    title.insert(1, "b")
    list.insert_range(0, [Integer(9L)])
  })
  assert_eq(root_paths, [["list"], ["list", 1, "title"]])
  assert_eq(list_paths, [[], [1, "title"]])
  list.remove_range(0, 1)
  assert_eq(
    Json(retained[1].path().iter().map(@yrs.PathSegment::to_json).to_array()),
    ["list", 1, "title"],
  )
  assert_true(root.unobserve_deep("root"))
  assert_true(list.unobserve_deep("list"))
}

///|
test "deep observers suppress newly created and deleted descendants" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let batches : Array[Json] = []
  root.observe_deep("root", fn(events, _) {
    batches.push(
      Json(
        events
        .iter()
        .map(fn(e) {
          Json(e.path().iter().map(@yrs.PathSegment::to_json).to_array())
        })
        .to_array(),
      ),
    )
  })
  let child = doc.transact(fn(_) {
    let child = root.insert_map("child")
    child.insert("x", Integer(1L))
    child
  })
  assert_eq(batches, [[[]]])
  doc.transact(fn(_) {
    child.insert("x", Integer(2L))
    root.remove("child") |> ignore
  })
  assert_eq(batches, [[[]], [[]]])
  child.insert("x", Integer(3L))
  assert_eq(batches.length(), 2)
}

///|
test "XML observers distinguish attributes from child changes and rich text" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_xml_fragment("xml")
  let element = root.insert_element(0, "p")
  let text = element.as_fragment().insert_text(0)
  text.as_text().insert(0, "hi")
  let children : Array[Bool] = []
  let paths : Array[Int32] = []
  let attrs : Array[Json] = []
  let text_deltas : Array[Json] = []
  element.observe("element", fn(e, _) {
    children.push(e.children_changed())
    paths.push(e.path().length())
  })
  text.observe("text", fn(e, _) {
    attrs.push(e.keys()["lang"].to_json())
    text_deltas.push(Json(e.delta().iter().map(@yrs.Delta::to_json).to_array()))
  })
  element.insert_attribute("class", String("body"))
  doc.transact(fn(_) {
    text.insert_attribute("lang", String("en"))
    text.as_text().insert(2, "!")
    element.as_fragment().insert_element(1, "br") |> ignore
  })
  assert_eq(children, [false, true])
  assert_eq(paths, [0, 0])
  assert_eq(attrs, [{ "action": "add", "new_value": "en" }])
  assert_eq(text_deltas, [[{ "retain": 2 }, { "insert": "!" }]])
  assert_true(element.unobserve("element"))
  assert_true(text.unobserve("text"))
}

///|
test "XML identity events retain child additions and deletions across deep paths" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_xml_fragment("xml")
  let outer = root.insert_element(0, "div")
  let children = outer.as_fragment()
  children.insert_element(0, "old") |> ignore
  let events : Array[@yrs.XmlEvent] = []
  root.observe_deep("ids", fn(batch, _) {
    for event in batch {
      if event is XmlFragment(event) {
        events.push(event)
      }
    }
  })
  doc.transact(fn(_) {
    children.remove(0)
    children.insert_element(0, "kept") |> ignore
    children.insert_element(1, "temporary") |> ignore
    children.remove(1)
  })
  assert_eq(events.length(), 1)
  assert_eq(events[0].added().iter().to_array(), [{ client: 1UL, clock: 2U, }])
  assert_eq(events[0].deleted().iter().to_array(), [{ client: 1UL, clock: 1U, }])
  children.remove(0)
  assert_eq(events[0].added().iter().to_array(), [{ client: 1UL, clock: 2U, }])
  let child = @yrs.Doc(client_id=3UL, guid="identity-test")
  assert_true(child.branch_id() is None)
  doc.get_or_insert_map("docs").insert_doc("child", child) |> ignore
  assert_true(child.branch_id() is Some(Nested(_)))
}
