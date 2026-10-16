///|
struct SavedOrder {
  name : String
  quantities : Array[Int32]
  invoice : Int64
  note : String?
} derive(@json.FromJson, Eq, Debug)

///|
impl @yrs.FromAny for SavedOrder with fn from_any(value) {
  let fields : Map[String, @yrs.Any] = @yrs.from_any(value)
  {
    name: @yrs.from_any(fields.get("name").unwrap_or(Undefined)),
    quantities: @yrs.from_any(fields.get("quantities").unwrap_or(Undefined)),
    invoice: @yrs.from_any(fields.get("invoice").unwrap_or(Undefined)),
    note: @yrs.from_any(fields.get("note").unwrap_or(Undefined)),
  }
}

///|
test "typed reads decode nested shared collections and preserve exact integer values" {
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  let order = root.insert_map("order")
  order.insert("name", String("Moon"))
  order.insert("invoice", Integer(9223372036854775807L))
  order.insert("note", Null)
  let quantities = order.insert_array("quantities")
  quantities.push_back(Value(Integer(3L))) |> ignore
  quantities.push_back(Value(Integer(7L))) |> ignore
  let decoded : SavedOrder = root.get_as("order")
  assert_eq(decoded, {
    name: "Moon",
    quantities: [3, 7],
    invoice: 9223372036854775807L,
    note: None,
  })
  let quantity : Int32 = quantities.get_as(1)
  assert_eq(quantity, 7)
  let absent : SavedOrder? = root.get_as("absent")
  let outside : Int32? = quantities.get_as(20)
  assert_eq(absent, None)
  assert_eq(outside, None)
  quantities.push_back(Value(String("wrong"))) |> ignore
  try {
    let _ : Int32 = quantities.get_as(2)
  } catch {
    _ => ()
  } noraise {
    _ => fail("wrong type was accepted")
  }
  order.insert("invoice", String("wrong"))
  try {
    let _ : SavedOrder = root.get_as("order")
  } catch {
    _ => ()
  } noraise {
    _ => fail("nested mismatch was accepted")
  }
}

///|
test "typed reads keep binary buffers and separate native JSON conventions" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("root")
  map.insert("blob", Buffer(b"\x00\xff\x08"))
  let bytes : Bytes = map.get_as("blob")
  assert_eq(bytes, b"\x00\xff\x08")
  map.insert("id", String("9223372036854775807"))
  let json_id : Int64 = map.get_json_as("id")
  assert_eq(json_id, 9223372036854775807L)
  try {
    let _ : Int64 = map.get_as("id")
  } catch {
    @yrs.TypeMismatch(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("numeric strings must not be implicitly parsed")
  }
}

///|
test "typed numeric conversion follows Rust losslessness and saturation at the endpoint" {
  let max : Int64 = @yrs.from_any(Integer(9223372036854775807L))
  let min : Int64 = @yrs.from_any(Integer(-9223372036854775808L))
  assert_eq(max, 9223372036854775807L)
  assert_eq(min, -9223372036854775808L)
  let endpoint : Int64 = @yrs.from_any(Float(9223372036854775808.0))
  assert_eq(endpoint, max)
  let unsigned : UInt32 = @yrs.from_any(Integer(4294967295L))
  assert_eq(unsigned, 0xffff_ffffU)
  let signed_zero : Double = @yrs.from_any(Float(-0.0))
  assert_eq(signed_zero.reinterpret_as_uint64(), 0x8000_0000_0000_0000UL)
  let nan = 0x7ff8_0000_0000_0000UL.reinterpret_as_double()
  let decoded_nan : Double = @yrs.from_any(Float(nan))
  assert_true(decoded_nan != decoded_nan)
  let invalid : Array[@yrs.Any] = [
    Float(1.5),
    Float(nan),
    Float(0x7ff0_0000_0000_0000UL.reinterpret_as_double()),
  ]
  for value in invalid {
    try {
      let _ : Int64 = @yrs.from_any(value)
    } catch {
      @yrs.TypeMismatch(_) => ()
      _ => fail("unexpected numeric error")
    } noraise {
      _ => fail("lossy numeric conversion accepted")
    }
  }
  try {
    let _ : Double = @yrs.from_any(Integer(9007199254740993L))
  } catch {
    @yrs.TypeMismatch(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("integer rounded silently")
  }
}
