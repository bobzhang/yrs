#!/usr/bin/env python3
"""Public block-range boundaries and slicing against pinned Rust."""
import json
import random
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'attribution'])
    run(['moon', 'build', 'validation/attribution', '--target', 'js', '--release'])
    cases = []
    rng = random.Random(718819)
    ranges = [(s, n) for s in [0, 1, 127, 128, (1 << 31), (1 << 32)-2, (1 << 32)-1]
              for n in [0, 1, 127, (1 << 32)-1-s] if s+n < (1 << 32)]
    ranges += [(s := rng.randrange(1 << 32), rng.randrange((1 << 32)-s)) for _ in range(1024)]
    for start, length in ranges:
        client = rng.choice([0, 1, 127, (1 << 53)-1])
        for offset in sorted({0, length, length//2}):
            clocks = sorted({max(0, start-1), start, min((1 << 32)-1, start+1), start+length})
            cases.append({'range': [client, start, length], 'offset': offset,
                          'ids': [[c, clock] for c in [client, client ^ 1] for clock in clocks]})
    a = execute(['validation/rust/target/release/attribution'], cases)
    b = execute(['node', 'validation/attribution.cjs'], cases)
    assert a == b, next(((i, r, m) for i, (r, m) in enumerate(zip(a, b)) if r != m), None)
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'ranges': len(ranges),
              'slice_cases': len(cases), 'membership_queries': sum(len(c['ids']) for c in cases),
              'last_id_is_exclusive_endpoint': True, 'status': 'passed'}
    (ROOT/'validation/block-range-results.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
