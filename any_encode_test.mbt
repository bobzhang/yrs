///|
priv struct SavedRecord {
  id : UInt64
  name : String
  payload : Bytes
} derive(Eq, Debug)

///|
priv struct TrackedValue {
  value : Int32
  visits : Array[Int32]
  reject : Bool
}

///|
impl @yrs.ToAny for TrackedValue with fn to_any(self) {
  self.visits.push(self.value)
  if self.reject {
    raise @yrs.Custom("rejected \{self.value}")
  }
  Integer(self.value.to_int64())
}

///|
test "read-only array serialization visits each value once in order" {
  let visits = []
  let empty : ReadOnlyArray[TrackedValue] = []
  assert_eq(@yrs.to_any(empty), Array([]))
  let values : ReadOnlyArray[TrackedValue] = [
    { value: 3, visits, reject: false, },
    { value: 1, visits, reject: false, },
    { value: 2, visits, reject: false, },
  ]
  assert_eq(@yrs.to_any(values), Array([Integer(3L), Integer(1L), Integer(2L)]))
  assert_eq(visits, [3, 1, 2])
}

///|
test "read-only array serialization stops at the first error" {
  for rejected in [0, 1] {
    let visits = []
    let values = ReadOnlyArray::makei(3, value => {
      value,
      visits,
      reject: value == rejected,
    })
    try @yrs.to_any(values) catch {
      @yrs.Custom(message) => assert_eq(message, "rejected \{rejected}")
      _ => fail("unexpected serialization error")
    } noraise {
      _ => fail("expected serialization error")
    }
    assert_eq(visits, Array::makei(rejected + 1, i => i))
  }
}

///|
impl @yrs.ToAny for SavedRecord with fn to_any(self) {
  Object([
    ("id", @yrs.to_any(self.id)),
    ("name", @yrs.to_any(self.name)),
    ("payload", @yrs.to_any(self.payload)),
  ])
}

///|
impl @yrs.FromAny for SavedRecord with fn from_any(value) {
  guard value is Object(entries) else { raise @yrs.TypeMismatch("SavedRecord") }
  let fields = Map::from_array(entries.iter().to_array())
  {
    id: @yrs.from_any(fields.get("id").unwrap_or(Null)),
    name: @yrs.from_any(fields.get("name").unwrap_or(Null)),
    payload: @yrs.from_any(fields.get("payload").unwrap_or(Null)),
  }
}

///|
test "typed application records survive CRDT updates without JSON precision loss" {
  let record : SavedRecord = {
    id: 9223372036854775807UL,
    name: "Moon🌙",
    payload: b"\x00\xff",
  }
  let doc = @yrs.Doc(client_id=1UL)
  doc.get_or_insert_map("records").insert("first", @yrs.to_any(record))
  for v2 in [false, true] {
    let peer = @yrs.Doc(client_id=2UL)
    if v2 {
      peer.apply_update_v2(doc.encode_state_as_update_v2())
    } else {
      peer.apply_update_v1(doc.encode_state_as_update_v1())
    }
    let restored : SavedRecord = peer
      .get_or_insert_map("records")
      .get_as("first")
    assert_eq(restored, record)
  }
  let invalid = SavedRecord::{ ..record, id: 9223372036854775808UL, }
  try @yrs.to_any([record, invalid]) catch {
    @yrs.UnrepresentableInt => ()
    _ => fail("unexpected serialization error")
  } noraise {
    _ => fail("unsigned overflow was silently serialized")
  }
}

///|
test "typed serialization distinguishes raw bytes and numeric arrays" {
  assert_eq(@yrs.to_any(b"\x00\xff"), Buffer(b"\x00\xff"))
  assert_eq(
    @yrs.to_any([(0).to_byte(), (255).to_byte()]),
    Array([Integer(0L), Integer(255L)]),
  )
  assert_eq(@yrs.to_any('🌙'), String("🌙"))
  assert_eq(@yrs.to_any((65535).to_uint16()), Integer(65535L))
  let values : ReadOnlyArray[Int64?] = [Some(1L), None]
  assert_eq(@yrs.to_any(values), Array([Integer(1L), Null]))
  assert_eq(
    @yrs.to_any(("hello", values)),
    Array([String("hello"), Array([Integer(1L), Null])]),
  )
}

///|
test "Any object serialization keeps key order and normalizes the last duplicate" {
  let object : @yrs.Any = Object([
    ("first", String("overwritten")),
    ("second", Float(2.0)),
    ("first", Undefined),
  ])
  guard @yrs.to_any(object) is Object(entries) else {
    fail("expected an object")
  }
  assert_eq(entries, [("first", Null), ("second", Integer(2L))])
  guard object is Object(original) else { fail("expected an object") }
  assert_eq(original, [
    ("first", String("overwritten")),
    ("second", Float(2.0)),
    ("first", Undefined),
  ])
}
