#!/usr/bin/env python3
"""Typed logical collection identities, replica resolution and Rust serde."""
import json
import random
from compare import ROOT, run
from updates import execute

def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'handles'])
    run(['moon', 'build', 'validation/handles', '--target', 'js', '--release'])
    rng = random.Random(71823)
    identities = [0, 1, 0xffffffff, (1 << 53) - 2] + [rng.randrange((1 << 53) - 1) for _ in range(124)]
    cases = [[client, ['', 'notes', '文档🌙', 'quote"/\\'][i % 4], gc]
             for i, client in enumerate(identities) for gc in [False, True]]
    reference = execute(['validation/rust/target/release/handles'], cases)
    actual = execute(['node', 'validation/handles.cjs'], cases)
    assert reference == actual, 'logical handle results differ'
    result = {
        'upstream': 'ac339600c712642e556895426113c3f9c117de39',
        'cases': len(cases), 'checks': [
            'non-creating root lookup', 'typed root creation',
            'root and nested hook serde including phantom tag',
            '53-bit client identifiers and Unicode root names',
            'v2 replica resolution', 'v1 deletion and replacement propagation',
            'deleted identities never resolve to replacements',
            'both retained and garbage-collected deletions'],
        'status': 'passed',
    }
    (ROOT / 'validation/handle-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)

if __name__ == '__main__':
    main()
