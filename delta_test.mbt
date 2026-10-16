///|
test "generic delta mapping preserves operation shape and maps only inserts" {
  let calls = Ref(0)
  let source : Array[@yrs.DeltaOf[Int32]] = [
    Retain(3, [("bold", Bool(true))]),
    Inserted(42, [("color", String("red"))]),
    Deleted(2),
  ]
  let mapped : Array[@yrs.DeltaOf[String]] = source.map(d => {
    d.map(n => {
      calls.val += 1
      n.to_string()
    })
  })
  assert_eq(calls.val, 1)
  guard mapped[0] is Retain(3, attributes) else { fail("retain changed") }
  assert_eq(attributes.iter().to_array(), [("bold", @yrs.Any::Bool(true))])
  guard mapped[1] is Inserted("42", attributes) else { fail("insert changed") }
  assert_eq(attributes.iter().to_array(), [("color", @yrs.Any::String("red"))])
  guard mapped[2] is Deleted(2) else { fail("delete changed") }
}

///|
test "observed text deltas replay through detached generic preliminary mapping" {
  let source = @yrs.Doc(client_id=1UL)
  let text = source.get_or_insert_text("text")
  let target = @yrs.Doc(client_id=2UL).get_or_insert_text("text")
  let pending : Array[@yrs.TextDelta] = []
  text.observe("copy", fn(event, _) {
    for delta in event.delta() {
      pending.push(delta.to_input())
    }
  })
  let embedded : Ref[@yrs.MapRef?] = Ref(None)
  source.transact(fn(_) {
    text.insert_with_attributes(0, "Moon", [("bold", Bool(true))])
    guard text.insert_embed_input(
        4,
        Map([("caption", Value(String("original")))]),
      )
      is Map(map) else {
      abort("map embed")
    }
    embedded.val = Some(map)
  })
  target.apply_delta(pending)
  pending.clear()
  assert_eq(
    target.to_delta().map(@yrs.TextChunk::to_json),
    text.to_delta().map(@yrs.TextChunk::to_json),
  )
  embedded.val.unwrap().insert("caption", String("changed"))
  assert_true(
    target.to_delta().map(@yrs.TextChunk::to_json) !=
    text.to_delta().map(@yrs.TextChunk::to_json),
  )
  // Input aliases retain their constructors and can be used by generic mappers.
  target.apply_delta([
    @yrs.TextDelta::retain(1),
    @yrs.TextDelta::delete(2),
    @yrs.TextDelta::insert_with(Value(String("X")), [("bold", Bool(false))]),
    @yrs.TextDelta::insert(Value(String("Y"))),
  ])
  assert_eq(target.get_string(), "MXYn")
  let roundtrip : @yrs.TextDelta = @yrs.Delta::Inserted(
    @yrs.Out::Value(@yrs.Any::Integer(7L)),
    [],
  ).map(@yrs.Out::to_input)
  guard roundtrip is @yrs.TextDelta::Inserted(Value(Integer(7L)), []) else {
    fail("specialized aliases lost constructors")
  }
}
