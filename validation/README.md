# Reproducing the compatibility checks

Use MoonBit `0.10.15+943464bfa`, Node.js 24, Python 3, and Rust 1.97.1.
The tested Moon CLI version is `0.1.20261012`. The Rust oracle is Yrs 0.28.0
with `weak` enabled at the exact commit below; its source must stay unchanged.

From the repository root, if the reference checkout does not already exist:

```sh
git clone https://github.com/y-crdt/y-crdt.git .repos/y-crdt
git -C .repos/y-crdt checkout --detach ac339600c712642e556895426113c3f9c117de39
rustup toolchain install 1.97.1 --profile minimal
npm ci --ignore-scripts --prefix validation/yjs
```

The Yjs lockfile pins 13.6.27. Each Python runner builds its MoonBit and Rust
bridges as needed. Do not update dependencies or patch the reference to make an
oracle pass.

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon info
python3 validation/compare.py
python3 validation/contracts.py
python3 validation/handles.py
python3 validation/value_decode.py
python3 validation/protocol_codec.py
python3 validation/sparse_wire.py
python3 validation/pending.py
python3 validation/pending_scheduling.py
python3 validation/transactions.py
python3 validation/presence.py
```

`.github/workflows/ci.yml` runs units on Linux/macOS and these oracle groups on
macOS using pinned GitHub action revisions. The lifecycle job also runs the
smallest real editing trace on native. The workflow has been prepared locally;
it has not yet run in GitHub because the public repository is not created.

For longer editing and memory checks on macOS:

```sh
python3 validation/traces.py --target native
python3 validation/traces.py --target js
```

These commands replay all five bundled reference traces with GC enabled and
disabled. The RSS measurement currently uses macOS `/usr/bin/time -l`; its
numbers include the whole process and are not microbenchmarks.

The other runners cover focused history, cursor, attribution, weak reference,
subdocument, JSONPath, and concurrent undo scenarios. Their matching
`*-results.json` files record scope and counts. A runner may exit successfully
while reporting an explicitly expected reference exception or partial parity:
that verifies the stated invariants, not full compatibility. Consult
[`REFERENCE_LIMITATIONS.md`](REFERENCE_LIMITATIONS.md) and
[`../COMPATIBILITY.md`](../COMPATIBILITY.md) before interpreting a green CI run.
