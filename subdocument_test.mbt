///|
test "subdocument identity, load events and separate replication" {
  let parent = @yrs.Doc(client_id=1UL, collection_id="workspace")
  let events : Array[(Array[String], Array[String], Array[String])] = []
  parent.observe_subdocs("events", fn(e, _) {
    events.push(
      (
        e.added().iter().map(@yrs.Doc::guid).to_array(),
        e.removed().iter().map(@yrs.Doc::guid).to_array(),
        e.loaded().iter().map(@yrs.Doc::guid).to_array(),
      ),
    )
  })
  let child = @yrs.Doc(client_id=99UL, guid="child")
  child.get_or_insert_text("body").insert(0, "private to child")
  parent.get_or_insert_map("files").insert_doc("a", child) |> ignore
  assert_eq(child.client_id(), 1UL)
  assert_eq(child.collection_id(), Some("workspace"))
  assert_eq(child.parent_doc().unwrap().client_id(), 1UL)
  assert_eq(events, [(["child"], [], ["child"])])
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(parent.encode_state_as_update_v2())
  guard peer.get_or_insert_map("files").get("a") is Some(Subdoc(remote)) else {
    abort("subdocument")
  }
  assert_eq(remote.guid(), "child")
  assert_false(remote.should_load())
  assert_eq(remote.get_or_insert_text("body").get_string(), "")
  remote.apply_update_v1(child.encode_state_as_update_v1())
  assert_eq(remote.get_or_insert_text("body").get_string(), "private to child")
  let loaded : Array[String] = []
  peer.observe_subdocs("loads", fn(e, _) {
    for d in e.loaded() {
      loaded.push(d.guid())
    }
  })
  remote.load()
  remote.load()
  assert_eq(loaded, ["child"])
  assert_true(remote.should_load())
}

///|
test "duplicate GUIDs, auto load, destroy replacement and nested removal" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("files")
  let a = @yrs.Doc(client_id=2UL, guid="same", auto_load=true)
  let b = @yrs.Doc(client_id=3UL, guid="same", should_load=false)
  array.insert_doc(0, a) |> ignore
  array.insert_doc(1, b) |> ignore
  assert_eq(doc.subdocs().length(), 2)
  assert_eq(doc.subdoc_guids().length(), 1)
  let destroyed : Array[String] = []
  a.observe_destroy("destroy", fn(d) { destroyed.push(d.guid()) })
  a.destroy()
  assert_eq(destroyed, ["same"])
  assert_true(a.parent_doc() is None)
  guard array.to_array()[0] is Subdoc(replacement) else { abort("replacement") }
  assert_false(replacement.should_load())
  assert_true(replacement.auto_load())
  assert_eq(doc.subdocs().length(), 2)
  array.remove_range(0, 2)
  assert_eq(doc.subdocs().length(), 0)
  assert_true(b.parent_doc() is None)
}

///|
test "subdocuments appear in array events and remote auto loads" {
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("files")
  let changes : Array[Json] = []
  array.observe("delta", fn(e, _) {
    changes.push(Json(e.delta().iter().map(@yrs.Change::to_json).to_array()))
  })
  array.insert_doc(0, @yrs.Doc(client_id=2UL, guid="auto", auto_load=true))
  |> ignore
  assert_eq(changes[0].stringify(), "[{\"insert\":[{\"guid\":\"auto\"}]}]")
  let remote = @yrs.Doc(client_id=3UL)
  let loads : Array[String] = []
  remote.observe_subdocs("load", fn(e, _) {
    for d in e.loaded() {
      loads.push(d.guid())
    }
  })
  remote.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(loads, ["auto"])
  assert_eq(remote.subdocs()[0].client_id(), 3UL)
}
