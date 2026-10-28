///|
fn path_member(value : Out?, doc : Doc?, key : String) -> Out? {
  match value {
    None =>
      match doc {
        Some(doc) => BranchId::Root(key).get(doc)
        None => None
      }
    Some(Value(Object(fields))) =>
      Map::from_array(fields.iter().to_array())
      .get(key)
      .map(fn(value) { Out::Value(value) })
    Some(Map(map)) => map.get(key)
    Some(XmlElement(xml)) => xml.get_attribute(key)
    Some(XmlText(xml)) => xml.get_attribute(key)
    Some(UndefinedRef(value)) => value.as_map().get(key)
    _ => None
  }
}

///|
fn path_sequence(value : Out?) -> Array[Out]? {
  match value {
    Some(Value(Array(values))) =>
      Some(values.iter().map(fn(value) { Out::Value(value) }).to_array())
    Some(Array(array)) => Some(array.to_array())
    Some(XmlElement(xml)) =>
      Some(xml.as_fragment().children().map(XmlNode::as_out))
    Some(XmlFragment(xml)) => Some(xml.children().map(XmlNode::as_out))
    _ => None
  }
}

///|
fn path_at(value : Out?, index : Int32) -> Out? {
  let values = match value {
    Some(UndefinedRef(value)) => value.as_array().to_array()
    _ =>
      match path_sequence(value) {
        Some(values) => values
        None => return None
      }
  }
  let index = if index < 0 { values.length() + index } else { index }
  values.get(index)
}

///|
fn path_children(value : Out?, doc : Doc?) -> Array[Out]? {
  match value {
    None => doc.map(fn(doc) { doc.root_refs().map(fn(entry) { entry.1 }) })
    Some(Value(Object(fields))) =>
      Some(
        Map::from_array(fields.iter().to_array())
        .values()
        .map(fn(value) { Out::Value(value) })
        .to_array(),
      )
    Some(Map(map)) => Some(map.values().to_array())
    Some(UndefinedRef(value)) => {
      let branch = value.doc.branch(value.name)
      Some(
        if branch.head is Some(_) {
          value.as_array().to_array()
        } else {
          value.as_map().values().to_array()
        },
      )
    }
    _ => path_sequence(value)
  }
}

///|
priv struct PathFrame {
  mut value : Out?
  mut index : Int32
  descending : Bool
}

///|
fn JsonPath::evaluate(self : JsonPath, root : Out?, doc : Doc?) -> Array[Out] {
  if self.tokens.is_empty() {
    return []
  }
  let result = []
  let stack : Array[PathFrame] = [{ value: root, index: 0, descending: false, }]
  fn schedule(children : Array[Out], index : Int32, descending : Bool) -> Unit {
    for i = children.length() - 1; i >= 0; i = i - 1 {
      stack.push({ value: Some(children[i]), index, descending, })
    }
  }
  while stack.pop() is Some(frame) {
    let mut failed = false
    let mut branched = false
    while frame.index < self.tokens.length() {
      let token = self.tokens[frame.index]
      frame.index += 1
      match token {
        Root => frame.value = root
        Current => ()
        Member(key) =>
          match path_member(frame.value, doc, key) {
            Some(value) => frame.value = Some(value)
            None => failed = true
          }
        Index(index) =>
          match path_at(frame.value, index) {
            Some(value) => frame.value = Some(value)
            None => failed = true
          }
        Wildcard | Descend =>
          match path_children(frame.value, doc) {
            Some(children) => {
              schedule(
                children,
                frame.index,
                frame.descending || token is Descend,
              )
              branched = true
            }
            None => failed = true
          }
        Slice(start, end, step) =>
          match path_sequence(frame.value) {
            Some(values) => {
              let selected = []
              let mut i = start.to_uint64()
              let end = end
                .min(values.length().reinterpret_as_uint())
                .to_uint64()
              while i < end {
                selected.push(values[i.to_int()])
                i += step.to_uint64()
              }
              schedule(selected, frame.index, frame.descending)
              branched = true
            }
            None => failed = true
          }
        Members(keys) =>
          if frame.value is (None | Some(Map(_)) | Some(Value(Object(_)))) {
            schedule(
              keys.filter_map(fn(key) { path_member(frame.value, doc, key) }),
              frame.index,
              frame.descending,
            )
            branched = true
          } else {
            failed = true
          }
        Indices(indices) =>
          match path_sequence(frame.value) {
            Some(values) => {
              schedule(
                indices.filter_map(fn(index) {
                  let index = if index < 0 {
                    values.length() + index
                  } else {
                    index
                  }
                  values.get(index)
                }),
                frame.index,
                frame.descending,
              )
              branched = true
            }
            None => failed = true
          }
      }
      if failed || branched {
        break
      }
    }
    if failed && frame.descending {
      if path_children(frame.value, doc) is Some(children) {
        schedule(children, frame.index - 1, true)
      }
    } else if !failed && !branched {
      if frame.value is Some(value) {
        result.push(value)
      }
    }
  }
  result
}

///|
pub fn Doc::json_path(self : Doc, path : JsonPath) -> Iter[Out] {
  path.evaluate(None, Some(self)).iter()
}

///|
pub fn Any::json_path(self : Any, path : JsonPath) -> Iter[Any] {
  path
  .evaluate(Some(Value(self)), None)
  .iter()
  .filter_map(fn(value) {
    match value {
      Value(value) => Some(value)
      _ => None
    }
  })
}
