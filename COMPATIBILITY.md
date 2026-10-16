# Compatibility scope and release gates

The reference is Yrs 0.28.0 at
`ac339600c712642e556895426113c3f9c117de39`, with its `weak` feature enabled.
Yjs 13.6.27 is a second wire-format reference. The agreed contract is **complete
public CRDT capabilities and wire interoperability with documented adaptations**.
It does not require Rust source/ABI compatibility, raw storage mutation, native
lock/future APIs, identical allocation order, or reproducing upstream defects.
Every discovered port correctness defect must be fixed and regression-tested.
The implementation audit is complete; the final release run is in progress.

## Public API inventory

The following inventory accounts for all 83 root exports in the pinned Rust
`lib.rs`. “Adapted” means the operation is expressed using MoonBit types or
methods; it does not mean that every edge case has been proved equivalent.
The generated `pkg.generated.mbti` is the authoritative MoonBit API.

| Rust root exports | MoonBit surface / status |
| --- | --- |
| `Doc`, `OffsetKind` | Implemented; explicit constructor options and defaults below |
| `Options` | Adapted to labeled `Doc(...)` arguments |
| `ClientID`, `ID`, `BranchID` | `UInt64`, `Id`, `BranchId`; the port also accepts client IDs beyond Rust's 53-bit domain |
| `Any`, `Number` | `Any`, direct casts, optional collection iterators and composable byte-stream codecs; numeric variants are `Integer(Int64)` and `Float(Double)` |
| `In`, `Out`, deprecated `Value` | `In`, `Out`, generic `Out.cast[T : FromOut]` with original-value errors; no deprecated `Value` alias |
| `Array`, `ArrayRef`, `ArrayPrelim` | `ArrayRef` methods, typed `get_as`, and `In.Array` preliminary values |
| `Map`, `MapRef`, `MapPrelim` | `MapRef` methods, typed `get_as`, generic `get_or_init[T : DefaultPrelim]`, concrete helpers and `In.Map` preliminary values |
| `Text`, `TextRef`, `TextPrelim` | `Text` methods, primitive/shared embeds with inherited or explicit formatting, and `In.Text` preliminary values |
| `Xml`, `XmlOut` | `XmlNode`, concrete XML methods and `In` constructors |
| `XmlElementRef`, `XmlElementPrelim` | `XmlElement`, `In.XmlElement` |
| `XmlFragment`, `XmlFragmentRef`, `XmlFragmentPrelim` | `XmlFragment`, `In.XmlFragment` |
| `XmlTextRef`, `XmlTextPrelim` | `XmlText`, `In.XmlText` |
| `GetString`, `Observable`, `DeepObservable` | Concrete `get_string`, `observe`, `observe_deep`, and keyed `unobserve` methods |
| `Quotable`, `WeakPrelim`, `WeakRef` | Concrete `quote` methods, `WeakPrelim`, `WeakRef`; corrected visible boundaries, queries and subscriptions described below |
| `SharedRef`, `RootRef`, `Root`, `Nested`, `Hook` | Open traits, generic hook creation, typed collection resolution and identity serialization |
| `StateVector`, `Snapshot`, `Update`, `IdSet` | Implemented, including owned empty-client metadata and v1/v2 round-trips |
| `BlockRange` | Identity endpoints, half-open interval, slice and membership checked against Rust |
| `IdMap`, `AttrRange`, `ContentAttribute`, `ContentAttributes`, `Diff` | Generic attribution types and operations; `Diff` is used for text history results |
| `Assoc`, `IndexScope`, `Offset`, `StickyIndex`, `IndexedSequence` | Cursor types plus concrete collection `sticky_index` / `sticky_boundary` methods |
| `JsonPath`, `JsonPathEval` | `JsonPath` and `Doc.json_path` |
| `Observer` | Generic `Observer[K,F]` with explicit keyed cancellation |
| `Transaction`, `TransactionMut`, `ReadTxn`, `WriteTxn`, `Transact` | Callback-scoped `Doc.transact`, `Transaction` metadata, and direct collection operations |
| `Origin` | `Bytes`; identity tokens are serialized explicitly |
| `RootRefs`, `SubdocsEventIter` | Arrays/iterators of root entries and child documents |
| `SubdocsEvent`, `TransactionCleanupEvent`, `UpdateEvent` | `SubdocsEvent`, `Transaction`, and update bytes passed to callbacks |
| `UndoManager` | `UndoManager[M]`, with injectable clock and metadata |
| `AcquireTransaction`, `AcquireTransactionMut`, `AsyncTransact`, `TransactionAcqError` | Rust lock-acquisition/future types have no implementation; the portable document is confined to its host execution context |
| `Store` | Exposed through `Doc`: state, roots, root-key paths, owned pending block/deletion inspection, pending pruning and scoped GC; no public raw mutable store or lock interface |
| `Uuid`, `uuid_v4`, `uuid_v4_from` | GUIDs are strings; `uuid_v4_from(Bytes)` formats 16 network-order bytes and `uuid_v4(entropy)` uses a host-provided entropy callback |
| `merge_updates_v1`, `merge_updates_v2` | Implemented stateless update union |
| `diff_updates_v1`, `diff_updates_v2` | Implemented stateless state-vector clipping |
| `encode_state_vector_from_update_v1`, `encode_state_vector_from_update_v2` | Implemented contiguous-prefix extraction |

