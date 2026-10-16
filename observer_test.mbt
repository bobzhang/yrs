///|
test "unsubscribing another callback during dispatch cancels it immediately" {
  let doc = @yrs.Doc(client_id=1UL)
  let text = doc.get_or_insert_text("note")
  let calls = Ref(0)
  text.observe("a", fn(_, _) {
    calls.val += 1
    text.unobserve("b") |> ignore
  })
  text.observe("b", fn(_, _) {
    calls.val += 1
    text.unobserve("a") |> ignore
  })
  text.insert(0, "one")
  assert_eq(calls.val, 1)
  text.insert(0, "two")
  assert_eq(calls.val, 2)
}

///|
test "generic observer replaces subscriptions and drains cancelled keys" {
  let observers : @yrs.Observer[Bytes, (Int32) -> Unit] = Observer()
  let values = []
  assert_false(observers.has_subscribers())
  observers.subscribe(b"key", fn(n) { values.push(n) })
  observers.subscribe(b"key", fn(n) { values.push(n * 10) })
  observers.trigger(fn(f) { f(3) })
  assert_eq(values, [30])
  assert_true(observers.unsubscribe(b"key"))
  assert_true(observers.unsubscribe(b"key"))
  assert_true(observers.has_subscribers())
  observers.trigger(fn(f) { f(4) })
  assert_false(observers.has_subscribers())
  assert_false(observers.unsubscribe(b"key"))
  assert_eq(values, [30])
  observers.subscribe(b"key", fn(n) {
    values.push(n)
    observers.subscribe(b"key", fn(n) { values.push(n * 100) })
  })
  observers.trigger(fn(f) { f(5) })
  assert_eq(values, [30, 5])
  observers.trigger(fn(f) { f(6) })
  assert_eq(values, [30, 5, 600])
  observers.unsubscribe(b"key") |> ignore
  observers.subscribe(b"other", fn(_) { () })
  assert_false(observers.unsubscribe(b"key"))
}

///|
fn check_cancellation(
  register : (String, () -> Unit) -> Unit,
  cancel : (String) -> Bool,
  fire : () -> Unit,
  repeat~ : Bool = true,
) -> Unit raise {
  let calls = Ref(0)
  register("a", fn() {
    calls.val += 1
    cancel("b") |> ignore
  })
  register("b", fn() {
    calls.val += 1
    cancel("a") |> ignore
  })
  fire()
  assert_eq(calls.val, 1)
  if repeat {
    fire()
    assert_eq(calls.val, 2)
  }
}

///|
test "document phases cancel callbacks during dispatch" {
  for phase in 0..<5 {
    let doc = @yrs.Doc(client_id=1UL)
    let text = doc.get_or_insert_text("text")
    check_cancellation(
      fn(key, f) {
        match phase {
          0 => doc.observe_before_observer_calls(key, fn(_) { f() })
          1 => doc.observe_after_transaction(key, fn(_) { f() })
          2 => doc.observe_transaction_cleanup(key, fn(_) { f() })
          3 => doc.observe_update_v1(key, fn(_, _) { f() })
          _ => doc.observe_update_v2(key, fn(_, _) { f() })
        }
      },
      fn(key) {
        match phase {
          0 => doc.unobserve_before_observer_calls(key)
          1 => doc.unobserve_after_transaction(key)
          2 => doc.unobserve_transaction_cleanup(key)
          3 => doc.unobserve_update_v1(key)
          _ => doc.unobserve_update_v2(key)
        }
      },
      fn() { text.insert(0, "x") },
    )
  }
  let doc = @yrs.Doc(client_id=1UL)
  check_cancellation(
    fn(key, f) { doc.observe_destroy(key, fn(_) { f() }) },
    fn(key) { doc.unobserve_destroy(key) },
    fn() { doc.destroy() },
    repeat=false,
  )
  let doc = @yrs.Doc(client_id=1UL)
  let array = doc.get_or_insert_array("subdocs")
  check_cancellation(
    fn(key, f) { doc.observe_subdocs(key, fn(_, _) { f() }) },
    fn(key) { doc.unobserve_subdocs(key) },
    fn() { array.insert_doc(0, Doc(client_id=2UL, guid="child")) |> ignore },
  )
}

