///|
fn shared(value : Json) -> @yrs.In {
  match value {
    Array(values) => Array(ReadOnlyArray::from_array(values.map(shared)[:]))
    Object(values) =>
      Map(
        ReadOnlyArray::from_array(
          values.to_array().map(fn(entry) { (entry.0, shared(entry.1)) })[:],
        ),
      )
    _ => Value(@yrs.Any::from_json(value))
  }
}

///|
fn run(input : String) -> String raise {
  guard @json.parse(input) is { "value": value, "paths": Array(paths), .. } else {
    abort("request")
  }
  let immutable = @yrs.Any::from_json(value)
  let doc = @yrs.Doc(client_id=1UL)
  let root = doc.get_or_insert_map("root")
  guard value is Object(fields) else { abort("root object") }
  for key, value in fields {
    root.insert_input(key, shared(value)) |> ignore
  }
  let results = []
  for path in paths {
    guard path is String(path) else { abort("path") }
    try @yrs.JsonPath::parse(path) catch {
      @yrs.JsonPathError::InvalidJsonPath(_) =>
        results.push({ "error": Json(true) })
    } noraise {
      parsed => {
        let suffix = if path.has_prefix("$") {
          path[1:].to_owned()
        } else {
          path
        }
        let document_path = @yrs.JsonPath::parse(
          if path == "" {
            ""
          } else {
            "$.root" + suffix
          },
        )
        results.push({
          "any": Json(
            immutable.json_path(parsed).map(@yrs.Any::to_json).to_array(),
          ),
          "doc": Json(
            doc.json_path(document_path).map(@yrs.Out::to_json).to_array(),
          ),
        })
      }
    }
  }
  Json(results).stringify()
}

///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  try! run(input)
}
