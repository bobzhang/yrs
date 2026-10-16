# Pinned reference limitations

The oracle uses Yrs 0.28.0 at `ac339600c712642e556895426113c3f9c117de39` without modifying its source.

## Sparse updates and garbage collection

`fixtures/upstream-sparse-gc-crash.json` is a reduced 15-operation reproducer for a bus error in the Rust reference when GC is enabled. It combines nested map replacement, queued updates and differential updates with missing history. On macOS, the process exits with SIGBUS; it does not return a Rust error. The reference completes with GC disabled.

After building the validation binary, reproduce with:

```sh
validation/rust/target/release/yrs-reference v1 --gc < validation/fixtures/upstream-sparse-gc-crash.json
```

The randomized relay oracle records this reference failure explicitly. It rejects unrecognized reference crashes. The matching scenario remains checked with GC disabled; the other GC-enabled histories are checked normally. This is a limitation of the reference comparison, not evidence of a passing GC comparison for the crashing case.

A second GC-enabled history, `fixtures/upstream-overflowing-skip-history.json`, makes the reference emit a skip block of length `UINT32_MAX` at a nonzero clock. The captured binary update is in `fixtures/upstream-overflowing-skip.json`. Adding that length overflows Yjs's 32-bit clock domain. The port rejects it before mutating the document; the relay oracle records this malformed-reference-output case separately instead of weakening overflow validation.

Garbage collection changes the dependency metadata of deleted blocks. Two independent producers with different GC policies can therefore expose different intermediate states when history is missing. The relay oracle compares every intermediate state using identical binary histories, and checks that each producer converges after full synchronization. Independent histories are compared operation by operation only when both producers retain tombstones; otherwise different intermediate states change later position-based edits.

## Rich-text attribute order

Rust attributes use hash maps. Their iteration order can change formatting-marker allocation, and in some concurrent histories the resulting formatting, even between two runs of the same Rust commands. Rich-text validation therefore compares identical binary histories in both runtimes and local operations starting from identical serialized documents. Cross-runtime imports must preserve exact state vectors. Adjacent strings with identical attributes are normalized only for delta chunk-boundary comparisons.

## Sparse v2 encoding

The pinned reference also panics in `transaction.rs:408` when merging its own pending v2 updates (`UnexpectedValue`). Its `BlockSlice::Skip` encoder writes the length through the v2 length column, while its update decoder reads skip lengths from the raw stream. The port uses the raw stream, matching the decoder and Yjs wire format. `validation/updates.py` currently records v1 relay/utility comparisons; the regular collection/rich-text suite still checks both v1 and v2. Sparse v2 is covered by MoonBit regression tests, with cross-runtime validation still outstanding.

## Historical snapshot clipping

The pinned snapshot encoder can emit a right-origin flag without the corresponding
ID when clipping a compacted text block. Reproduction: insert `ab`, insert `X` at
index 1, take a snapshot, then insert `Y` at index 2. Encoding the earlier snapshot
produces `010301000401046e6f746501618401000162c4010002585900`, which Rust itself rejects
with `EndOfBuffer(89)`. The relevant path is `ItemSlice::encode` in `slice.rs`:
`item.info()` retains `HAS_RIGHT_ORIGIN`, but the ID is written only when
`adjacent_right()` is true.

Reproduce without modifying upstream:

```sh
cargo +1.97.1 run --release --locked --manifest-path validation/rust/Cargo.toml --bin history -- --reference-snapshot-regression
```

The history oracle captures actual Rust text at snapshot creation, then requires
MoonBit to reconstruct that content after every subsequent operation. It compares
snapshot state vectors and deletion ranges independently, exchanges snapshot and
cursor encodings in both directions, and records this reference failure in the
results. No historical reconstruction cases are excluded because of this defect.

## Undo restoration order

The unchanged pinned Rust implementation restores an unordered set of items.
Fresh processes can therefore produce different item identities and, in some
histories, different rendered results. This is not a reason to accept an arbitrary
port result: the undo oracle requires a fresh Rust run to match the complete
MoonBit history prefix (up to 64 attempts). Every accepted alternative is logged
in `undo-results.json`.

Reproduce with the `undo` reference binary and either fixture:

