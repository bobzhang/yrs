///|
struct AppTitle(String)

///|
impl @yrs.FromOut for AppTitle with fn try_from_out(value) {
  let title : Result[String, @yrs.Out] = value.cast()
  title.map(fn(value) { AppTitle(value) })
}

///|
fn[T] cast_is_accepted(result : Result[T, @yrs.Out]) -> Bool {
  result is Ok(_)
}

///|
test "direct primitive casts preserve rejected values and Rust narrowing" {
  let narrow : Result[Int32, @yrs.Out] = @yrs.Out::Value(Integer(4294967297L)).cast()
  guard narrow is Ok(1) else { fail("integer cast should narrow") }
  let unsigned : Result[UInt32, @yrs.Out] = @yrs.Out::Value(Integer(-1L)).cast()
  guard unsigned is Ok(0xffffffffU) else { fail("unsigned cast should wrap") }
  let rejected : Result[Int32, @yrs.Out] = @yrs.Out::Value(Float(1.5)).cast()
  guard rejected is Err(Value(Float(1.5))) else { fail("original value lost") }
  let title : Result[AppTitle, @yrs.Out] = @yrs.Out::Value(String("MoonBit")).cast()
  guard title is Ok(AppTitle("MoonBit")) else { fail("custom cast failed") }
  let bytes : Result[Bytes, @yrs.Out] = @yrs.Out::Value(Buffer(b"payload")).cast()
  guard bytes is Ok(value) else { fail("buffer cast failed") }
  assert_eq(value, b"payload")
}

///|
test "shared output casts preserve exact type and live identity" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let source = doc.get_or_insert_text("source")
  source.insert(0, "quote")
  let inputs : Array[@yrs.In] = [
    Text([]),
    Array([]),
    Map([]),
    XmlFragment([]),
    XmlText([], []),
    XmlElement("p", [], []),
    WeakLink(source.quote(Unbounded, Unbounded)),
    Subdoc(@yrs.Doc(client_id=2UL, guid="child")),
  ]
  for i, input in inputs {
    let value = root.insert_input(i.to_string(), input)
    let accepted = [
      cast_is_accepted((value.cast() : Result[@yrs.Text, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.ArrayRef, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.MapRef, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.XmlFragment, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.XmlText, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.XmlElement, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.WeakRef, @yrs.Out])),
      cast_is_accepted((value.cast() : Result[@yrs.Doc, @yrs.Out])),
    ]
    for j, accepted in accepted {
      assert_eq(accepted, i == j)
    }
    assert_eq(
      cast_is_accepted((value.cast() : Result[@yrs.XmlNode, @yrs.Out])),
      i >= 3 && i <= 5,
    )
    let primitive : Result[String, @yrs.Out] = value.cast()
    guard primitive is Err(original) else {
      fail("shared value cast to primitive")
    }
    assert_eq(original.branch_id(), value.branch_id())
    if i == 0 {
      let text : Result[@yrs.Text, @yrs.Out] = original.cast()
      guard text is Ok(text) else { fail("typed handle missing") }
      text.insert(0, "same branch")
      assert_eq(value.to_string(), "same branch")
    }
  }
}

///|
test "typed weak dereference distinguishes missing entries and failed casts" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("root")
  map.insert("source", String("hello"))
  let prelim = map.link("source").unwrap()
  let value = map.insert_input("link", WeakLink(prelim))
  guard value is WeakLink(link) else { fail("weak link missing") }
  let initial : Result[String, @yrs.Out?] = link.try_deref()
  guard initial is Ok("hello") else { fail("initial value missing") }
  let detached : Result[String, @yrs.Out?] = prelim.try_deref(doc)
  guard detached is Ok("hello") else { fail("preliminary value missing") }
  map.insert("source", Bool(true))
  let wrong_type : Result[String, @yrs.Out?] = link.try_deref()
  guard wrong_type is Err(Some(Value(Bool(true)))) else {
    fail("type failure did not preserve original value")
  }
  map.remove("source")
  let missing : Result[String, @yrs.Out?] = link.try_deref()
  guard missing is Err(None) else {
    fail("missing entry confused with type failure")
  }
}
