#!/usr/bin/env python3
"""Full UInt32 compressed GC/deleted runs against unchanged Rust and Yjs."""
import json
from compare import ROOT, run
from updates import execute, varuint

MAX = (1 << 32) - 1
HALF = (1 << 31) - 1


def packet(kind, lengths):
    out = varuint(1) + varuint(len(lengths)) + varuint(7) + varuint(0)
    clock = 0
    for length in lengths:
        out += bytes([kind | (128 if kind and clock else 0)])
        if kind:
            out += varuint(7) + varuint(clock-1) if clock else b'\x01\x04note'
        out += varuint(length)
        clock += length
    return (out + b'\0').hex()


def normalize(states):
    return [[str(c), n] for c, n in states]


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'yrs-reference'])
    run(['moon', 'build', 'validation/bridge', '--target', 'js', '--release'])
    assert json.loads((ROOT/'validation/yjs/node_modules/yjs/package.json').read_text())['version'] == '13.6.27'
    cases = []
    for kind in [0, 1]:
        for length in [1, 127, 128, HALF-1, HALF, HALF+1, MAX-1, MAX]:
            for cut in sorted({0, 1, length//2, min(length, HALF), length-1, length}):
                full = packet(kind, [length])
                split = packet(kind, [cut, length-cut]) if 0 < cut < length else full
                prefix = packet(kind, [cut]) if cut else '0000'
                cases.append((kind, length, cut, full, split, prefix))
    checks = relays = 0
    groups = []
    for version, name, active, use_rust in [
        ('v1', 'all-ranges', cases, True),
        ('v2', 'rust-supported-ranges', [c for c in cases if c[0] == 0 or c[1] < (1 << 30)], True),
        ('v2', 'large-item-origins', [c for c in cases if c[0] == 1 and c[1] >= (1 << 30)], False),
    ]:
        engines = [['node', 'validation/run.cjs', version],
                   ['node', 'validation/yjs/large-ranges.cjs', version]]
        if use_rust:
            engines.insert(0, ['validation/rust/target/release/yrs-reference', version])
        wires = [[full, split, prefix] for _, _, _, full, split, prefix in active]
        if version == 'v2':
            wires = execute(['node', 'validation/yjs/large-ranges.cjs', 'convert'], wires)
        requests = [{'updates': [full, split, full], 'remote': (varuint(1)+varuint(7)+varuint(cut)).hex()}
                    for (_, _, cut, _, _, _), (full, split, _) in zip(active, wires)]
        outputs = [execute(engine+['utilities'], requests) for engine in engines]
        for rows in outputs:
            for (_, length, _, _, _, _), row in zip(active, rows):
                assert normalize(row['states']) == [['7', length]], row
                checks += 1
        for gc in [False, True]:
            commands = [engine + (['--gc'] if gc else []) for engine in engines]
            for producer in outputs:
                histories = [[['a', 0, prefix], ['a', 0, row['diff']], ['a', 0, row['diff']], ['a', 1, row['merged']], ['a', 2, full]]
                             for (full, _, prefix), row in zip(wires, producer)]
                applied = [execute(command, histories) for command in commands]
                for rows in applied:
                    for (_, length, _, _, _, _), row in zip(active, rows):
                        assert all(normalize(sv) == [['7', length]] for sv in row['states']), row
                        checks += 3
                    # Reimport persisted state into every participating engine.
                    saved = [[['a', 0, row['updates'][0]]] for row in rows]
                    for command in commands:
                        for (_, length, _, _, _, _), row in zip(active, execute(command, saved)):
                            assert normalize(row['states'][0]) == [['7', length]], row
                            relays += 1
        groups.append({'format': version, 'group': name, 'cases': len(active),
                       'engines': ['rust', 'moonbit', 'yjs'] if use_rust else ['moonbit', 'yjs']})
        print(f'{version} {name}: {len(active)} unsigned range cases passed', flush=True)
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'yjs_version': '13.6.27',
              'groups': groups, 'gc_modes': [False, True],
              'rust_v2_large_item_origin_limitation': 'See v2_clock_boundaries.py: pinned signed delta overflow',
              'state_checks': checks, 'cross_runtime_reloads': relays, 'status': 'passed'}
    (ROOT/'validation/large-range-results.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
