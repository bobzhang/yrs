#!/usr/bin/env python3
"""Replay pinned real editing traces with reconnect/restart and wire checks.

Uses upstream's Unicode codepoint traces, converting offsets to UTF-16 using an
independent Python string model. Time/RSS include parsing, two replicas, packet
encoding, duplicate/reversed delivery, two restarts and serialization. They are
process-level stress measurements, not a microbenchmark of local edits.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import platform
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from compare import ROOT, run

NAMES = ['friendsforever_flat', 'sveltecomponent', 'rustcode', 'seph-blog1', 'automerge-paper']


def prepare(name):
    path = ROOT / '.repos/y-crdt/assets/editing-traces/sequential_traces' / (name + '.json.gz')
    source = json.loads(gzip.decompress(path.read_bytes()))
    text = source['startContent']
    assert not text
    txns = []
    for tx in source['txns']:
        patches = []
        for at, count, value in tx['patches']:
            assert 0 <= at <= len(text) and 0 <= count <= len(text) - at
            patches.append([len(text[:at].encode('utf-16-le')) // 2,
                            len(text[at:at + count].encode('utf-16-le')) // 2, value])
            text = text[:at] + value + text[at + count:]
        txns.append(patches)
    assert text == source['endContent'], name
    return txns, text, hashlib.sha256(path.read_bytes()).hexdigest()


def measured(command, request, directory):
    source = directory / 'input.json'
    source.write_text(json.dumps(request, ensure_ascii=False))
    # macOS time reports RSS in bytes. Retain the method alongside the results.
    start = time.perf_counter()
    result = subprocess.run(['/usr/bin/time', '-l', *command, str(source)], cwd=ROOT,
                            text=True, capture_output=True, timeout=1800)
    elapsed = time.perf_counter() - start
    if result.returncode:
        (ROOT / 'validation/fixtures/trace-failure.json').write_text(json.dumps(request))
        raise RuntimeError(result.stderr[:4000])
    rss = int(re.search(r'(\d+)\s+maximum resident set size', result.stderr)[1])
    return result.stdout, {'elapsed_seconds': round(elapsed, 4), 'peak_rss_bytes': rss}


def provenance():
    paths = sorted(set(
        list(ROOT.glob('*.mbt')) + [ROOT/'moon.mod', ROOT/'moon.pkg',
        ROOT/'validation/traces.py', ROOT/'validation/traces.cjs',
        ROOT/'validation/rust/Cargo.toml', ROOT/'validation/rust/Cargo.lock',
        ROOT/'validation/rust/src/bin/traces.rs'] +
        [p for package in ['traces', 'traces_core', 'traces_native'] for p in (ROOT/'validation'/package).iterdir()
         if p.suffix in ['.mbt', '.c'] or p.name == 'moon.pkg']
    ))
    digest = hashlib.sha256()
    relative = []
    for path in paths:
        name = str(path.relative_to(ROOT))
        relative.append(name)
        digest.update(name.encode() + b'\0' + path.read_bytes() + b'\0')
    return {
        'port_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain', '--', *relative], cwd=ROOT, text=True).strip()),
        'source_sha256': digest.hexdigest(),
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'moon_toolchain': subprocess.check_output(['moon', 'version', '--all'], text=True).strip(),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--traces', nargs='+', choices=NAMES, default=NAMES)
    parser.add_argument('--target', choices=['js', 'native'], default='js')
    parser.add_argument('--gc', choices=['both', 'on', 'off'], default='both')
    args = parser.parse_args()
    source = provenance()
    assert platform.system() == 'Darwin', 'RSS wrapper currently uses macOS /usr/bin/time -l'
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'traces'])
    package = 'validation/traces_native' if args.target == 'native' else 'validation/traces'
    run(['moon', 'build', package, '--target', args.target, '--release'])
    moon_runtime = 'moonbit_' + args.target
    result_path = ROOT / ('validation/trace-native-results.json' if args.target == 'native' else 'validation/trace-results.json')
    prior = json.loads(result_path.read_text()) if result_path.exists() else {}
    records = {}
    for row in prior.get('cases', []):
        row.setdefault('port_revision', prior.get('port_revision', 'unknown'))
        records[(row['trace'], row['gc'])] = row
    with tempfile.TemporaryDirectory(prefix='yrs-traces-') as directory:
        directory = Path(directory)
        # Freeze both executables for the entire matrix. Later rebuilds in this
        # checkout must not silently change the implementation between cases.
        rust_binary = directory / 'rust-traces'
        shutil.copy2(ROOT/'validation/rust/target/release/traces', rust_binary)
        if args.target == 'native':
            artifact = directory / 'moonbit-traces'
            shutil.copy2(ROOT/'_build/native/release/build/validation/traces_native/traces_native.exe', artifact)
            moon_command = [str(artifact)]
        else:
            artifact = directory / 'moonbit.js'
            shutil.copy2(ROOT/'_build/js/release/build/validation/traces/traces.js', artifact)
            runner = directory / 'runner.cjs'
            runner.write_text("const fs=require('node:fs'); const {evaluate}=require('./moonbit.js'); "
                              "console.log(evaluate(fs.readFileSync(process.argv[2],'utf8')));\n")
            moon_command = ['node', str(runner)]
        assert provenance()['source_sha256'] == source['source_sha256'], 'source changed while building benchmark'
        source['artifact_sha256'] = {
            'rust': hashlib.sha256(rust_binary.read_bytes()).hexdigest(),
            moon_runtime: hashlib.sha256(artifact.read_bytes()).hexdigest(),
        }
        commands = {'rust': [str(rust_binary)], moon_runtime: moon_command}
        for name in args.traces:
            txns, expected, digest = prepare(name)
            for gc in ([False, True] if args.gc == 'both' else [args.gc == 'on']):
                rows, measurements = {}, {}
                for runtime, command in commands.items():
                    print(f'{name}, gc={gc}: {runtime}, {len(txns)} transactions', flush=True)
                    output, measurements[runtime] = measured(command, {'gc': gc, 'txns': txns}, directory)
                    rows[runtime] = json.loads(output)
                    assert rows[runtime]['text'] == expected, (name, gc, runtime, 'final content')
                for field in ['clock', 'patches', 'transactions', 'deliveries', 'checkpoints']:
                    assert rows['rust'][field] == rows[moon_runtime][field], (name, gc, field)
                for runtime, row in rows.items():
                    other = 'rust' if runtime == moon_runtime else moon_runtime
                    for version in ['v1', 'v2']:
                        imported, _ = measured(commands[other], {'wire': row['wire_' + version], 'v2': version == 'v2'}, directory)
                        assert imported.removesuffix('\n') == expected, (name, gc, runtime, version, 'wire interchange')
                    measurements[runtime].update({
                        'full_sync_catchups': row['catchups'],
                        'encoded_v1_bytes': len(row['wire_v1']) // 2,
                        'encoded_v2_bytes': len(row['wire_v2']) // 2,
                    })
                row = {key: rows['rust'][key] for key in ['clock', 'patches', 'transactions', 'deliveries', 'checkpoints']}
                row.update({'port_revision': source['port_revision'], 'provenance': source, 'trace': name, 'gc': gc, 'source_sha256': digest,
                            'final_utf8_sha256': hashlib.sha256(expected.encode()).hexdigest(),
                            'measurements': measurements, 'status': 'passed'})
                records[(name, gc)] = row
                result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39',
                          'port_revisions': sorted({r['port_revision'] for r in records.values()}),
                          'latest_run': source,
                          'platform': platform.platform(),
                          'node': subprocess.check_output(['node', '--version'], text=True).strip(),
                          'moon': subprocess.check_output(['moon', 'version'], text=True).strip(),
                          'measurement': 'one run per case; whole-process wall time and macOS peak RSS; includes JSON, replicas, updates, reconnects and restarts',
                          'offsets': 'Unicode traces converted to UTF-16 by independent Python model',
                          'checks': ['recorded final content', 'reversed duplicate update delivery every 128 transactions',
                                     'full-state catchup when pending replay stalls (counted)',
                                     'state-vector equality at reconnects', 'v1 and v2 restart',
                                     'bidirectional Rust/MoonBit v1 and v2 full-state imports'],
                          'cases': list(records.values())}
                result_path.write_text(json.dumps(result, indent=2) + '\n')
                print(json.dumps(row), flush=True)


if __name__ == '__main__':
    main()
