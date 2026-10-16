# Compatibility scope and release gates

The reference is Yrs 0.28.0 at
`ac339600c712642e556895426113c3f9c117de39`, with its `weak` feature enabled.
Yjs 13.6.27 is a second wire-format reference. **This port is still in development;
full upstream compatibility is not established.** Passing the core suite is one
part of that work, not a release certification.

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
| `Quotable`, `WeakPrelim`, `WeakRef` | Concrete `quote` methods, `WeakPrelim`, `WeakRef`; query/event differences remain open |
| `SharedRef`, `RootRef`, `Root`, `Nested`, `Hook` | Open traits, generic hook creation, typed collection resolution and identity serialization |
| `StateVector`, `Snapshot`, `Update`, `IdSet` | Implemented, including owned empty-client metadata and v1/v2 round-trips |
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
a declaration inventory, **not a completed semantic audit** or a coverage percentage.
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
- `types` / `undo`: concrete editing and observation are implemented; method-level
  edge cases, generic conversions and event equivalence remain under audit.
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

## Behavioral gates still open

| Area | Current evidence | Work remaining |
| --- | --- | --- |
| Ordinary sparse pending delivery | Complete histories and scoped GC agree; original-packet fixed-point replay agrees in all 512 cases | Ordinary buffering intentionally differs in 44 cases; a reduced retry-watermark/head-blocking fixture explains how the 14 persistent cases arise. Exact buffered-state parity remains unclaimed |
| Weak references | Mixed-runtime concurrent editing converges; broad query/event oracles retained | Resolve query inconsistencies and additional port notifications; do not label partial event comparisons as passes |
| Concurrent undo | GC-disabled mixed-author networks pass; GC-enabled MoonBit-authored networks pass with Rust wire/event mirrors; 9,984 post-undo reloads pass across GC modes. Restored-parent persistence and inferred-GC deletion propagation defects corrected | Expanded GC-enabled mixed-author gate encounters a Rust panic, now reproduced by seven Rust-only operations. The port passes that regression on every backend. Strict independent histories differ because pinned Rust loses restored map entries; independently allocated restoration identities remain under audit |
| Public API | Root exports inventoried above; main editing and protocol APIs implemented | Finish method/module audit and resolve or explicitly define the portability boundary for unimplemented APIs |
| Performance | All five real editing traces pass on JS/native with GC on/off | Clock-index and position-cache changes remeasured on both backends; address the substantial large-trace runtime gap |
| Release packaging | Local small commits and reproducible oracle scripts | Pinned CI and reproduction instructions are prepared locally; finish the supported-feature contract and regression gates, then create the public GitHub repository |

Known reference defects and deliberate corrections are recorded in
[`validation/REFERENCE_LIMITATIONS.md`](validation/REFERENCE_LIMITATIONS.md).
Individual `validation/*-results.json` files describe the exact scope of each
comparison. They must not be combined into a blanket percentage of compatibility.
