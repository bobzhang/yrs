///|
fn[T : @yrs.SharedRef] save_collection_identity(value : T) -> @yrs.Hook[T] {
  value.hook()
}

///|
test "generic collection initialization preserves matching identity and replaces other types" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("root")
  let nested : @yrs.MapRef = map.get_or_init("nested")
  nested.insert("key", Integer(1L))
  let first = doc.state_vector()
  assert_eq(
    map.get_or_init_map("nested").hook(),
    save_collection_identity(nested),
  )
  assert_eq(doc.state_vector(), first)
  let array : @yrs.ArrayRef = map.get_or_init("nested")
  array.push_back(Value(Integer(2L))) |> ignore
  assert_true(nested.hook().get(doc) is None)
  assert_eq(
    map.get_or_init_array("nested").hook(),
    save_collection_identity(array),
  )
  let text : @yrs.Text = map.get_or_init("nested")
  text.insert(0, "a")
  assert_eq(map.get_or_init_text("nested").get_string(), "a")
  assert_true(array.hook().get(doc) is None)
  let fragment : @yrs.XmlFragment = map.get_or_init("nested")
  fragment.insert_text(0).as_text().insert(0, "b")
  let before = doc.state_vector()
  assert_eq(map.get_or_init_xml_fragment("nested").get_string(), "b")
  assert_eq(doc.state_vector(), before)
  assert_true(text.hook().get(doc) is None)
  let xml_text : @yrs.XmlText = map.get_or_init("nested")
  xml_text.as_text().insert(0, "c")
  assert_eq(map.get_or_init_xml_text("nested").get_string(), "c")
  assert_true(fragment.hook().get(doc) is None)
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(doc.encode_state_as_update_v2())
  assert_eq(
    save_collection_identity(xml_text).get(peer).unwrap().get_string(),
    "c",
  )
}

///|
struct ApplicationNote {
  text : @yrs.Text
}

///|
impl @yrs.SharedRef for ApplicationNote with fn from_branch(doc, id) {
  @yrs.Text::from_branch(doc, id).map(fn(text) { { text, } })
}

///|
impl @yrs.SharedRef for ApplicationNote with fn hook(self) {
  @yrs.Hook(self.text.hook().id())
}

///|
impl @yrs.DefaultPrelim for ApplicationNote with fn default_prelim() {
  @yrs.Text::default_prelim()
}

///|
impl @yrs.DefaultPrelim for ApplicationNote with fn from_out(value) {
  @yrs.Text::from_out(value).map(fn(text) { { text, } })
}

///|
test "applications can initialize and resolve their own typed collection wrappers" {
  let doc = @yrs.Doc(client_id=1UL)
  let map = doc.get_or_insert_map("root")
  let note : ApplicationNote = map.get_or_init("note")
  note.text.insert(0, "custom")
  let handle = save_collection_identity(note)
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  assert_eq(handle.get(peer).unwrap().text.get_string(), "custom")
  let again : ApplicationNote = map.get_or_init("note")
  assert_eq(save_collection_identity(again), handle)
}