- `fixtures/upstream-undo-map-order.json`: the same final map entry was observed
  as both 24 and 81 in separate runs.
- `fixtures/upstream-undo-xml-nondeterminism.json`: after repeated XML undo and
  restoration, the final map-only edit was observed to leave the XML text as
  `hello` or shorten it to `h`. The occurrence depends on restoration order;
  repeat the fixture across fresh processes. The harness does not modify the
  upstream checkout or its hashing implementation.

The default undo comparison uses a single editing author with synchronization to
followers and explicit bidirectional binary transfers. Multiple independent undo
authors are an additional, currently failing compatibility configuration; their
restored identities can affect later conflict ordering. Do not interpret the
single-author result as proof of full concurrent undo compatibility. Exact undo
observer-event equivalence also remains unverified; the separate event oracle
covers grouped and concurrent changes without independently generated undo.

## Subdocument destruction leaves a stale registry handle

`validation/fixtures/upstream-subdoc-destroy-registry.json` inserts child A,
explicitly destroys it, then removes its parent map entry. Pinned Yrs leaves A
in `ReadTxn::subdocs()` even though the map is empty. `Doc::destroy` registers
the replacement in both the added and removed identity maps; the original
registration survives. The MoonBit port removes the old identity and registers
the replacement, so removing the slot leaves an empty registry. This is an
intentional compatibility difference, not a passing exact-reference case.

`validation/subdocs.py` compares the complete registry, child state and lifecycle
events in 96 randomized histories without explicit destroy. A separate 32-history
destroy matrix compares child state and lifecycle events, excluding only the
reference registry. It independently requires the MoonBit registry to contain
exactly the live map slots, including duplicate GUIDs. Parent wire replays are
checked against both runtimes; child contents are replicated separately.


## Live mixed-runtime undo and formatting cleanup

`undo_mixed.py` uses persistent, unchanged-reference Rust sessions and persistent
MoonBit sessions. Each logical replica has one editing owner and a mirror in the
other runtime; the mirror replays wire updates rather than independently running
undo. This preserves the exact identities that drive conflict resolution. The
96-history matrix passes both wire formats, including nested collections, XML,
remote edits, undo/redo, duplicate delivery and final replica convergence.

Importing rich text can generate additional formatting deletion operations. A
mirror and its source therefore exchange those generated updates before their
complete rendered states are compared. The result records the number of such
reconciliation rounds; it does not omit formatting or normalize away attribute
differences. This checks convergence after all generated operations have arrived,
not equality before those additional deletions have been delivered. Observer
notifications and independently allocated undo identities remain outside this
matrix. The prior independent-history failure is not removed or marked passed.


## Legacy JSON content decoder

The pinned Rust `ItemContent::JSON` decoder reads `count + 1` strings because its
loop uses `remaining >= 0`. Its encoder writes exactly `count` strings. The
valid v1 packet in `fixtures/upstream-legacy-json.json` is accepted by Yjs
13.6.27 and rejected by pinned Rust with `EndOfBuffer`. The Rust output conversion
also exposes the encoded JSON strings rather than their parsed values.

The port follows [Yjs ContentJSON](https://github.com/yjs/yjs/blob/v13.6.27/src/structs/ContentJSON.js):
read exactly the declared number of entries, parse each JSON value and preserve
the special `undefined` entry. `legacy.py` asserts the pinned Rust failure and
checks 64 v1/v2 cases against pinned Yjs, including deletion, block splitting and
replay of MoonBit output. This is an explicit reference exception; it is not a
passing Rust legacy-content comparison. A separate Rust matrix checks opaque
shared-type references 5, 9 and 15 with modern content, in both wire formats and
GC modes. Type reference 9 is distinct from actual subdocument content reference 9.


## Saved undo stacks and independently allocated identities

`fixtures/undo-reload-independent-identity.json` also demonstrates that independent
undo/reload histories can allocate different restored IDs while the rendered
text remains equal. Those IDs become visible in later stack deletion ranges.
The saved-stack contract oracle therefore starts each comparison from the exact
same Rust document update and serialized undo/redo stacks. It compares complete
output stack records and metadata, undo/redo results, and event parent multisets.
This validates cross-runtime stack restoration rather than requiring identical
allocation from independently generated histories. It does not resolve the
previously documented independent-history limitation.
