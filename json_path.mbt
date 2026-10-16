///|
pub suberror JsonPathError {
  InvalidJsonPath(String)
} derive(Debug)

///|
pub extend JsonPathError with Debug::{to_repr}

///|
priv enum PathToken {
  Root
  Current
  Member(String)
  Index(Int32)
  Wildcard
  Descend
  Slice(UInt32, UInt32, UInt32)
  Members(Array[String])
  Indices(Array[Int32])
}

///|
/// The JSONPath subset supported by Yrs: members, indices, wildcards, recursive
/// descent, slices and unions. Predicate expressions are not supported.
pub struct JsonPath {
  priv tokens : Array[PathToken]
}

///|
fn path_in_ranges(c : Char, ranges : ReadOnlyArray[(Int32, Int32)]) -> Bool {
  let value = c.to_int()
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (start, end) = ranges[mid]
    if value < start {
      hi = mid
    } else if value >= end {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
fn path_alpha(c : Char) -> Bool {
  path_in_ranges(c, path_alphabetic_ranges)
}

///|
fn path_alnum(c : Char) -> Bool {
  path_alpha(c) || path_in_ranges(c, path_numeric_ranges)
}

///|
fn path_string(chars : Array[Char], start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  for i in start..<end {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn path_number(s : String) -> Int64? {
  let chars = s.iter().to_array()
  if chars.is_empty() {
    return None
  }
  let negative = chars[0] == '-'
  let start = if negative || chars[0] == '+' { 1 } else { 0 }
  if start == chars.length() {
    return None
  }
  let mut number = 0L
  for i in start..<chars.length() {
    let c = chars[i]
    if !c.is_ascii_digit() {
      return None
    }
    number = number * 10L + (c.to_int() - 48).to_int64()
    if number > 0xffff_ffffL {
      return None
    }
  }
  Some(if negative { -number } else { number })
}

///|
fn path_index(s : String) -> Int32? {
  match path_number(s) {
    Some(n) if n >= -2147483648L && n <= 2147483647L => Some(n.to_int())
    _ => None
  }
}

///|
fn path_unsigned(s : String, fallback : UInt32) -> UInt32 {
  match path_number(s) {
    Some(n) if n >= 0L => n.reinterpret_as_uint64().to_uint()
    _ => fallback
  }
}

///|
fn path_bracket(s : String) -> PathToken raise JsonPathError {
  if s == "*" {
    return Wildcard
  }
  if path_index(s) is Some(index) {
    return Index(index)
  }
  if s.has_prefix("?") {
    raise InvalidJsonPath("JSONPath predicates are not supported")
  }
  if s.contains(":") {
    let parts = s.split(":").map(fn(p) { p.to_owned() }).to_array()
    let start = path_unsigned(parts[0], 0U)
    let end = path_unsigned(parts.get(1).unwrap_or(""), 0xffff_ffffU)
    let step = path_unsigned(parts.get(2).unwrap_or(""), 1U)
    guard step > 0U else {
      raise InvalidJsonPath("slice step must be positive")
    }
    return Slice(start, end, step)
  }
  if s.contains(",") {
    let parts = s.split(",").map(fn(p) { p.trim().to_owned() }).to_array()
    if parts[0].has_prefix("'") && parts[0].has_suffix("'") {
      let members = []
      for part in parts {
        guard part.length() >= 2 && part.has_prefix("'") && part.has_suffix("'") else {
          raise InvalidJsonPath("unpaired member quote")
        }
        members.push(part[1:part.length() - 1].to_owned())
      }
      return Members(members)
    }
    let indices = []
    for part in parts {
      guard path_index(part) is Some(index) else {
        raise InvalidJsonPath("invalid index union")
      }
      indices.push(index)
    }
    return Indices(indices)
  }
  if s.length() >= 2 && s.has_prefix("'") && s.has_suffix("'") {
    return Member(s[1:s.length() - 1].to_owned())
  }
  raise InvalidJsonPath("unsupported bracket expression")
}

///|
pub fn JsonPath::parse(path : String) -> JsonPath raise JsonPathError {
  let chars = path.iter().to_array()
  let tokens : Array[PathToken] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    match c {
      '$' => tokens.push(Root)
      '@' => tokens.push(Current)
      '*' => tokens.push(Wildcard)
      '.' => {
        guard i < chars.length() else {
          raise InvalidJsonPath("path cannot end with '.'")
        }
        if chars[i] == '.' {
          tokens.push(Descend)
          i += 1
        } else if chars[i] == '*' {
          tokens.push(Wildcard)
          i += 1
        } else if path_alpha(chars[i]) {
          let start = i
          while i < chars.length() && (path_alnum(chars[i]) || chars[i] == '_') {
            i += 1
          }
          tokens.push(Member(path_string(chars, start, i)))
        } else {
          raise InvalidJsonPath("invalid member name")
        }
      }
      '[' => {
        let start = i
        let mut quoted = false
        let mut nesting = 1
        while i < chars.length() {
          let c = chars[i]
          if c == '[' {
            nesting += 1
          }
          if c == ']' {
            nesting -= 1
            if nesting == 0 && !quoted {
              break
            }
          }
          if c == '\'' {
            quoted = !quoted
          }
          i += 1
        }
        guard i < chars.length() && !quoted else {
          raise InvalidJsonPath("unclosed bracket expression")
        }
        tokens.push(path_bracket(path_string(chars, start, i)))
        i += 1
      }
      _ =>
        if path_alpha(c) {
          let start = i - 1
          while i < chars.length() && (path_alnum(chars[i]) || chars[i] == '_') {
            i += 1
          }
          tokens.push(Member(path_string(chars, start, i)))
        } else {
          raise InvalidJsonPath("invalid path character")
        }
    }
  }
  { tokens, }
}
