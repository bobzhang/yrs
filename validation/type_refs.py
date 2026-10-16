#!/usr/bin/env python3
"""All public type descriptors, including weak boundaries, against pinned Yrs."""
import json
import random
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'update_codecs'])
    run(['moon', 'build', 'validation/update_codecs', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/update_codecs']
    moon = ['node', 'validation/update_codecs.cjs']
    values = [{'kind': kind} for kind in [0, 1, 2, 4, 5, 6, 9, 15]]
    values += [{'kind': 3, 'tag': name} for name in ['', 'p', '🌙中文', '\ufeff', 'x'*128]]
    for client in [0, 1, 127, 128, (1 << 53)-1]:
        for clock in [0, 1, 127, 128, (1 << 32)-1]:
            item = {'item': {'client': client, 'clock': clock}}
            for parent in [{'tname': 'root🌙'}, {'type': {'client': client, 'clock': clock}}]:
                for start in [item, parent]:
                    for end in [item, parent, {'item': {'client': 999, 'clock': 10}}]:
                        for a in [-1, 0]:
                            for b in [-1, 0]:
                                values.append({'kind': 7, 'start': dict(start, assoc=a), 'end': dict(end, assoc=b)})
    rng = random.Random(771081)
    rng.shuffle(values)
    cases = []
    for offset in range(0, len(values), 41):
        ops = [['typevalue', v] for v in values[offset:offset+41]] + [['key', 'suffix'], ['var', 4242]]
        cases.extend(dict(ops=ops, v2=v2) for v2 in [False, True])
    a, b = execute(rust, cases), execute(moon, cases)
    assert a == b, next(((i, r, m) for i, (r, m) in enumerate(zip(a, b)) if r != m), None)
    for row in a:
        assert row['decoded'] != 'error'
        assert all(v['equal'] for v in row['decoded']['values'][:-2])
        assert row['decoded']['values'][-2:] == ['suffix', 4242]
    for receiver, producer in [(rust, b), (moon, a)]:
        received = execute(receiver, [dict(case, bytes=row['encoded']) for case, row in zip(cases, producer)])
        assert received == a
    # Every truncated single-descriptor v1 encoding must fail in both decoders.
    singles = [dict(ops=[['typevalue', v]], v2=False) for v in values]
    encoded = execute(rust, singles)
    truncated = [dict(case, bytes=row['encoded'][:n]) for case, row in zip(singles, encoded) for n in range(len(row['encoded']))]
    for receiver in [rust, moon]:
        for offset in range(0, len(truncated), 256):
            assert all(row['decoded'] == 'error' for row in execute(receiver, truncated[offset:offset+256]))
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'descriptors': len(values),
              'wire_versions': [1, 2], 'composed_streams': len(cases), 'cross_runtime_streams': 2*len(cases),
              'truncated_v1_inputs_per_runtime': len(truncated), 'exact_bytes_equal': True,
              'checks': ['all type tags', 'Unicode XML names', 'single and ranged weak links',
                         'root/nested unbounded endpoints', 'both associations', 'client/clock boundaries',
                         'interleaved compression columns and trailing fields'], 'status': 'passed'}
    (ROOT/'validation/type-ref-results.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
