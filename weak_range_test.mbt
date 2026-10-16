///|
test "fresh weak ranges select current visible positions after deletion and formatting" {
  for skip_gc in [false, true] {
    for formatted in [false, true] {
      let doc = @yrs.Doc(client_id=1UL, skip_gc~)
      let text = doc.get_or_insert_text("text")
      text.insert(0, "XabcdYefgh")
      text.remove_range(0, 1)
      text.remove_range(4, 1)
      if formatted {
        text.format(0, 2, [("bold", Bool(true))])
        text.format(4, 2, [("italic", Bool(true))])
      }
      assert_eq(text.get_string(), "abcdefgh")
      let links = doc.get_or_insert_map("links")
      for start in 0..<8 {
        for end in start..<8 {
          for exclude_start in [false, true] {
            for include_end in [false, true] {
              let lo = start + (if exclude_start { 1 } else { 0 })
              let hi = end + (if include_end { 1 } else { 0 })
              let expected = if lo < hi {
                "abcdefgh"[lo:hi].to_owned()
              } else {
                ""
              }
              let quote = text.quote(
                if exclude_start {
                  Excluded(start)
                } else {
                  Included(start)
                },
                if include_end {
                  Included(end)
                } else {
                  Excluded(end)
                },
              )
              let link = weak(links.insert_input("q", WeakLink(quote)))
              assert_eq(link.get_string(), expected)
              let plain = StringBuilder()
              for chunk in link.to_delta() {
                if chunk.insert is Value(String(value)) {
                  plain.write_string(value)
                }
              }
              assert_eq(plain.to_string(), expected)
            }
          }
        }
      }
    }
  }
}
