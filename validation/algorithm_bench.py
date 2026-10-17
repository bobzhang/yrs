#!/usr/bin/env python3
"""Whole-process scaling probes for append copying and dependency scheduling.

Includes construction, edits, final value checks and v1/v2 serialization. Each
edit commits separately, with UTF-16 offsets and no observers or replicas.
Array verification performs individual indexed reads to expose accidental copies.
Three fresh processes
per workload/size/runtime; output lengths and encoded sizes must match Rust.
These supplement, rather than replace, the real editing/network traces.
"""
import hashlib
import json
import platform
import re
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from compare import ROOT, run


def main():
    assert platform.system() == 'Darwin', 'RSS measurement uses macOS time -l'
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'algorithm_bench'])
    for target in ['native', 'js']:
        run(['moon', 'build', 'validation/algorithm_bench', '--target', target, '--release'])
    commands = {
        'rust': ['validation/rust/target/release/algorithm_bench'],
        'moonbit_native': ['_build/native/release/build/validation/algorithm_bench/algorithm_bench.exe'],
        'moonbit_js': ['node', '_build/js/release/build/validation/algorithm_bench/algorithm_bench.js'],
    }
    files = sorted(list(ROOT.glob('*.mbt')) + [ROOT/'moon.mod', ROOT/'moon.pkg',
        Path(__file__).resolve(), ROOT/'validation/algorithm_bench/main.mbt',
        ROOT/'validation/algorithm_bench/moon.pkg', ROOT/'validation/rust/src/bin/algorithm_bench.rs',
        ROOT/'validation/rust/Cargo.toml', ROOT/'validation/rust/Cargo.lock'])
    digest = hashlib.sha256()
    for path in files:
        digest.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes() + b'\0')
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'port_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source_sha256': digest.hexdigest(),
              'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain', '--',
                  *[str(p.relative_to(ROOT)) for p in files]], cwd=ROOT, text=True).strip()),
              'method': __doc__.strip(), 'host': platform.platform(),
              'rust_reference': subprocess.check_output(['git', '-C', '.repos/y-crdt', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'moon_toolchain': subprocess.check_output(['moon', 'version', '--all'], cwd=ROOT, text=True).strip(),
              'artifacts': {name: {'command': command, 'sha256': hashlib.sha256((ROOT / command[-1]).read_bytes()).hexdigest()}
                            for name, command in commands.items()}, 'cases': []}
    for kind, sizes in [('text', [20000, 40000, 80000]), ('array', [20000, 40000, 80000]),
                        ('dependencies', [2000, 4000, 8000])]:
        for size in sizes:
            measurements = {name: [] for name in commands}
            expected = None
            for repeat in range(3):
                # Rotate runtime order to reduce systematic warmup/order bias.
                names = list(commands)
                names = names[repeat:] + names[:repeat]
                for name in names:
                    start = time.perf_counter()
                    process = subprocess.run(['/usr/bin/time', '-l', *commands[name], kind, str(size)],
                        cwd=ROOT, text=True, capture_output=True, check=True, timeout=600)
                    seconds = time.perf_counter() - start
                    output = json.loads(process.stdout)
                    if expected is None: expected = output
                    assert output == expected, (kind, size, name, output, expected)
                    measurements[name].append({'elapsed_seconds': round(seconds, 6),
                        'peak_rss_bytes': int(re.search(r'(\d+)\s+maximum resident set size', process.stderr)[1])})
            row = {'workload': kind, 'operations': size, 'output': expected, 'measurements': measurements,
                   'median': {name: {key: statistics.median(sample[key] for sample in samples)
                       for key in ['elapsed_seconds', 'peak_rss_bytes']} for name, samples in measurements.items()}}
            report['cases'].append(row)
            print(kind, size, row['median'], flush=True)
    (ROOT/'validation/algorithm-bench-results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
