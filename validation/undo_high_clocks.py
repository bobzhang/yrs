#!/usr/bin/env python3
"""Mixed Yjs/MoonBit authors editing at signed/unsigned clock boundaries."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from compare import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['both', 'js', 'native'], default='both')
    args = parser.parse_args()
    targets = ['js', 'native'] if args.target == 'both' else [args.target]
    suffix = '' if args.target == 'both' else '-'+args.target
    path = ROOT/f'validation/undo-high-clock{suffix}-results.json'
    results = []
    # Cross Int32::MAX during editing, then exercise IDs close to UInt32::MAX.
    for target in targets:
        for initial in [(1 << 31)-64, (1 << 32)-1-131072]:
            # Cover both rich text and nested shared-type/XML history generators.
            for start in [0, 48]:
                with tempfile.TemporaryDirectory(prefix='yrs-high-clocks-') as directory:
                    report = Path(directory)/'result.json'
                    command = [sys.executable, 'validation/undo_mixed.py', '--reference', 'yjs',
                               '--target', target, '--seeds', '8', '--seed-start', str(start),
                               '--initial-clock', str(initial), '--report', str(report)]
                    proc = subprocess.run(command, cwd=ROOT)
                    results.append(json.loads(report.read_text()) if report.exists() else
                                   {'status': 'failed', 'command': command, 'exit_code': proc.returncode})
                    result = {'runs': results, 'status': 'passed' if proc.returncode == 0 else 'failed',
                              'replica_state_comparisons': sum(r.get('replica_state_comparisons', 0) for r in results),
                              'undo_redo_actions': sum(r.get('undo_redo_actions', 0) for r in results)}
                    path.write_text(json.dumps(result, indent=2)+'\n')
                    if proc.returncode:
                        raise RuntimeError(f'high-clock run failed: {command}; see {path}')
    print(json.dumps({k: v for k, v in result.items() if k != 'runs'}))


if __name__ == '__main__':
    main()
