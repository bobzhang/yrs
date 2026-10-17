///|
// A bounded immutable view over append-only storage. Appending at the physical
// end cannot change any existing view. Branching from an older view copies its
// prefix once, just as copy-on-write storage does. Never expose the backing
// array or mutate elements: decoded updates and retained transactions share it.
priv struct ContentBuffer[T] {
  data : Array[T]
  frozen : Ref[Bool]
  count : Int32
}

///|
fn[T] ContentBuffer::ContentBuffer(values : ArrayView[T]) -> ContentBuffer[T] {
  { data: values.to_owned(), count: values.length(), frozen: Ref(false), }
}

///|
fn[T] ContentBuffer::length(self : ContentBuffer[T]) -> Int32 {
  self.count
}

///|
#alias("_[_]")
fn[T] ContentBuffer::get(self : ContentBuffer[T], index : Int32) -> T {
  guard index >= 0 && index < self.count else {
    abort("content index out of bounds")
  }
  self.data[index]
}

///|
fn[T] ContentBuffer::iter(self : ContentBuffer[T]) -> Iter[T] {
  self.data[:self.count].iter()
}

///|
fn[T] ContentBuffer::slice(
  self : ContentBuffer[T],
  start : Int32,
  end : Int32,
) -> ContentBuffer[T] {
  guard 0 <= start && start <= end && end <= self.count else {
    abort("content slice out of bounds")
  }
  if start == 0 && end == self.count {
    self
  } else {
    // Do not let a tiny surviving slice pin an arbitrarily large deleted block.
    ContentBuffer(self.data[start:end])
  }
}

///|
fn[T] ContentBuffer::joined(
  self : ContentBuffer[T],
  other : ContentBuffer[T],
) -> ContentBuffer[T] {
  let reused = self.count == self.data.length() && !self.frozen.val
  let data = if reused { self.data } else { self.data[:self.count].to_owned() }
  // The count is captured before appending, including when storage aliases.
  for i in 0..<other.count {
    data.push(other.data[i])
  }
  {
    data,
    count: self.count + other.count,
    frozen: if reused {
      self.frozen
    } else {
      Ref(false)
    },
  }
}

///|
priv struct TextContent {
  units : ContentBuffer[UInt16]
  utf8_length : Int32
  mut rendered : String?
}

///|
fn TextContent::TextContent(text : String) -> TextContent {
  let mut bytes = 0
  for c in text {
    bytes += utf8_width(c)
  }
  {
    units: ContentBuffer(text.code_units()),
    utf8_length: bytes,
    rendered: Some(text),
  }
}

///|
fn TextContent::length(self : TextContent) -> Int32 {
  self.units.length()
}

///|
fn TextContent::iter(self : TextContent) -> Iter[Char] {
  let mut index = 0
  Iter::new(fn() {
    guard index < self.length() else { return None }
    let first = self.units[index].to_int()
    index += 1
    if first >= 0xd800 && first <= 0xdbff && index < self.length() {
      let second = self.units[index].to_int()
      if second >= 0xdc00 && second <= 0xdfff {
        index += 1
        return Some(
          (0x10000 + ((first - 0xd800) << 10) + second - 0xdc00).unsafe_to_char(),
        )
      }
    }
    Some(first.unsafe_to_char())
  })
}

///|
fn TextContent::text(self : TextContent) -> String {
  if self.rendered is Some(text) {
    return text
  }
  let text = String::from_iter(self.iter())
  self.rendered = Some(text)
  text
}

///|
fn TextContent::slice(
  self : TextContent,
  start : Int32,
  end : Int32,
) -> TextContent {
  if start == 0 && end == self.length() {
    return self
  }
  let units = self.units.slice(start, end)
  if units.count > 0 {
    // A cut surrogate becomes U+FFFD permanently, even if the halves are
    // subsequently joined again. These are fresh slice-owned arrays.
    if units[0] >= 0xdc00 && units[0] <= 0xdfff {
      units.data[0] = 0xfffd
    }
    let last = units.count - 1
    if units[last] >= 0xd800 && units[last] <= 0xdbff {
      units.data[last] = 0xfffd
    }
  }
  let result = { units, utf8_length: 0, rendered: None, }
  let mut bytes = 0
  for c in result {
    bytes += utf8_width(c)
  }
  { ..result, utf8_length: bytes, }
}

///|
fn TextContent::joined(self : TextContent, other : TextContent) -> TextContent {
  {
    units: self.units.joined(other.units),
    utf8_length: self.utf8_length + other.utf8_length,
    rendered: None,
  }
}

///|
fn Content::freeze_storage(self : Content) -> Unit {
  match self {
    Characters(text) => text.units.frozen.val = true
    Values(values) | LegacyJson(values) => values.frozen.val = true
    _ => ()
  }
}
