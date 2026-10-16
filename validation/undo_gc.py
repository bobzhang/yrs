#!/usr/bin/env python3
"""Isolate the reference GC/undo crash without any MoonBit-generated input."""
import json
import subprocess
from undo import ROOT, execute, canonical


def main():
    subprocess.run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
                    'validation/rust/Cargo.toml', '--bin', 'undo'], cwd=ROOT, check=True)
    subprocess.run(['moon', 'build', 'validation/undo', '--release', '--target', 'js'], cwd=ROOT, check=True)
    fixture = 'validation/fixtures/upstream-undo-gc-parent.json'
    commands = json.loads((ROOT / fixture).read_text())
    crashes = checkpoints = reloads = 0
    for version in ['v1', 'v2']:
        rust = ['validation/rust/target/release/undo', version]
        moon = ['node', 'validation/undo.cjs', version]
        reference = execute(rust, [commands])[0]
        for _ in range(10):
            p = subprocess.run(rust + ['--gc'], cwd=ROOT, input=json.dumps(commands) + '\n',
                               text=True, capture_output=True, timeout=30)
            assert p.returncode != 0 and 'Could not get parent branch info for item' in p.stderr, p.stderr
            crashes += 1
        for gc in [False, True]:
            flags = ['--gc'] if gc else []
            port = execute(moon + flags, [commands])[0]
            assert len(port['snapshots']) == len(reference['snapshots']) == len(commands)
            for a, b in zip(reference['snapshots'], port['snapshots']):
                assert canonical(a) == canonical(b)
                checkpoints += 1
            # Both runtimes, including GC-enabled Rust, accept the port's full
            # states. The crash requires Rust's retained local undo/GC state.
            for receiver in [rust + flags, moon + flags]:
                rows = execute(receiver, [[['apply', 0, packet]] for packet in port['updates']])
                for before, row in zip(port['snapshots'][-1]['docs'], rows):
                    assert canonical({'docs': [before]}) == canonical({'docs': [row['snapshots'][-1]['docs'][0]]})
                    reloads += 1
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'fixture': fixture,
              'operations': len(commands), 'reference_only_gc_crashes': crashes,
              'port_snapshots_matching_gc_disabled_reference': checkpoints,
              'port_state_cross_runtime_reloads': reloads, 'wire_versions': [1, 2],
              'gc_modes': [False, True], 'status': 'reference crash isolated; port regression passed',
              'scope': 'Seven-operation deterministic witness, not a waiver for other mixed-author failures.'}
    (ROOT / 'validation/undo-gc-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