///|
test "typed and deep observers cancel callbacks during dispatch" {
  for deep in [false, true] {
    let doc = @yrs.Doc(client_id=1UL)
    let text = doc.get_or_insert_text("text")
    let array = doc.get_or_insert_array("array")
    let map = doc.get_or_insert_map("map")
    let xml = doc.get_or_insert_xml_fragment("xml")
    let element = xml.insert_element(0, "p")
    let xml_text = xml.insert_text(1)
    let links = doc.get_or_insert_map("links")
    text.insert(0, "anchor")
    let link = weak(
      links.insert_input("quote", WeakLink(text.quote(Unbounded, Unbounded))),
    )
    for kind in 0..<7 {
      check_cancellation(
        fn(key, f) {
          if deep {
            let cb = fn(_, _) { f() }
            match kind {
              0 => text.observe_deep(key, cb)
              1 => array.observe_deep(key, cb)
              2 => map.observe_deep(key, cb)
              3 => xml.observe_deep(key, cb)
              4 => element.observe_deep(key, cb)
              5 => xml_text.observe_deep(key, cb)
              _ => link.observe_deep(key, cb)
            }
          } else {
            match kind {
              0 => text.observe(key, fn(_, _) { f() })
              1 => array.observe(key, fn(_, _) { f() })
              2 => map.observe(key, fn(_, _) { f() })
              3 => xml.observe(key, fn(_, _) { f() })
              4 => element.observe(key, fn(_, _) { f() })
              5 => xml_text.observe(key, fn(_, _) { f() })
              _ => link.observe(key, fn(_, _) { f() })
            }
          }
        },
        fn(key) {
          if deep {
            match kind {
              0 => text.unobserve_deep(key)
              1 => array.unobserve_deep(key)
              2 => map.unobserve_deep(key)
              3 => xml.unobserve_deep(key)
              4 => element.unobserve_deep(key)
              5 => xml_text.unobserve_deep(key)
              _ => link.unobserve_deep(key)
            }
          } else {
            match kind {
              0 => text.unobserve(key)
              1 => array.unobserve(key)
              2 => map.unobserve(key)
              3 => xml.unobserve(key)
              4 => element.unobserve(key)
              5 => xml_text.unobserve(key)
              _ => link.unobserve(key)
            }
          }
        },
        fn() {
          match kind {
            0 | 6 => text.insert(0, "x")
            1 => array.insert_range(0, [Integer(1L)])
            2 =>
              map.insert("x", Integer(doc.state_vector().get(1UL).to_int64()))
            3 => xml.insert_element(0, "i") |> ignore
            4 => element.as_fragment().insert_text(0) |> ignore
            5 => xml_text.as_text().insert(0, "x")
            _ => abort("kind")
          }
        },
      )
    }
  }
}

///|
test "awareness and undo observers cancel callbacks during dispatch" {
  for update in [false, true] {
    let awareness : @yrs.Awareness = Awareness(Doc(client_id=1UL), clock=fn() {
      0UL
    })
    let count = Ref(0)
    check_cancellation(
      fn(key, f) {
        if update {
          awareness.on_update(key, fn(_, _, _) { f() })
        } else {
          awareness.on_change(key, fn(_, _, _) { f() })
        }
      },
      fn(key) {
        if update {
          awareness.unobserve_update(key)
        } else {
          awareness.unobserve_change(key)
        }
      },
      fn() {
        count.val += 1
        awareness.set_local_state(Json(count.val))
      },
    )
  }
  for kind in 0..<4 {
    let doc = @yrs.Doc(client_id=1UL)
    let text = doc.get_or_insert_text("text")
    let undo : @yrs.UndoManager[Unit] = UndoManager(clock=fn() { 100UL })
    undo.expand_scope(Text(text))
    text.insert(0, "seed")
    check_cancellation(
      fn(key, f) {
        match kind {
          0 => undo.observe_item_added(key, fn(_, _) { f() })
          1 => undo.observe_item_updated(key, fn(_, _) { f() })
          2 => undo.observe_item_popped(key, fn(_, _) { f() })
          _ => undo.observe_stack_cleared(key, fn(_, _) { f() })
        }
      },
      fn(key) {
        match kind {
          0 => undo.unobserve_item_added(key)
          1 => undo.unobserve_item_updated(key)
          2 => undo.unobserve_item_popped(key)
          _ => undo.unobserve_stack_cleared(key)
        }
      },
      fn() {
        match kind {
          0 => {
            undo.reset()
            text.insert(0, "x")
          }
          1 => text.insert(0, "x")
          2 => {
            undo.reset()
            text.insert(0, "x")
            undo.undo() |> ignore
          }
          _ => {
            text.insert(0, "x")
            undo.clear_all()
          }
        }
      },
    )
  }
}