The compiler-derived [public API inventory](validation/public-api-inventory.json)
now records 225 reachable declarations and 802 inherent methods, trait members,
fields and variants, including public module paths and reexports. Regenerate it
with `python3 validation/public_api.py`; `--check` detects inventory drift. It is
a declaration inventory, not a coverage percentage. The reviewed
[`api-contract.json`](validation/api-contract.json) assigns all 225 declarations
and 802 members to 23 capability/adaptation groups with implementation descriptions
and test evidence. `python3 validation/api_contract.py` rejects omissions or member
drift; it does not substitute for semantic tests.
Rust also exposes
`block`, `doc`, `types`, `updates`, `any`, `atomic`, `branch`, `encoding`, `error`,
`iter`, `json_path`, `observer`, `sync`, and `undo` modules. In particular:

- `sync`: awareness, message codecs, `Protocol`, `AsyncProtocol`, and
  `DefaultProtocol` are available. Transport and scheduling are host concerns.
- `updates` / `encoding`: public v1/v2 utilities and codecs are available;
  open `Read` / `Write` stream traits, `Cursor`, and `ByteWriter` now support
  application-defined byte streams. Open `Encoder`, `Decoder`, `Encode` and `Decode`
  traits expose update fields, concrete v1/v2 codecs and application record composition.
  Updates, state vectors, deletion sets, snapshots and cursor metadata implement
  generic value codecs. Documents and transactions can also write directly through
  application-supplied field codecs, including historical snapshots; low-level block/branch internals remain outside the public API. Varint signedness and width are expressed explicitly
  with 64-bit methods; Rust's generic integer trait and u128 are not exposed.
- `block` / `branch` / `iter` / `atomic`: raw pointers, mutation internals,
  transaction-bound iterators and atomic storage are not ported as public APIs.
- Value serialization: `ToAny` / `to_any` and `FromAny` / `from_any` expose
  direct typed adapters without JSON precision loss;
  application records implement the open trait. `FromOut` exposes direct handle/primitive casts separately, including Rust's narrowing integer conversion. Built-in conversion rules are
  compared with Rust serde. Serialization covers primitives, optional values, arrays,
  string-keyed maps, pairs, raw bytes and custom records; 3,481 cases agree with
  Rust, including 906 unsigned-overflow rejections. Application enum/record
  representations are explicitly implemented with the open trait; MoonBit
  compiler-derived serde attributes are not provided. `get_json_as` is a separate MoonBit JSON adapter.
- `types` / `undo`: concrete editing, generic conversions and observation are implemented.
  The capability audit maps the complete pinned member surface to portable APIs.
  The open `AsPrelim` trait exposes `to_input` for generic deep-copy builders
  across shared collections, output values, XML nodes and weak links. Rust's
  associated preliminary types are represented by the `In` enum; application
  types can implement the trait without constructing an `Out` wrapper.
  `DeltaOf[T]` supplies generic insertion mapping; `Delta` and `TextDelta`
  specialize it to observed `Out` and preliminary `In` values. `Delta.to_input`
  detaches inserted shared values for replay. Empty attribute arrays represent
  both Rust `None` and `Some(empty)`; upstream `apply_delta` treats these equally.
  Public `TypeRef` descriptors expose every upstream kind, including legacy
  types and weak-link boundaries, and implement generic v1/v2 codecs. Typed root
  handles expose `RootRef.type_ref` and `RootRef.root`. The descriptor oracle
  checks 1,213 values against unchanged Rust with exact byte equality.
- Errors use MoonBit error types. Stricter malformed-input validation is
  intentional; Rust panic behavior is not a compatibility target.

