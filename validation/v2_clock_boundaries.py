#!/usr/bin/env python3
"""Full clock-column width against Yjs, with an explicit pinned Rust overflow witness."""
import json
import random
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'update_codecs'])
    run(['moon', 'build', 'validation/update_codecs', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/update_codecs']
    moon = ['node', 'validation/update_codecs.cjs']
    yjs = ['node', 'validation/yjs/clock-columns.cjs']
    boundary = [0, 1, (1 << 30)-1, 1 << 30, (1 << 31)-1, 1 << 31, (1 << 32)-2, (1 << 32)-1]
    cases = [{'v2': True, 'ops': [[field, ['7', clock]]]}
             for field in ['left', 'right'] for clock in boundary]
    rng = random.Random(813001)
    for _ in range(128):
        ops = [[rng.choice(['left', 'right']), [str(rng.choice([0, 7, (1 << 53)-1])),
                rng.choice(boundary) if rng.randrange(2) else rng.randrange(1 << 32)]] for _ in range(128)]
        cases.append({'v2': True, 'ops': ops})
    a = execute(moon, cases)
    b = execute(yjs, cases)
    assert a == b
    for case, row in zip(cases, a):
        assert row['decoded']['values'] == [op[1] for op in case['ops']]
    assert execute(moon, [dict(c, bytes=r['encoded']) for c, r in zip(cases, b)]) == a
    assert execute(yjs, [dict(c, bytes=r['encoded']) for c, r in zip(cases, a)]) == b
    witness = {'v2': True, 'ops': [['left', ['7', 1 << 30]]]}
    reference = execute(rust, [witness])[0]
    correct = execute(moon, [witness])[0]
    assert reference['decoded']['values'] == [['7', 3 << 30]], reference
    imported = execute(rust, [dict(witness, bytes=correct['encoded'])])[0]
    assert imported['decoded'] == 'error', imported
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'yjs_version': '13.6.27',
              'streams': len(cases), 'clock_fields': sum(len(c['ops']) for c in cases),
              'moonbit_yjs_exact_bytes_and_values': True,
              'rust_only_witness': {'input': witness, 'self_decoded': reference['decoded'],
                                    'valid_yjs_packet_decode': imported['decoded']},
              'status': 'passed with reproduced pinned Rust overflow'}
    (ROOT/'validation/v2-clock-boundary-results.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
