///|
test "legacy JSON and opaque shared branches retain clocks and child content" {
  for reference in [5, 9, 15] {
    let items : Array[RawItem] = [
      {
        id: { client: 1UL, clock: 0U, },
        origin: None,
        right_origin: None,
        parent: Some(Root("items")),
        parent_sub: None,
        content: LegacyJson(
          ContentBuffer([
            Object([("x", Integer(1L))]),
            Undefined,
            String("hello"),
          ]),
        ),
      },
      {
        id: { client: 1UL, clock: 3U, },
        origin: Some({ client: 1UL, clock: 2U, }),
        right_origin: None,
        parent: None,
        parent_sub: None,
        content: Shared(SharedOpaque(reference)),
      },
      {
        id: { client: 1UL, clock: 4U, },
        origin: None,
        right_origin: None,
        parent: Some(Nested({ client: 1UL, clock: 3U, })),
        parent_sub: Some("key"),
        content: Values(ContentBuffer([String("kept")])),
      },
    ]
    let source = encode_raw_update(items, Map([]))
    let doc = Doc(client_id=2UL)
    doc.apply_update_v1(source)
    let array = doc.get_or_insert_array("items")
    assert_eq(array.length(), 4)
    array.remove_range(1, 1)
    assert_eq(array.to_array()[0].to_json(), ({ "x": Json(1) } : Json))
    assert_eq(array.to_array()[1].to_json(), Json("hello"))
    let peer = Doc(client_id=3UL)
    peer.apply_update_v2(doc.encode_state_as_update_v2())
    guard peer.get_or_insert_array("items").to_array()[2]
      is UndefinedRef(branch) else {
      abort("opaque branch")
    }
    assert_eq(branch.type_ref(), reference)
    assert_eq(branch.as_map().get("key").unwrap().to_json(), Json("kept"))
    assert_eq(peer.state_vector().get(1UL), 5U)
  }
}
