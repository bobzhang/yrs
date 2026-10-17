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
priv enum TextStorage {
  Flat(String)
  Buffered(ContentBuffer[UInt16])
}

///|
priv struct TextContent {
  storage : TextStorage
  utf8_length : Int32
  mut rendered : String?
}

///|
fn TextContent::TextContent(text : String) -> TextContent {
  let mut bytes = 0
  for c in text {
    bytes += utf8_width(c)
  }
  { storage: Flat(text), utf8_length: bytes, rendered: None, }
}

///|
fn TextContent::length(self : TextContent) -> Int32 {
  match self.storage {
    Flat(text) => text.length()
    Buffered(units) => units.count
  }
}

///|
fn TextContent::iter(self : TextContent) -> Iter[Char] {
  let units = match self.storage {
    Flat(text) => return text.iter()
    Buffered(units) => units
  }
  let mut index = 0
  Iter::new(fn() {
    guard index < units.count else { return None }
    let first = units[index].to_int()
    index += 1
    if first >= 0xd800 && first <= 0xdbff && index < units.count {
      let second = units[index].to_int()
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
  if self.storage is Flat(text) {
    return text
  }
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
  guard 0 <= start && start <= end && end <= self.length() else {
    abort("text slice out of bounds")
  }
  if start == 0 && end == self.length() {
    return self
  }
  if start == end {
    return TextContent("")
  }
  match self.storage {
    Flat(text) => {
      // Checked string views require scalar boundaries. Replace only orphaned
      // edge units, then copy the selected interior without scanning the prefix.
      let low = text[start] >= 0xdc00 && text[start] <= 0xdfff
      let high = text[end - 1] >= 0xd800 && text[end - 1] <= 0xdbff
      if !low && !high {
        return TextContent(text[start:end].to_owned())
      }
      let from = start + (if low { 1 } else { 0 })
      let to = end - (if high { 1 } else { 0 })
      let builder = StringBuilder()
      if low {
        builder.write_char('\ufffd')
      }
      builder.write_stringview(text[from:to])
      if high {
        builder.write_char('\ufffd')
      }
      TextContent(builder.to_string())
    }
    Buffered(source) => {
      let units = source.slice(start, end)
      // Non-full slices own their arrays. Cut surrogates stay replaced even
      // when the two slices are joined again.
      if units[0] >= 0xdc00 && units[0] <= 0xdfff {
        units.data[0] = 0xfffd
      }
      let last = units.count - 1
      if units[last] >= 0xd800 && units[last] <= 0xdbff {
        units.data[last] = 0xfffd
      }
      let result = { storage: Buffered(units), utf8_length: 0, rendered: None, }
      let mut bytes = 0
      for c in result {
        bytes += utf8_width(c)
      }
      { ..result, utf8_length: bytes, }
    }
  }
}

///|
// Most inserted strings are small and never need their own append allocation.
// Copy their units directly into the destination rather than allocating a
// temporary ContentBuffer for every incoming/local character.
fn ContentBuffer::joined_string(
  self : ContentBuffer[UInt16],
  text : String,
) -> ContentBuffer[UInt16] {
  let reused = self.count == self.data.length() && !self.frozen.val
  let data = if reused { self.data } else { self.data[:self.count].to_owned() }
  for i in 0..<text.length() {
    data.push(text[i])
  }
  {
    data,
    count: self.count + text.length(),
    frozen: if reused {
      self.frozen
    } else {
      Ref(false)
    },
  }
}

///|
fn TextContent::joined(self : TextContent, other : TextContent) -> TextContent {
  let units = match self.storage {
    Flat(text) => ContentBuffer(text.code_units())
    Buffered(units) => units
  }
  let units = match other.storage {
    Flat(text) => units.joined_string(text)
    Buffered(other) => units.joined(other)
  }
  {
    storage: Buffered(units),
    utf8_length: self.utf8_length + other.utf8_length,
    rendered: None,
  }
}

///|
fn Content::freeze_storage(self : Content) -> Unit {
  match self {
    Characters({ storage: Buffered(units), .. }) => units.frozen.val = true
    Values(values) | LegacyJson(values) => values.frozen.val = true
    _ => ()
  }
}
