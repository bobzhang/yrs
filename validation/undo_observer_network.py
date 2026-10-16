#!/usr/bin/env python3
"""Three mixed-runtime authors synchronize exclusively through observer updates.

Full-state encodings are used only for final independent reload checks, never to
repair network synchronization. Every update generated while importing a remote
packet is eligible for forwarding too. Links can deliver batches out of order.
"""
import argparse
import json
import random
import subprocess
from pathlib import Path
from compare import ROOT
from undo_mixed import Session, history, state, causal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['js', 'native'], default='js')
    parser.add_argument('--seeds', type=int, default=32)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    assert 0 < args.seeds <= 96
    assert json.loads((ROOT/'validation/yjs/node_modules/yjs/package.json').read_text())['version'] == '13.6.27'
    report = args.report or ROOT/f'validation/undo-observer-network-{args.target}-results.json'
    package = 'validation/undo_native' if args.target == 'native' else 'validation/undo'
    subprocess.run(['moon', 'build', package, '--target', args.target, '--release'], cwd=ROOT, check=True)
    result = {'reference': 'yjs', 'yjs_version': '13.6.27', 'moonbit_target': args.target,
              'network_transport': 'update observer packets only', 'histories': 0,
              'wire_versions': ['v1', 'v2'], 'gc_modes': [False, True],
              'local_commands': 0, 'emitted_packets': 0, 'delivered_packets': 0,
              'duplicate_checks': 0, 'converged_replicas': 0, 'cross_runtime_reloads': 0,
              'status': 'running'}
    for gc in [False, True]:
        for version in ['v1', 'v2']:
            for index in range(args.seeds):
                seed = index if index < args.seeds//2 else 48+index-args.seeds//2
                owners = [(i+seed) % 2 for i in range(3)]
                flags = [version]+(['--gc'] if gc else [])
                commands = [['node', 'validation/yjs/undo-live.cjs']+flags,
                            (['_build/native/release/build/validation/undo_native/undo_native.exe', '--live']
                             if args.target == 'native' else ['node', 'validation/undo-live.cjs'])+flags]
                sessions = [Session(c) for c in commands]
                last = [s.call([]) for s in sessions]
                logs = [[], [], []]
                positions = [[0]*3 for _ in range(3)]
                rng = random.Random(901000+seed)
                step = -1
                try:
                    def call(replica, command):
                        owner = owners[replica]
                        row = sessions[owner].call([command])
                        last[owner] = row
                        for source, packet in row['emitted']:
                            assert source == replica, (replica, source)
                            logs[source].append(packet)
                            result['emitted_packets'] += 1
                        return row

                    def sync(source, target):
                        begin, end = positions[source][target], len(logs[source])
                        positions[source][target] = end
                        packets = logs[source][begin:end]
                        rng.shuffle(packets)
                        for packet in packets:
                            row = call(target, ['apply', target, packet])
                            result['delivered_packets'] += 1
                            if result['delivered_packets'] % 13 == 0:
                                visible, metadata = state(row)[target], causal(row)[target]
                                duplicate = call(target, ['apply', target, packet])
                                assert state(duplicate)[target] == visible and causal(duplicate)[target] == metadata
                                assert not duplicate['emitted'], 'duplicate delivery emitted another update'
                                result['duplicate_checks'] += 1
                        return bool(packets)

                    for step, command in enumerate(history(seed)):
                        if command[0] == 'sync':
                            sync(command[1], command[2])
                        else:
                            call(command[1], command)
                            result['local_commands'] += 1
                    # Finite generated updates must drain without a full-state fallback.
                    for _ in range(16):
                        progressed = False
                        for x in range(3):
                            for y in range(3):
                                if x != y:
                                    progressed = sync(x, y) or progressed
                        if not progressed:
                            break
                    else:
                        raise AssertionError('observer update network did not quiesce')
                    visible = [state(last[owners[i]])[i] for i in range(3)]
                    metadata = [causal(last[owners[i]])[i] for i in range(3)]
                    assert visible[0] == visible[1] == visible[2], ('document convergence', visible)
                    assert metadata[0] == metadata[1] == metadata[2], ('causal convergence', metadata)
                    result['converged_replicas'] += 3
                    # Test each producer's persistence, independently of network transport.
                    for i in range(3):
                        saved = last[owners[i]]['updates'][i]
                        for command in commands:
                            restored = Session(command)
                            try:
                                row = restored.call([['apply', 0, saved]])
                                assert state(row)[0] == visible[i], ('reload content', i)
                                assert causal(row)[0] == metadata[i], ('reload causal history', i)
                            finally:
                                restored.close()
                            result['cross_runtime_reloads'] += 1
                    result['histories'] += 1
                except Exception as error:
                    failure = {'gc': gc, 'version': version, 'seed': seed, 'step': step,
                               'owners': owners, 'error': str(error), 'calls': [s.calls for s in sessions]}
                    Path('/tmp/yrs-undo-observer-network-failure.json').write_text(json.dumps(failure)+'\n')
                    report.write_text(json.dumps({**result, 'status': 'failed', 'failure': {k:v for k,v in failure.items() if k != 'calls'}}, indent=2)+'\n')
                    raise
                finally:
                    for session in sessions:
                        session.close()
            print(f'{version} gc={gc}: {args.seeds} observer-only networks passed', flush=True)
    result['status'] = 'passed'
    report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
