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

Collaborative plain text uses the upstream YATA conflict-ordering algorithm, UTF-16 clocks, state vectors, binary v1 and v2 updates, deletion ranges, duplicate suppression and pending dependency integration. Deleted content is retained. Shared arrays and maps use the same store, with immutable lib0 values (including binary, signed 64-bit integers, floating point, arrays and objects). The Rust oracle covers 513 scenarios in four wire-version/GC configurations: 273,432 independent operation comparisons, 546,816 binary replay snapshots, 109,400 local rich-text operations from identical starting states and 12,312 bidirectional document transfers. These include nested maps/arrays/text, parent replacement, concurrent child edits and rich text.

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

Rich text supports attributed insertion, formatting, JSON embeds and formatted deltas. A further 128 randomized histories exercise overlapping formatting, delayed/duplicate delivery and local edits from identical serialized states. The oracle replays identical binary histories in both implementations because upstream Rust attribute-map iteration makes independently generated rich-text histories nondeterministic. Adjacent string delta chunks with equal attributes are compared as one chunk; values, attributes, embeds and imported state vectors remain checked.

Current limitations: XML is not yet implemented; unsupported content is rejected before applying an update. The remaining shared types and transaction/event APIs are still outstanding. The store currently favors straightforward correctness over upstream's block compaction and indexing optimizations. This is not a production release or a completed port.

Run `moon test --target all` and `python3 validation/compare.py`. The oracle uses the installed Rust 1.97.1 toolchain and the exact reference checkout under `.repos/y-crdt`; its Cargo dependencies are locked. Clone `https://github.com/y-crdt/y-crdt.git` there and check out `ac339600c712642e556895426113c3f9c117de39` before running it.

Binary v2 currently uses a checked conversion layer around the common v1 integration path. It implements unsigned, difference and byte RLE columns, UTF-16 string lengths, key dictionaries and delta delete sets. This favors one integration implementation over minimum intermediate allocation. `convert_update_v2_to_v1` defaults to a configurable 1,000,000-item expansion budget; lib0 nesting is bounded at 256.

Sparse updates can integrate beyond missing clock ranges when their dependencies are available. State vectors report only contiguous prefixes; `has_missing_updates()` reports holes, pending dependencies and early deletions. Full-state encoding forwards pending blocks. Stateless `merge_updates_v1/v2`, `diff_updates_v1/v2` and `encode_state_vector_from_update_v1/v2` preserve item identities and gaps without integrating a document.

`python3 validation/updates.py` checks partial-history relays and stateless utilities against Rust: 4,416 independent snapshots, 36,432 identical-wire replay snapshots and 352 merge/diff cases passed. The pinned reference has GC and sparse-v2 defects; explicit failures and reproduction instructions are recorded in [validation/REFERENCE_LIMITATIONS.md](validation/REFERENCE_LIMITATIONS.md) and [validation/update-results.json](validation/update-results.json). These results do not establish compatibility for reference cases that crash or emit overflowing clocks.
