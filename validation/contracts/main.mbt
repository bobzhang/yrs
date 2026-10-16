///|
fn integer(value : Json) -> Int32 {
  guard value is Number(n, ..) else { abort("integer") }
  n.to_int()
}

///|
fn string(value : Json) -> String {
  guard value is String(s) else { abort("string") }
  s
}

///|
fn array(value : Json) -> Array[Json] {
  guard value is Array(a) else { abort("array") }
  a
}

///|
fn ranges(set : @yrs.IdSet) -> Json {
  Json(
    set
    .ranges()
    .map(fn(r) { Json([Json(r.0.to_string()), Json(r.1), Json(r.2)]) }),
  )
}

///|
fn set_metadata(set : @yrs.IdSet) -> Json {
  {
    "clients": Json(set.client_ids().map(fn(c) { Json(c.to_int()) })),
    "length": Json(set.length()),
    "empty": Json(set.is_empty()),
    "get": Json(
      [
        for c in 1..<9 => {
          match set.get(c.to_uint64()) {
            None => Json::null()
            Some(ranges) =>
              Json(ranges.map(fn(r) { Json([Json(r.0), Json(r.1)]) }))
          }
        }
      ],
    ),
  }
}

///|
fn parse_set(value : Json) -> @yrs.IdSet {
  @yrs.IdSet(
    ranges=array(value).map(fn(r) {
      let r = array(r)
      (
        integer(r[0]).to_uint64(),
        integer(r[1]).reinterpret_as_uint(),
        integer(r[2]).reinterpret_as_uint(),
      )
    }),
  )
}

///|
fn bytes(value : Bytes) -> Json {
  Json(value.iter().map(fn(b) { Json(b.to_int()) }).to_array())
}

///|
fn record(
  events : Array[Json],
  name : String,
  event : @yrs.UndoEvent[Int32],
) -> Unit {
  let parents = event
    .changed_parent_types()
    .iter()
    .map(fn(value) {
      match value.branch_id().unwrap() {
        Root(name) => Json([Json("root"), Json(name)])
        Nested(id) =>
          Json([Json("nested"), Json(id.client.to_string()), Json(id.clock)])
      }
    })
    .to_array()
  parents.sort_by(fn(a, b) { a.stringify().compare(b.stringify()) })
  events.push(
    Json([
      Json(name),
      Json(if event.kind() == Undo { "Undo" } else { "Redo" }),
      Json(event.meta),
      Json(parents),
    ]),
  )
  if name != "popped" {
    event.set_meta(event.meta + 1)
  }
}

///|
fn subscribe(manager : @yrs.UndoManager[Int32], events : Array[Json]) -> Unit {
  manager.observe_item_added("added", fn(e, _) { record(events, "added", e) })
  manager.observe_item_updated("updated", fn(e, _) {
    record(events, "updated", e)
  })
  manager.observe_item_popped("popped", fn(e, _) { record(events, "popped", e) })
}

