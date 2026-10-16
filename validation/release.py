#!/usr/bin/env python3
"""Run reproducible release gates; expected upstream defects remain asserted by each oracle."""
import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Independent local undo can allocate different identities in unchanged Rust.
# The retained diagnostic undo.py and Rust-owned GC crash are not passing gates.
# The undo group instead asserts the minimized upstream crash and tests GC-off
# mixed authors, GC-on port authors, and persistence. Yjs tests both author types.
SUITES = {
    'core': ['compare'],
    'values': ['value_decode', 'value_encode', 'any_stream', 'streams'],
    'contracts': ['contracts', 'handles', 'attribution', 'block_ranges', 'type_refs',
                  'update_codecs', 'codec_updates', 'protocol_codec'],
    'wire': ['updates', 'update_info', 'sparse_wire', 'pending', 'pending_scheduling',
             'v2_clock_boundaries', 'large_ranges', 'legacy'],
    'history': ['history', 'offsets', 'cursor_offsets', 'diffs', 'queries'],
    'lifecycle': ['transactions', 'events', 'presence', 'subdocs', 'embeds', 'prelims'],
    'weak': ['weak', 'weak_network'],
    'undo': ['undo_gc', ['undo_mixed', '--gc', 'off'],
             ['undo_mixed', '--gc', 'on', '--owner', 'moon', '--report',
              'validation/undo-gc-port-results.json'], 'undo_persistence'],
    'undo-yjs': [['undo_mixed', '--reference', 'yjs']],
    'undo-yjs-native': [['undo_mixed', '--reference', 'yjs', '--target', 'native']],
    'undo-high-clocks': ['undo_high_clocks'],
    'undo-observer': ['undo_observer_network'],
    'undo-observer-native': [['undo_observer_network', '--target', 'native']],
}


def source_hash():
    files = sorted(p for p in ROOT.glob('*.mbt') if not p.name.endswith('_test.mbt'))
    files += [ROOT / 'moon.mod', ROOT / 'moon.pkg']
    h = hashlib.sha256()
    for p in files:
        h.update(p.name.encode() + b'\0' + p.read_bytes() + b'\0')
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--suite', choices=list(SUITES))
    selection.add_argument('--verify', action='store_true', help='Verify all saved gates against the current library')
    args = parser.parse_args()
    if args.verify:
        count = 0
        for suite in SUITES:
            saved = json.loads((ROOT / 'validation' / f'release-{suite}-results.json').read_text())
            assert saved['status'] == 'passed', (suite, saved['status'])
            assert saved['source_sha256'] == source_hash(), (suite, 'stale library revision')
            assert len(saved['commands']) == len(SUITES[suite]), (suite, 'incomplete run')
            for item, entry in zip(saved['commands'], SUITES[suite]):
                entry = [entry] if isinstance(entry, str) else entry
                assert item['command'] == ['python3', f'validation/{entry[0]}.py', *entry[1:]]
                assert item['exit_code'] == 0
                count += 1
        print(f'All {len(SUITES)} release suites ({count} oracle commands) passed for {source_hash()}')
        return
    log_dir = ROOT / '_build' / 'release-logs'
    log_dir.mkdir(parents=True, exist_ok=True)
    report_path = ROOT / 'validation' / f'release-{args.suite}-results.json'
    result = {'contract': 'complete CRDT features with documented adaptations',
              'reference': 'ac339600c712642e556895426113c3f9c117de39',
              'source_sha256': source_hash(), 'suite': args.suite, 'commands': [],
              'status': 'running'}
    for entry in SUITES[args.suite]:
        entry = [entry] if isinstance(entry, str) else entry
        command = [sys.executable, f'validation/{entry[0]}.py', *entry[1:]]
        log = log_dir / (args.suite + '-' + str(len(result['commands'])) + '.log')
        print('Running ' + ' '.join(command[1:]), flush=True)
        start = time.monotonic()
        with log.open('w') as output:
            proc = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        result['commands'].append({'command': ['python3', *command[1:]],
                                   'exit_code': proc.returncode,
                                   'seconds': round(time.monotonic() - start, 3)})
        if proc.returncode:
            result['status'] = 'failed'
            report_path.write_text(json.dumps(result, indent=2) + '\n')
            print(log.read_text()[-6000:], file=sys.stderr)
            raise SystemExit(proc.returncode)
        report_path.write_text(json.dumps(result, indent=2) + '\n')
    if result['source_sha256'] != source_hash():
        result['status'] = 'invalidated by a library change during execution'
        report_path.write_text(json.dumps(result, indent=2) + '\n')
        raise SystemExit('Library changed while running; rerun this suite against a stable revision')
    result['status'] = 'passed'
    report_path.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{args.suite}: {len(result["commands"])} checks passed', flush=True)


if __name__ == '__main__':
    main()
