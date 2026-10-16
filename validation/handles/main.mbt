///|
fn run(input : String) -> String raise {
  let request = @json.parse(input)
  if request is { "uuid": Array(values), .. } {
    let value = Bytes::from_array(
      values.map(fn(v) {
        guard v is Number(n, ..) else { abort("byte") }
        n.to_int().to_byte()
      }),
    )
    return Json(@yrs.uuid_v4_from(value)).stringify()
  }
  guard request is Array([Number(client, ..), String(name), gc]) else {
    abort("input")
  }
  let doc = @yrs.Doc(client_id=client.to_uint64(), skip_gc=gc != Json(true))
  let root : @yrs.Root[@yrs.MapRef] = Root(name)
  guard root.get(doc) is None else { abort("root exists") }
  let map = root.get_or_create(doc)
  let text = map.insert_text("note")
  text.insert(0, "Moon🌙")
  let root_hook = map.hook()
  let nested_hook = text.hook()
  let peer = @yrs.Doc(client_id=client.to_uint64() + 1UL)
  peer.apply_update_v2(doc.encode_state_as_update_v2())
  let remote = nested_hook.get(peer).unwrap().get_string()
  guard nested_hook.into_nested().unwrap().get(peer).unwrap().get_string() ==
    remote else {
    abort("nested")
  }
  map.remove("note")
  let replacement = map.insert_text("note")
  replacement.insert(0, "new")
  peer.apply_update_v1(doc.encode_state_as_update_v1())
  let encoded = nested_hook.to_json()
  let decoded : @yrs.Hook[@yrs.Text] = @yrs.Hook::from_json(encoded)
  guard decoded.id() == nested_hook.id() else { abort("json") }
  let missing_tag = try {
    let _ : @yrs.Hook[@yrs.Text] = @yrs.Hook::from_json({
      "id": nested_hook.id().to_json(),
    })
    true
  } catch {
    _ => false
  }
  (
    {
      "root": root_hook.to_json(),
      "nested": encoded,
      "replacement": replacement.hook().to_json(),
      "before": Json(remote),
      "after": Json(replacement.hook().get(peer).unwrap().get_string()),
      "old_missing": Json(
        nested_hook.get(doc) is None && nested_hook.get(peer) is None,
      ),
      "root_present": Json(root.get(peer) is Some(_)),
      "nested_json_without_tag_accepted": Json(missing_tag),
    } : Json).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
