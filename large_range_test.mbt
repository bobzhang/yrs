///|
fn large_run(kind : Int32, start : UInt32, length : UInt32) -> Bytes raise {
  let w = @yrs.EncoderV1()
  w.write_var_uint(1UL)
  w.write_var_uint(1UL)
  w.write_var_uint(7UL)
  w.write_var_uint(start.to_uint64())
  w.write_u8(kind.to_byte())
  if kind == 1 {
    w.write_var_uint(1UL)
    w.write_string("note")
  }
  w.write_var_uint(length.to_uint64())
  w.write_var_uint(0UL)
  w.to_bytes()
}

///|
test "compressed deleted runs span unsigned clocks without signed overflow" {
  for kind in [0, 1] {
    for length in [0x7fff_ffffU, 0x8000_0000U, 0xffff_fffeU, 0xffff_ffffU] {
      let packet = large_run(kind, 0U, length)
      for v2 in [false, true] {
        for gc in [false, true] {
          let doc = @yrs.Doc(client_id=9UL, skip_gc=!gc)
          let update = @yrs.Update::decode_v1(packet)
          if v2 {
            doc.apply_update_v2(update.encode_v2())
          } else {
            doc.apply_update(update)
          }
          assert_eq(doc.state_vector().get(7UL), length)
          assert_eq(doc.get_or_insert_text("note").get_string(), "")
          // Re-importing a differently segmented representation must be idempotent.
          doc.apply_update_v1(packet)
          let saved = doc.encode_state_as_update_v1()
          assert_true(saved.length() < 100)
          for cut in [1U, 0x7fff_fffeU, 0x7fff_ffffU, length - 1U, length] {
            if cut > length {
              continue
            }
            let peer = @yrs.Doc(client_id=10UL, skip_gc=!gc)
            peer.apply_update_v1(large_run(kind, 0U, cut))
            let remote = peer.state_vector()
            if v2 {
              peer.apply_update_v2(
                @yrs.diff_updates_v2(
                  @yrs.convert_update_v1_to_v2(saved),
                  remote.encode_v1(),
                ),
              )
            } else {
              peer.apply_update_v1(
                @yrs.diff_updates_v1(saved, remote.encode_v1()),
              )
            }
            assert_eq(
              peer.state_vector(),
              doc.state_vector(),
              msg="kind=\{kind} length=\{length} cut=\{cut} v2=\{v2} gc=\{gc}",
            )
            assert_eq(peer.snapshot(), doc.snapshot())
          }
        }
      }
    }
  }
}

///|
test "compressed range overflow is rejected before document mutation" {
  for kind in [0, 1] {
    let doc = @yrs.Doc(client_id=9UL)
    try doc.apply_update_v1(large_run(kind, 1U, 0xffff_ffffU)) catch {
      @yrs.InvalidData(message) => assert_eq(message, "clock overflow")
      _ => fail("unexpected error")
    } noraise {
      _ => fail("accepted overflowing clocks")
    }
    assert_true(doc.state_vector().is_empty())
  }
}

///|
test "v2 clock columns preserve full unsigned jumps and repeated negative deltas" {
  let clocks : Array[UInt32] = [
    0U, 0x3fff_ffffU, 0x4000_0000U, 0x7fff_ffffU, 0x8000_0000U, 0xffff_ffffU, 0U,
    0xffff_ffffU, 0xffff_fffeU, 0xffff_fffdU, 0x8000_0000U, 0U, 0U, 0U,
  ]
  let encoder = @yrs.EncoderV2()
  for clock in clocks {
    encoder.write_left_id({ client: 7UL, clock, })
    encoder.write_right_id({ client: 9UL, clock: 0xffff_ffffU - clock, })
  }
  let decoder = @yrs.DecoderV2(encoder.to_bytes())
  for clock in clocks {
    assert_eq(decoder.read_left_id(), { client: 7UL, clock, })
    assert_eq(decoder.read_right_id(), {
      client: 9UL,
      clock: 0xffff_ffffU - clock,
    })
  }
}
