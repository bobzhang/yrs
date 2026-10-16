#!/usr/bin/env python3
"""Typed v2 rich-text values exchanged with unchanged pinned Rust Yrs."""
import json
from compare import ROOT, run
from updates import execute

def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'typed_v2'])
    run(['moon', 'build', 'validation/typed_v2', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/typed_v2']
    moon = ['node', 'validation/typed_v2.cjs']
    a, b = execute(rust, [[]])[0], execute(moon, [[]])[0]
    assert len(a) == len(b) == 3
    # Each bridge independently checks typed embeds and formatting attributes,
    # then re-exports the received content for a second cross-runtime roundtrip.
    from_moon = execute(rust, [b])[0]
    from_rust = execute(moon, [a])[0]
    assert len(from_moon) == len(from_rust) == 3
    assert execute(moon, [from_moon])[0] == b
    assert execute(rust, [from_rust])[0] == a
    result = dict(upstream='ac339600c712642e556895426113c3f9c117de39',
                  values=['Buffer([1,2])', 'Undefined', 'Integer(9007199254740993)'],
                  cross_runtime_document_transfers=12,
                  checks=['typed rich-text embeds', 'typed formatting attributes', 'bidirectional v2 re-export'], status='passed')
    (ROOT / 'validation/typed-v2-results.json').write_text(json.dumps(result, indent=2)+'\n')
    print(result)
if __name__ == '__main__': main()
