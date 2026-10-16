///|
test "seeded update mutations fail safely or preserve decoded identities on reencoding" {
  let source = @yrs.Doc(client_id=7UL)
  let text = source.get_or_insert_text("text")
  text.insert(0, "Unicode 🦀 and 中文 with retained deletions")
  text.format(2, 9, [("bold", Bool(true))])
  text.remove_range(13, 3)
  let root = source.get_or_insert_map("root")
  let array = root.insert_array("items")
  array.insert_range(0, [Integer(42L), String("value"), Bool(true)])
  array.insert_text(1).insert(0, "nested")
  let seeds = [
    source.encode_state_as_update_v1(),
    source.encode_state_as_update_v2(),
  ]
  let mut random = 0x1234abcdU
  let mut accepted = 0
  let mut rejected = 0
  for version, seed in seeds {
    for iteration in 0..<3000 {
      let data = seed.iter().to_array()
      random = random * 1664525U + 1013904223U
      let pos = (random % data.length().reinterpret_as_uint()).reinterpret_as_int()
      match iteration % 4 {
        0 =>
          data[pos] = (data[pos].to_uint() ^
          (1U << (random % 8U).reinterpret_as_int())).to_byte()
        1 => data.truncate(pos)
        2 => data.push((random >> 16).to_byte())
        _ =>
          for i in pos..<data.length().min(pos + 4) {
            random = random * 1664525U + 1013904223U
            data[i] = (random >> 16).to_byte()
          }
      }
      let input = Bytes::from_array(data[:])
      let update = Some(
        if version == 0 {
          @yrs.Update::decode_v1(input)
        } else {
          @yrs.Update::decode_v2(input)
        },
      ) catch {
        _ => None
      }
      match update {
        None => rejected += 1
        Some(update) => {
          accepted += 1
          let doc = @yrs.Doc(client_id=11UL)
          doc.apply_update(update)
          let copy = @yrs.Doc(client_id=12UL)
          copy.apply_update_v1(doc.encode_state_as_update_v1())
          assert_eq(doc.state_vector(), copy.state_vector())
          assert_eq(doc.snapshot(), copy.snapshot())
          let roundtrip = @yrs.Update::decode_v1(update.encode_v1())
          assert_eq(update.state_vector(), roundtrip.state_vector())
          assert_eq(update.state_vector_lower(), roundtrip.state_vector_lower())
          assert_eq(
            update.delete_set().ranges(),
            roundtrip.delete_set().ranges(),
          )
          assert_eq(
            update.insertions(include_deleted=true).ranges(),
            roundtrip.insertions(include_deleted=true).ranges(),
          )
        }
      }
    }
  }
  assert_true(accepted > 100)
  assert_true(rejected > 1000)
}
