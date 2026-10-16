#!/usr/bin/env python3
"""Yjs oracle for sparse v1/v2 merges, differences and cross-runtime relays.

Intermediate integration intentionally differs between Yjs and Yrs. Compare wire
identities and delete coverage independently, then complete every receiver with
all original packets before comparing observable document state.
"""
import json
import random
import re
from compare import ROOT, run
from updates import execute, varuint

YJS = ['node', 'validation/yjs/sparse_wire.cjs']
MOON = ['node', 'validation/sparse_wire.cjs']


def vector(pairs):
    return list(varuint(len(pairs)) + b''.join(varuint(c) + varuint(n) for c, n in pairs))


def union(ranges):
    result = []
    for c, a, b in sorted(ranges):
        if result and result[-1][0] == c and result[-1][2] >= a:
            result[-1][2] = max(result[-1][2], b)
        else:
            result.append([c, a, b])
    return result


def inspect(rows, cases, field):
    return execute(YJS, [{'inspect': row[field], 'state': row['vector'], 'version': case['version']}
                         for row, case in zip(rows, cases)])


def main():
    run(['moon', 'build', 'validation/sparse_wire', '--target', 'js', '--release'])
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'pending'])
    fixture = json.loads((ROOT / 'validation/fixtures/yjs-surrogate-suffix-loss.json').read_text())
    request = dict(fixture['case'], apply=True, version=1, gc=False)
    assert execute(YJS, [request])[0]['text'] == fixture['expected']['yjs']
    assert execute(MOON, [request])[0]['text'] == fixture['expected']['moon']
    assert execute(['validation/rust/target/release/pending'], [fixture['case']])[0]['before']['text'] == fixture['expected']['rust']
    requests = [{'produce': seed, 'gc': gc} for seed in range(32) for gc in [False, True]]
    histories = execute(YJS, requests)
    histories_v2 = execute(YJS, [{'convert': True, 'packets': h, 'version': 2} for h in histories])
    cases, completions = [], []
    prefixes = execute(YJS, [{'state_only': True, 'packets': h[:n]}
                             for h in histories for n in [len(h)//4, len(h)//2]])
    baselines = execute(YJS, [{'apply': True, 'version': 1, 'gc': False, 'packets': h} for h in histories])
    for i, history in enumerate(histories):
        rng = random.Random(19000 + i)
        for selection in range(4):
            selected = rng.sample(history, rng.randrange(1, len(history)))
            selected += rng.choices(selected, k=5)
            rng.shuffle(selected)
            remote = [[client, rng.randrange(160)] for client in [1, 2, 3]]
            for version in [1, 2]:
                cases.append({'packets': selected, 'remote': prefixes[2*i+selection] if selection < 2 else vector(remote), 'version': version,
                              'remote_kind': 'observed' if selection < 2 else 'arbitrary', 'history': i})
                completions.append(history if version == 1 else histories_v2[i])
    # Convert using the independent Yjs implementation, including sparse input.
    conversion = execute(YJS, [{'convert': True, 'packets': c['packets'], 'version': 2}
                              for c in cases if c['version'] == 2])
    for c, converted in zip(cases[1::2], conversion):
        c['packets'] = converted
    reference = execute(YJS, cases)
    actual = execute(MOON, cases)
    a, b = inspect(reference, cases, 'merged'), inspect(actual, cases, 'merged')
    assert a == b, 'merged insertion/delete metadata or contiguous state differs'
    da, db = inspect(reference, cases, 'diff'), inspect(actual, cases, 'diff')
    assert da == db, 'difference insertion/delete metadata differs'
    decoded_remotes = execute(YJS, [{'inspect': row['merged'], 'state': case['remote'], 'version': case['version']} for row, case in zip(actual,cases)])
    for merged, diff, remote_info in zip(a, da, decoded_remotes):
        remote = dict(remote_info['state'])
        expected = union([[c, max(start, remote.get(c, 0)), end]
                          for c, start, end in merged['info']['inserted'] if end > remote.get(c, 0)])
        assert diff['info']['inserted'] == expected
        assert diff['info']['deleted'] == merged['info']['deleted']
    # Both producers' merged packets and differences must be accepted by both
    # consumers; missing prefixes are filled using the original history.
    transfers = []
    for i, case in enumerate(cases):
        version = case['version']
        complete = completions[i]
        for producer in [reference, actual]:
            for field in ['merged', 'diff']:
                for gc in [False, True]:
                    transfers.append({'apply': True, 'version': version, 'gc': gc,
                                      'packets': [producer[i][field]] + complete})
    ys = execute(YJS, transfers)
    ms = execute(MOON, transfers)
    views = []
    for row in ys + ms:
        views.append({'inspect': row['wire'], 'state': row['state'], 'version': 2})
    metadata = execute(YJS, views)
    surrogate_losses = 0
    for i, (y, m) in enumerate(zip(ys, ms)):
        source_case = cases[i // 8]
        original = baselines[source_case['history']]
        for key in ['text', 'array', 'map']:
            assert m[key] == original[key], ('port completion lost original content', i, key)
        if y['text'] != m['text']:
            # An arbitrary clock may bisect an inserted surrogate pair. Pinned
            # Yjs retains the lossy suffix even after the original arrives;
            # Rust and MoonBit preserve the original character in this case.
            pattern = ''.join('(?:' + re.escape(c) + '|��)' if ord(c)>0xffff else re.escape(c) for c in m['text'])
            assert source_case['remote_kind'] == 'arbitrary' and re.fullmatch(pattern, y['text']), ('unexpected text difference', i)
            surrogate_losses += 1
        for key in ['array', 'map', 'pending']:
            if y[key] != m[key]:
                (ROOT / 'validation/fixtures/sparse-wire-failure.json').write_text(json.dumps({'case': transfers[i], 'yjs': y, 'moon': m}, indent=2) + '\n')
            assert y[key] == m[key], (i, key, y[key], m[key])
        assert y['pending'] is False
        assert metadata[i] == metadata[i + len(ys)], ('completed metadata', i)
    result = {
        'yjs': '13.6.27', 'histories': len(histories), 'sparse_utility_cases': len(cases),
        'observed_state_vector_cases': sum(c['remote_kind']=='observed' for c in cases),
        'arbitrary_state_vector_cases': sum(c['remote_kind']=='arbitrary' for c in cases),
        'yjs_surrogate_split_completion_differences': surrogate_losses,
        'binary_versions': [1, 2], 'producer_gc_modes': [False, True],
        'receiver_gc_modes': [False, True], 'completed_receiver_comparisons': len(ys),
        'checks': ['three concurrent clients with Unicode text, formatting, arrays and nested maps',
                   'reverse and duplicate delivery with missing histories',
                   'exact insertion identities, deletions and contiguous state from independent Yjs decoder',
                   'independent diff clipping invariant',
                   'both producer merge/diff outputs accepted by both runtimes',
                   'complete-history structures, state and insertion/delete coverage'],
        'scope': 'wire utilities and complete-history convergence; not intermediate scheduler parity',
        'status': 'passed with explicit Yjs surrogate-split exception for arbitrary state vectors',
    }
    (ROOT / 'validation/sparse-wire-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