///|
fn run(input : String) -> String raise {
  let request = array(@json.parse(input))
  let result : Json = match string(request[0]) {
    "sets" => {
      let a = parse_set(request[1])
      let b = parse_set(request[2])
      let wire = Bytes::from_array([b'\x00'] + a.encode_v1().to_array())
      let update = @yrs.Update::decode_v1(wire)
      let snap = @yrs.Snapshot(delete_set=a)
      let removed = a.merge(@yrs.IdSet())
      removed.remove_range({ client: 7UL, clock: 0U, }, 0U)
      {
        "removed": set_metadata(removed),
        "update_empty": Json(update.is_empty()),
        "update_meta": Json(
          [
            update.delete_set(),
            @yrs.Update::decode_v2(update.encode_v2()).delete_set(),
            @yrs.Update::decode_v1(@yrs.merge_updates_v1([wire, b"\x00\x00"])).delete_set(),
            @yrs.Update::decode_v1(@yrs.diff_updates_v1(wire, b"\x00")).delete_set(),
            snap.delete_set(),
            @yrs.Snapshot::decode_v1(snap.encode_v1()).delete_set(),
            @yrs.Snapshot::decode_v2(snap.encode_v2()).delete_set(),
          ].map(set_metadata),
        ),
        "a": ranges(a),
        "union": ranges(a.merge(b)),
        "diff": ranges(a.diff(b)),
        "intersect": ranges(a.intersect(b)),
        "v1": bytes(a.encode_v1()),
        "v2": bytes(a.encode_v2()),
        "json": a.to_json(),
        "meta": Json(
          [
            a,
            a.merge(b),
            a.diff(b),
            a.intersect(b),
            @yrs.IdSet::decode_v1(a.encode_v1()),
            @yrs.IdSet::decode_v2(a.encode_v2()),
            @yrs.IdSet::from_json(a.to_json()),
          ].map(set_metadata),
        ),
      }
    }
    "undo" | "restore" => {
      let restoring = string(request[0]) == "restore"
      let mut doc = @yrs.Doc(client_id=1UL, guid="A")
      let mut root = doc.get_or_insert_map("root")
      let mut text = root.insert_text("text")
      let mut manager : @yrs.UndoManager[Int32] = UndoManager(
        clock=fn() { 100UL },
        capture_timeout_millis=0xffff_ffff_ffff_ffffUL,
      )
      manager.expand_scope(Map(root))
      if restoring {
        doc = @yrs.Doc(client_id=integer(request[1]).to_uint64(), guid="A")
        doc.apply_update_v1(
          Bytes::from_array(
            array(request[2]).map(fn(v) { integer(v).to_byte() })[:],
          ),
        )
        root = doc.get_or_insert_map("root")
        guard root.get("text") is Some(Text(t)) else { abort("text") }
        text = t
        manager = @yrs.UndoManager(
          clock=fn() { 100UL },
          capture_timeout_millis=0xffff_ffff_ffff_ffffUL,
          init_undo_stack=array(request[3]).map(fn(s) raise {
            @yrs.StackItem::from_json(s, doc, fn(v) { integer(v) })
          }),
          init_redo_stack=array(request[4]).map(fn(s) raise {
            @yrs.StackItem::from_json(s, doc, fn(v) { integer(v) })
          }),
        )
        manager.expand_scope(Map(root))
      }
      let events = []
      subscribe(manager, events)
      let rows = []
      for command in array(request[if restoring { 5 } else { 1 }]) {
        let command = array(command)
        let mut changed : Json = Json::null()
        match string(command[0]) {
          "i" =>
            text.insert(
              integer(command[1]) % (text.length() + 1),
              string(command[2]),
            )
          "d" =>
            if text.length() > 0 {
              let at = integer(command[1]) % text.length()
              text.remove_range(at, integer(command[2]).min(text.length() - at))
            }
          "reset" => manager.reset()
          "undo" => changed = Json(manager.undo())
          "redo" => changed = Json(manager.redo())
          "reload" => {
            let state = doc.encode_state_as_update_v1()
            let undo = manager
              .undo_stack()
              .iter()
              .map(fn(s) { s.to_json(fn(m) { Json(m) }) })
              .to_array()
            let redo = manager
              .redo_stack()
              .iter()
              .map(fn(s) { s.to_json(fn(m) { Json(m) }) })
              .to_array()
            manager.destroy()
            doc = @yrs.Doc(client_id=doc.client_id() + 1UL, guid="A")
            doc.apply_update_v1(state)
            root = doc.get_or_insert_map("root")
            guard root.get("text") is Some(Text(t)) else { abort("text") }
            text = t
            manager = @yrs.UndoManager(
              clock=fn() { 100UL },
              capture_timeout_millis=0xffff_ffff_ffff_ffffUL,
              init_undo_stack=undo.map(fn(s) raise {
                @yrs.StackItem::from_json(s, doc, fn(v) { integer(v) })
              }),
              init_redo_stack=redo.map(fn(s) raise {
                @yrs.StackItem::from_json(s, doc, fn(v) { integer(v) })
              }),
            )
            manager.expand_scope(Map(root))
            subscribe(manager, events)
          }
          _ => abort("unknown command")
        }
        rows.push({
          "text": Json(text.get_string()),
          "changed": changed,
          "undo": Json(
            manager
            .undo_stack()
            .iter()
            .map(fn(s) { s.to_json(fn(m) { Json(m) }) })
            .to_array(),
          ),
          "redo": Json(
            manager
            .redo_stack()
            .iter()
            .map(fn(s) { s.to_json(fn(m) { Json(m) }) })
            .to_array(),
          ),
          "events": Json(events.copy()),
        })
        events.clear()
      }
      Json(rows)
    }
    _ => abort("unknown case")
  }
  result.stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
