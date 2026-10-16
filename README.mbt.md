# Yrs for MoonBit

Collaborative text, rich text, arrays, maps and XML in MoonBit, ported from
[Yrs](https://github.com/y-crdt/y-crdt). Implements the public CRDT capabilities
of Yrs 0.28.0, including its weak-reference extension, with Yjs v1/v2 wire formats.
The release target is **complete CRDT compatibility with documented adaptations**;
Rust ownership/locking APIs and reproduced upstream bugs are not compatibility
requirements. The implementation audit and all 13 release suites pass.

## Installation

```sh
moon add bobzhang/yrs@0.1.1
```

[GitHub](https://github.com/bobzhang/yrs) · [Mooncakes](https://mooncakes.io/docs/bobzhang/yrs)

## Replicate concurrent edits

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

## Supported capabilities

- Nested shared arrays, maps, text, rich-text formatting/embeds, XML fragments,
  elements, attributes and XML text; detached copies and replayable deltas.
- State vectors, v1/v2 updates, merge/diff/conversion, out-of-order and duplicate
  delivery, pending-data inspection/pruning, deletion sets and garbage collection.
- Transactions with origins, shallow/deep observers and incremental update packets.
- Undo/redo with capture policies, origins, metadata and restorable stacks;
  snapshots, historical rich-text diffs, attribution and relative cursor positions.
- Weak references and quoted ranges, typed root/nested handles, JSONPath queries,
  subdocument lifecycle, awareness and extensible sync/authentication protocols.
- Open serialization, preliminary-value and binary-codec traits for applications.

All CRDT code runs on JavaScript, native, Wasm and Wasm GC. Host applications
provide transport, scheduling, time and identity generation.

## Resolve a shared handle on another replica

```mbt check
///|
test "resolve a typed collection on another replica" {
  let source = @yrs.Doc(client_id=1UL)
  let root : @yrs.Root[@yrs.MapRef] = Root("workspace")
  let map = root.get_or_create(source)
  let text = map.insert_text("title")
  text.insert(0, "Hello")
  let handle = text.hook()
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(source.encode_state_as_update_v2())
  assert_eq(handle.get(peer).unwrap().get_string(), "Hello")
  map.remove("title")
  peer.apply_update_v1(source.encode_state_as_update_v1())
  assert_true(handle.get(peer) is None)
}
```

## Integration contract

Use a unique `Doc(client_id=...)` for each active writer. For Rust/Yjs peers,
keep client IDs in the 53-bit range (`0` through `2^53 - 1`). Transactions run within
`doc.transact(fn(tx) { ... })`; direct collection methods also create transactions.
Callbacks commit their edits even if the body raises: transactions do not roll back.
Serialize access to a document in its host execution context.

Observe `Doc.observe_update_v1` or `observe_update_v2` to send incremental packets.
Forward updates generated during remote imports too: formatting cleanup and other
causal changes can generate new operations. Duplicate delivery is safe. Persist
`encode_state_as_update_v1/v2`; replicate subdocument contents separately.

Defaults are UTF-16 offsets and retained deleted content (`skip_gc=true`). Use
`offset_kind=Bytes, skip_gc=false` for Rust's defaults. Snapshot reconstruction
requires retained content. Observers have explicit subscription keys and cancellation.

See [COMPATIBILITY.md](COMPATIBILITY.md) for exact adaptations and
[the API contract](validation/api-contract.json) for the disposition of every
pinned public declaration/member. Corrections to upstream behavior have
[retained reproductions](validation/REFERENCE_LIMITATIONS.md). Yrs weak links are
an upstream extension; their semantics are checked against Rust, not Yjs 13.

The 0.1.1 follow-up fixes gaps found by a fresh Codex CLI review: typed v2
rich-text values, sparse relays and history, ghost weak subscriptions, and
retained observer transactions. See the [review and issue dispositions](validation/reviews/2026-10-16-ultra.md).

## Validation

196 tests pass on all four backends. Differential tests use unchanged Yrs at
`ac339600c712642e556895426113c3f9c117de39` and pinned Yjs 13.6.27.
The core matrix covers 641 scenarios across both wire formats and GC modes.
Mixed MoonBit/Yjs undo tests check rendered content, state vectors, deletion ranges,
notifications and persistence on JavaScript and native. The observer-only network
matrix checks 128 histories per backend with shuffled packets and duplicates.

The sparse oracle requires each receiver to reach the independent Rust causal
fixed point without resending packets. Weak-reference tests check current visible
quote boundaries independently, then replay identical wire histories to compare
views and notifications. Known reference failures remain explicit assertions;
passing a supported-contract gate is not a claim of exact Rust bug parity.

[Reproduction instructions](validation/README.md) describe all release suites.
`validation/release-*-results.json` records the library source hash and command
outcomes; detailed oracle reports record counts and reference exceptions.
Historical development measurements are retained in
[validation/DEVELOPMENT_HISTORY.md](validation/DEVELOPMENT_HISTORY.md).

## Performance and limits

Correctness compatibility does not imply performance parity. The last full native
benchmark on the largest GC-enabled editing trace measured about **120 seconds
and 117 MiB peak RSS** for MoonBit versus **12.9 seconds and 93 MiB** for Rust.
Those measurements predate the final correctness fixes; see the exact revisions
and whole-process methodology in [the native report](validation/trace-native-results.json).
The [JavaScript report](validation/trace-results.json) is recorded separately.

Collection positions use MoonBit `Int`; binary clocks retain the full UInt32 range.
Decoder resource limits and host memory still apply. This initial release has
extensive interoperability tests, not a claim of exhaustive verification,
unrestricted native thread safety or production deployment history.

## License

MIT; upstream notices are retained in [LICENSE](LICENSE).
