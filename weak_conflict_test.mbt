///|
test "conflict-deleted weak quotations do not retain deep subscriptions" {
  for v2 in [false, true] {
    for skip_gc in [false, true] {
      let a = @yrs.Doc(client_id=1UL, skip_gc~)
      let b = @yrs.Doc(client_id=2UL, skip_gc~)
      let array = a.get_or_insert_array("array")
      array.insert_map(0).insert("seed", String("initial"))
      if v2 {
        b.apply_update_v2(a.encode_state_as_update_v2())
      } else {
        b.apply_update_v1(a.encode_state_as_update_v1())
      }
      a
      .get_or_insert_map("links")
      .insert_input("key", WeakLink(array.quote(Included(0), Included(0))))
      |> ignore
      let links = b.get_or_insert_map("links")
      links.insert("key", String("winner"))
      if v2 {
        b.apply_update_v2(a.encode_state_as_update_v2())
      } else {
        b.apply_update_v1(a.encode_state_as_update_v1())
      }
      let events = Ref(0)
      links.observe_deep("watch", fn(changes, _) {
        events.val += changes.length()
      })
      guard b.get_or_insert_array("array").get(0) is Some(Map(child)) else {
        fail("missing nested map")
      }
      child.insert("value", String("changed"))
      assert_eq(links.get("key").unwrap().to_json(), Json("winner"))
      assert_eq(events.val, 0)
      // Ordinary changes to the observed map still notify.
      links.insert("live", Bool(true))
      assert_eq(events.val, 1)
    }
  }
}
