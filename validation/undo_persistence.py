#!/usr/bin/env python3
"""Every successful sampled undo/redo must survive reload in both runtimes."""
import json
from compare import ROOT, run
from undo import execute, canonical
from undo_mixed import Session, history


def doc(value):
    return canonical({'docs': [value]})['docs'][0]


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'undo'])
    run(['moon', 'build', 'validation/undo', '--target', 'js', '--release'])
    fixture = json.loads((ROOT / 'validation/fixtures/upstream-undo-restored-attribute-parent.json').read_text())
    reference_defects = 0
    actions = transfers = 0
    seeds = list(range(24)) + list(range(48, 72))
    for gc, version in [(gc, v) for gc in [False, True] for v in ['v1', 'v2']]:
        flags = ['--gc'] if gc else []
        rust = ['validation/rust/target/release/undo', version] + flags
        moon = ['node', 'validation/undo.cjs', version] + flags
        r = execute(rust, [fixture])[0]
        m = execute(moon, [fixture])[0]
        expected = doc(m['snapshots'][-1]['docs'][0])
        assert expected == doc(r['snapshots'][-1]['docs'][0])
        rr = execute(rust, [[['apply', 0, r['updates'][0]]]])[0]
        assert doc(rr['snapshots'][-1]['docs'][0]) != expected
        reference_defects += 1
        for command in [rust, moon]:
            received = execute(command, [[['apply', 0, m['updates'][0]]]])[0]
            assert doc(received['snapshots'][-1]['docs'][0]) == expected
        packets, expected = [], []
        for seed in seeds:
            session = Session(['node', 'validation/undo-live.cjs', version] + flags)
            try:
                session.call([])
                for c in history(seed):
                    row = session.call([c])
                    if c[0] in ['undo', 'redo'] and row['snapshots'][-1]['result']:
                        target = c[1]
                        packets.append([['apply', 0, row['updates'][target]]])
                        expected.append(doc(row['snapshots'][-1]['docs'][target]))
                        actions += 1
            finally:
                session.close()
        for command in [rust, moon]:
            received = execute(command, packets)
            for index, (before, row) in enumerate(zip(expected, received)):
                after = doc(row['snapshots'][-1]['docs'][0])
                if before != after:
                    (ROOT / 'validation/fixtures/undo-persistence-failure.json').write_text(json.dumps({'version': version, 'gc': gc, 'commands': packets[index], 'expected': before, 'actual': after}) + '\n')
                    raise AssertionError((version, gc, command, index, before, after))
                transfers += 1
        print(version, 'gc='+str(gc), len(packets), 'successful undo/redo checkpoints passed', flush=True)
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'histories': len(seeds),
              'wire_versions': [1, 2], 'gc_modes': [False, True], 'successful_undo_redo_checkpoints': actions,
              'cross_runtime_reloads': transfers, 'reference_restored_parent_defects': reference_defects,
              'checks': ['structured XML including text attributes', 'nested maps and arrays',
                         'rich text', 'concurrent editing authors', 'save/reload after each successful undo or redo'],
              'status': 'passed with explicit reference restored-parent encoding exception'}
    (ROOT / 'validation/undo-persistence-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
