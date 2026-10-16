#!/usr/bin/env python3
"""Generic update codec composition replayed by Rust and MoonBit documents."""
import json
from compare import ROOT, run, canonical_snapshot
from updates import execute, states
from embeds import scenarios as embeds
from prelims import scenarios as prelims


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'yrs-reference'])
    run(['moon', 'build', 'validation/bridge', '--target', 'js', '--release'])
    run(['moon', 'build', 'validation/update_codecs', '--target', 'js', '--release'])
    cases = embeds()[:5] + prelims()[:5]
    converted = snapshots = histories = 0
    for source_v2 in [False, True]:
      for gc in [False, True]:
        version = 'v2' if source_v2 else 'v1'
        args = [version] + (['--gc'] if gc else [])
        sources = [execute(['validation/rust/target/release/yrs-reference'] + args, cases),
                   execute(['node', 'validation/run.cjs'] + args, cases)]
        for source in sources:
            traces = [row['history'] for row in source]
            packets = sorted({cmd[2] for trace in traces for cmd in trace})
            outputs = execute(['node', 'validation/update_codecs.cjs'],
                              [dict(update=list(bytes.fromhex(packet)), v2=source_v2) for packet in packets])
            converted += len(packets)
            for target_version in ['v1', 'v2']:
                mapping = {packet: bytes(out[target_version]).hex() for packet, out in zip(packets, outputs)}
                converted_traces = [[[cmd[0], cmd[1], mapping[cmd[2]]] for cmd in trace] for trace in traces]
                target_args = [target_version] + (['--gc'] if gc else [])
                baseline = execute(['validation/rust/target/release/yrs-reference'] + args, traces)
                for command in [['validation/rust/target/release/yrs-reference'], ['node', 'validation/run.cjs']]:
                    actual = execute(command + target_args, converted_traces)
                    for before, after in zip(baseline, actual):
                        assert len(before['snapshots']) == len(after['snapshots'])
                        for p, q in zip(before['snapshots'], after['snapshots']):
                            assert canonical_snapshot(p) == canonical_snapshot(q)
                            snapshots += 1
                        assert [states(v) for v in before['states']] == [states(v) for v in after['states']]
                        histories += 1
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'source_histories': len(cases),
              'generic_decoded_updates': converted, 'complete_history_replays': histories,
              'cross_runtime_snapshots': snapshots, 'wire_versions': [1, 2], 'gc_modes': [False, True],
              'checks': ['Rust and MoonBit produced updates', 'both generic input and output codecs',
                         'interleaved compressed fields across multiple values', 'full rich text, shared embeds and XML documents'],
              'status': 'passed'}
    (ROOT / 'validation/codec-update-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)

if __name__ == '__main__':
    main()
