#!/usr/bin/env python3
"""Public v1/v2 codec field streams against unchanged pinned Yrs."""
import json
import random
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'update_codecs'])
    run(['moon', 'build', 'validation/update_codecs', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/update_codecs']
    moon = ['node', 'validation/update_codecs.cjs']
    rng = random.Random(811715)
    cases = []
    for seed in range(128):
        ops = []
        clock = 0
        for i in range(128):
            kind = rng.choice(['left', 'right', 'client', 'string', 'key', 'info', 'type', 'len', 'parent', 'any', 'json', 'var', 'ds', 'reset'])
            if kind in ['left', 'right']:
                value = [str(rng.choice([0, 1, 255, (1 << 53)-1])), rng.randrange(1 << 20)]
            elif kind == 'client':
                value = str(rng.choice([0, 1, 255, (1 << 53)-1]))
            elif kind in ['string', 'key']:
                value = rng.choice(['', 'key', 'key', '\ufeff🌙中文', 'x'*128])
            elif kind in ['info', 'type']:
                value = rng.randrange(256)
            elif kind == 'parent':
                value = rng.choice([False, True])
            elif kind in ['any', 'json']:
                value = rng.choice([None, False, True, 0, 1, -1, 1.25, '🌙', [], [1, None, 'nested']])
            elif kind in ['len', 'var']:
                value = rng.choice([0, 1, 127, 128, 65535, (1 << 32)-1])
            elif kind == 'ds':
                clock += rng.randrange(1024)
                size = rng.randrange(1, 1024)
                ops += [['dsclock', clock], ['dslen', size]]
                clock += size
                continue
            else:
                clock = 0; value = None
            ops.append([kind, value])
        cases += [dict(ops=ops, v2=v2) for v2 in [False, True]]
    # Long runs and alternating deltas across every compression column.
    for field, values in [('client', ['7']*256), ('info', [3]*256), ('type', [7]*256), ('len', [127]*256), ('parent', [True]*256), ('left', [['17', n] for n in range(256)]), ('right', [['17', 500 - n] for n in range(256)])]:
        cases += [dict(ops=[[field, v] for v in values], v2=v2) for v2 in [False, True]]
    expected = execute(rust, cases)
    actual = execute(moon, cases)
    byte_differences = 0
    for i, (r, m) in enumerate(zip(expected, actual)):
        assert r['decoded'] == m['decoded'] and r['decoded'] != 'error', (i, cases[i], r, m)
        byte_differences += r['encoded'] != m['encoded']
    rust_import = execute(rust, [dict(case, bytes=out['encoded']) for case, out in zip(cases, actual)])
    moon_import = execute(moon, [dict(case, bytes=out['encoded']) for case, out in zip(cases, expected)])
    for r, m, ri, mi in zip(expected, actual, rust_import, moon_import):
        assert ri['decoded'] == r['decoded'] == mi['decoded'] == m['decoded']
    raw_cases = [dict(v2=v2, raw=True, ops=[['all', [1, 2, 3]], ['buf', [4, 5]], ['u32', 16909060], ['u8', 238]]) for v2 in [False, True]]
    assert execute(rust, raw_cases) == execute(moon, raw_cases)
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'field_streams': len(cases),
              'fields': sum(len(c['ops']) for c in cases), 'cross_runtime_streams': 2*len(cases),
              'valid_nonidentical_encodings': byte_differences, 'raw_framing_cases': len(raw_cases),
              'checks': ['all update codec fields', 'v2 RLE runs and increasing/decreasing clock deltas',
                         'repeated Unicode keys', 'delete-set clock resets and lengths', 'raw stream framing'], 'status': 'passed'}
    (ROOT / 'validation/update-codec-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)

if __name__ == '__main__':
    main()
