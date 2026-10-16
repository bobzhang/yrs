///|
test "restored remote awareness is added and emits a change after removal" {
  let awareness : @yrs.Awareness = @yrs.Awareness(@yrs.Doc(client_id=9UL), clock=fn() {
    100UL
  })
  let changes : Array[@yrs.AwarenessSummary] = []
  let updates : Array[@yrs.AwarenessSummary] = []
  awareness.on_change("test", fn(_, event, _) { changes.push(event) })
  awareness.on_update("test", fn(_, event, _) { updates.push(event) })
  fn apply(clock : UInt32, json : String) -> @yrs.AwarenessSummary? {
    awareness.apply_update(
      @yrs.AwarenessUpdate(entries=[(1UL, { clock, json, })]),
    )
  }
  apply(1U, "{}") |> ignore
  apply(2U, "null") |> ignore
  changes.clear()
  updates.clear()
  let restored = apply(3U, "{}").unwrap()
  assert_eq(restored.added, ReadOnlyArray::from_array([1UL]))
  assert_eq(restored.updated.length(), 0)
  assert_eq(changes, [restored])
  assert_eq(updates, [restored])
  // Duplicates stay silent, and a same-value heartbeat is only an update.
  assert_eq(apply(3U, "{}"), None)
  apply(4U, "{}") |> ignore
  assert_eq(changes.length(), 1)
  assert_eq(updates.length(), 2)
  assert_eq(updates[1].updated, ReadOnlyArray::from_array([1UL]))
}