## Host and language adaptations

`Doc(client_id=...)` requires a host-provided client ID. Subdocument GUIDs must be
unique and explicit; `uuid_v4` accepts the host's entropy callback. The default offset mode is UTF-16 and deleted content is
retained (`skip_gc=true`); Rust defaults to byte offsets and GC enabled. Pass
`offset_kind=Bytes, skip_gc=false` to select those Rust defaults. A protocol peer
must never reuse another active editor's client ID.

Transactions run synchronously within a callback. They batch notifications and
updates; they are not rollback transactions. The API does not expose a Rust-style
read/write lock or promise safe concurrent mutation from multiple native threads.
`AsyncProtocol` may suspend its handlers, but does not make `Doc` thread-safe.
The host must serialize access to a shared document.

Shared-handle equality compares logical branch IDs across documents. `Out`
also requires the same value variant. `Doc` equality compares GUIDs, whereas
`Doc.ptr_eq` compares in-memory instances; explicitly supply distinct GUIDs when
that distinction matters. Untyped `UndefinedRef` outputs use instance equality,
matching Rust's raw branch-pointer comparison.

Observers use explicit keys and cancellation instead of Rust RAII subscription
guards. Iterator-returning convenience methods may snapshot collections. These
are API/lifetime adaptations, not claims of identical Rust ownership behavior.

## Behavioral contract and evidence

| Area | Required behavior and evidence | Deliberate difference |
| --- | --- | --- |
| Core shared types | Text, rich text, arrays, maps, nested values and XML; 641 randomized scenarios in both formats and GC modes, with independent operations and wire replay | Attribute iteration can allocate different IDs; comparisons of conflict-sensitive edits use identical wire histories |
| Unsigned clock boundaries | Full-width GC/deleted ranges, 7,042 reloads and 16,400 exact Yjs clock fields | Corrects pinned Rust's large v2 delta overflow |
| Sparse delivery | All 512 sparse cases immediately equal the unchanged Rust original-packet causal fixed point; 320 scoped-GC cases pass | Ready blocks are not stalled behind unrelated missing dependencies. Corrupt pending encodings and stale pending flags are not reproduced |
| Weak references | All current visible range combinations, 9,004 positional quote checks, 74,240 identical-wire query/event snapshots and mixed-author convergence | Skip tombstones/format markers when constructing ranges; preserve subscriptions through splits, empty quotations and key reinsertion; reject Rust's internally inconsistent query results |
| Concurrent undo | Mixed Yjs/MoonBit authors in v1/v2 with both GC modes on JS/native; structured documents, causal state, notifications, high clocks and reloads | Restoration IDs may differ across independently authored undo. Correct restored-parent persistence; retain the seven-operation Rust GC panic witness |
| Observer transport | 128 mixed Yjs/MoonBit histories per backend converge using emitted packets alone, with shuffled delivery, duplicates and 768 reloads | Applications must forward updates produced by remote transactions too |
| History and positions | Snapshots, annotated diffs, attribution, cursor identities and byte/UTF-16 offset conversion | Correct malformed Rust snapshot output and byte-mode cursor units |
| Lifecycle and protocols | Subdocuments, transaction/deep events, awareness and custom synchronous/asynchronous sync handlers | Correct stale subdocument registry entries after destroy; transport/time/scheduling belong to the host |

The release suites in `validation/release.py` execute the supported contract.
Expected upstream failures are asserted by focused reproductions, never silently
converted to ordinary passing comparisons. The unmodified strict `undo.py` and
Rust-owned GC `undo_mixed.py` diagnostics remain available; independently
allocated undo IDs and the known upstream panic make those unsuitable as release
success criteria. The release instead tests mixed Yjs authors under both GC modes,
GC-disabled mixed Rust authors, GC-enabled port authors with Rust mirrors, and
saved-state roundtrips in both runtimes.

The port does not promise equal runtime/memory use: the largest measured native
editing trace is approximately nine times slower than Rust. This is a performance
limitation, not missing CRDT functionality. See the versioned benchmark reports.

Known reference defects and deliberate corrections are recorded in
[`validation/REFERENCE_LIMITATIONS.md`](validation/REFERENCE_LIMITATIONS.md).
Individual `validation/*-results.json` files describe their exact scope. Historical
reports saying “partial compatibility” refer to exact pinned Rust behavior; read
their exception details and the current contract rather than treating them as a
percentage. Release reports identify the exact library source hash tested.
