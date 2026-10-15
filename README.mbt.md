# Yrs for MoonBit

A MoonBit port of Yrs, the Rust implementation of the Yjs CRDT. Work in progress; full upstream compatibility is the target, not a current claim.

The reference is Yrs 0.28.0 at `ac339600c712642e556895426113c3f9c117de39`, checked out in `.repos/y-crdt`. The implementation preserves Yjs item identities, conflict ordering, deletion semantics and binary updates. Public APIs use MoonBit constructors.

Implementation sequence:

1. Collaborative text and binary v1 update exchange against Rust, including concurrent and out-of-order edits.
2. Arrays, maps, nested types, rich text and XML on the same item store.
3. Binary v2, update utilities, sync and awareness protocols.
4. Transactions, observers, undo, snapshots, relative positions, subdocuments and the remaining pinned upstream surface.

Every milestone needs real Rust interoperability tests, rather than only MoonBit-to-MoonBit convergence tests. Validation evidence and remaining limitations will be recorded as each milestone lands.

## Implemented and checked

Collaborative plain text uses the upstream YATA conflict-ordering algorithm, UTF-16 clocks, state vectors, binary v1 updates, deletion ranges, duplicate suppression and pending dependency integration. Deleted content is retained. Shared arrays and maps use the same store, with immutable lib0 values (including binary, signed 64-bit integers, floating point, arrays and objects). The Rust oracle covers 385 scenarios, 68,358 operation snapshots and 2,310 bidirectional document transfers, including nested maps/arrays/text, parent replacement and concurrent child edits.

```mbt check
///|
test "two replicas exchange concurrent edits" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let left = a.get_or_insert_text("note")
  let right = b.get_or_insert_text("note")
  left.insert(0, "Hello")
  b.apply_update_v1(a.encode_state_as_update_v1())
  left.insert(5, " Moon")
  right.insert(5, " Rust")
  a.apply_update_v1(b.encode_state_as_update_v1(remote=a.state_vector()))
  b.apply_update_v1(a.encode_state_as_update_v1(remote=b.state_vector()))
  assert_eq(left.get_string(), "Hello Moon Rust")
  assert_eq(left.get_string(), right.get_string())
}
```

Current limitations: rich text and XML are not yet implemented; unsupported content is rejected before applying an update. Binary v2, the remaining shared types and transaction/event APIs are still outstanding. The store currently favors straightforward correctness over upstream's block compaction and indexing optimizations. This is not a production release or a completed port.

Run `moon test --target all` and `python3 validation/compare.py`. The oracle uses the installed Rust 1.97.1 toolchain and the exact reference checkout under `.repos/y-crdt`; its Cargo dependencies are locked. Clone `https://github.com/y-crdt/y-crdt.git` there and check out `ac339600c712642e556895426113c3f9c117de39` before running it.
