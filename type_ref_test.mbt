///|
test "shared-type descriptors compose with update columns and raw metadata" {
  let id : @yrs.Id = { client: 9007199254740991UL, clock: 0xffffffffU, }
  let descriptors : Array[@yrs.TypeRef] = [
    Array,
    Map,
    Text,
    XmlElement("🌙"),
    XmlFragment,
    XmlHook,
    XmlText,
    SubDoc,
    Undefined,
  ]
  for parent in [@yrs.IndexScope::Root("root🌙"), Nested(id)] {
    for start in [parent, @yrs.IndexScope::Relative(id)] {
      for end in [parent, @yrs.IndexScope::Relative(id)] {
        for start_assoc in [@yrs.Assoc::Before, After] {
          for end_assoc in [@yrs.Assoc::Before, After] {
            descriptors.push(
              WeakLink(
                @yrs.LinkSource(
                  @yrs.StickyIndex(scope=start, assoc=start_assoc),
                  @yrs.StickyIndex(scope=end, assoc=end_assoc),
                ),
              ),
            )
          }
        }
      }
    }
  }
  for v2 in [false, true] {
    let encoder : &@yrs.Encoder = if v2 {
      (@yrs.EncoderV2() : &@yrs.Encoder)
    } else {
      (@yrs.EncoderV1() : &@yrs.Encoder)
    }
    for value in descriptors {
      value.encode(encoder)
    }
    @yrs.Write::write_var_uint(encoder, 12345UL)
    let bytes = encoder.to_bytes()
    let decoder : &@yrs.Decoder = if v2 {
      (@yrs.DecoderV2(bytes) : &@yrs.Decoder)
    } else {
      (@yrs.DecoderV1(bytes) : &@yrs.Decoder)
    }
    for value in descriptors {
      assert_eq(@yrs.TypeRef::decode(decoder), value)
    }
    assert_eq(@yrs.Read::read_var_uint(decoder), 12345UL)
    assert_eq(decoder.read_to_end(), b"")
  }
  for invalid in [b"\x08", b"\x10", b"\x07\x40", b"\x03"] {
    try @yrs.TypeRef::decode_v1(invalid) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid or truncated descriptor")
    }
  }
}

///|
test "output descriptors distinguish typed collections from unresolved roots" {
  let source = @yrs.Doc(client_id=1UL)
  let map = source.get_or_insert_map("root")
  let value = @yrs.Out::Map(map)
  assert_eq(value.type_ref(), Some(@yrs.TypeRef::Map))
  assert_eq(@yrs.Out::Value(Null).type_ref(), None)
  let child = map.insert_input("xml", XmlElement("p", [], []))
  assert_eq(child.type_ref(), Some(@yrs.TypeRef::XmlElement("p")))
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(source.encode_state_as_update_v1())
  let untyped = peer.root_refs()[0].1
  assert_eq(untyped.type_ref(), Some(@yrs.TypeRef::Undefined))
  peer.get_or_insert_map("root") |> ignore
  assert_eq(peer.root_refs()[0].1.type_ref(), Some(@yrs.TypeRef::Map))
}

///|
fn[T : @yrs.RootRef] named_root(name : String) -> (@yrs.TypeRef, @yrs.Root[T]) {
  (T::type_ref(), T::root(name))
}

///|
test "generic root descriptors expose static type metadata and resolve on peers" {
  let doc = @yrs.Doc(client_id=1UL)
  let (kind, root) : (@yrs.TypeRef, @yrs.Root[@yrs.Text]) = named_root("body")
  assert_eq(kind, @yrs.TypeRef::Text)
  root.get_or_create(doc).insert(0, "shared root")
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(root.get(peer).unwrap().get_string(), "shared root")
  assert_eq(@yrs.ArrayRef::type_ref(), @yrs.TypeRef::Array)
  assert_eq(@yrs.MapRef::type_ref(), @yrs.TypeRef::Map)
  assert_eq(@yrs.XmlFragment::type_ref(), @yrs.TypeRef::XmlFragment)
  @yrs.MapRef::root("map").get_or_create(doc).insert("value", Integer(42L))
  assert_eq(doc.get_or_insert_map("map").to_json(), { "value": 42 })
}
