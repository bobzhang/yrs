#!/usr/bin/env python3
"""Concurrent weak references with mixed Rust/MoonBit authors and shared wire history."""
import json
import random
from compare import ROOT, run
from updates import execute
from weak import equivalent, exceptions


def values(row):
    return {k: v for k, v in row.items() if k not in ['wire', 'events']}


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'weak'])
    run(['moon', 'build', 'validation/weak', '--target', 'js', '--release'])
    count = 32
    checks = deliveries = edits = 0
    initial = [['i', 0, 'abcdefghijklmnop'], *[['ai', i, i] for i in range(12)],
               ['m', 'key', 0], ['ml', 'mref', 'key'],
               ['q', 'tall', None, None], ['q', 'thead', ['i', 1], ['i', 8]],
               ['q', 'aall', None, None]]
    for version in ['v1', 'v2']:
        for gc in [False, True]:
            rust = ['validation/rust/target/release/weak', version] + (['gc'] if gc else [])
            moon = ['node', 'validation/weak.cjs', version] + (['gc'] if gc else [])
            seed = execute(rust, [initial])[0][-1]['wire']
            states = [[seed, seed, seed] for _ in range(count)]
            rngs = [random.Random(31000 + i) for i in range(count)]

            def evaluate(cases, label):
                nonlocal checks
                a = execute(rust, cases)
                b = execute(moon, cases)
                result = []
                for i, (x, y) in enumerate(zip(a, b)):
                    x, y = x[-1], y[-1]
                    if not equivalent(x, y):
                        (ROOT / 'validation/fixtures/weak-network-failure.json').write_text(
                            json.dumps({'version': version, 'gc': gc, 'stage': label,
                                        'commands': cases[i], 'rust': values(x), 'moon': values(y)}, indent=2) + '\n')
                        raise AssertionError((version, gc, label, i, values(x), values(y)))
                    # These all-range quotations have an independent expected view.
                    assert y['links']['tall'][1][0] == y['text'], (label, i, 'text quotation')
                    assert y['links']['aall'][1] == y['array'], (label, i, 'array quotation')
                    checks += 1
                    result.append((x, y))
                return result

            for step in range(64):
                cases, authors = [], []
                for i, rng in enumerate(rngs):
                    author = rng.randrange(3)
                    authors.append(author)
                    kind = rng.choice(['i', 'i', 'd', 'ai', 'ad', 'm', 'md', 'ml', 'f'])
                    n = rng.randrange(100)
                    op = {'i': ['i', n, rng.choice(['!', 'xyz', 'a'])], 'd': ['d', n, 2],
                          'ai': ['ai', n, n], 'ad': ['ad', n, 2], 'm': ['m', 'key', n],
                          'md': ['md', 'key'], 'ml': ['ml', 'mref', 'key'],
                          'f': ['f', n, 2, rng.choice([True, None])]}[kind]
                    cases.append([['client', author + 2], ['load', states[i][author]], op])
                rows = evaluate(cases, f'edit-{step}')
                for i, (a, b) in enumerate(rows):
                    states[i][authors[i]] = (a if (i + step) % 2 else b)['wire']
                edits += count
                if step % 2 == 0:
                    cases, targets = [], []
                    for i, author in enumerate(authors):
                        target = (author + 1) % 3
                        targets.append(target)
                        packet = states[i][author]
                        cases.append([['client', target + 2], ['load', states[i][target]],
                                      ['load', packet], ['load', packet]])
                    rows = evaluate(cases, f'delivery-{step}')
                    for i, (a, b) in enumerate(rows):
                        states[i][targets[i]] = (a if (i + step) % 2 else b)['wire']
                    deliveries += count * 2
            final = [[None, None, None] for _ in range(count)]
            for round in range(4):
                for source in range(3):
                    for target in range(3):
                        if source == target:
                            continue
                        cases = [[['client', target + 2], ['load', state[target]], ['load', state[source]]]
                                 for state in states]
                        rows = evaluate(cases, f'final-{round}-{source}-{target}')
                        for i, (_, b) in enumerate(rows):
                            states[i][target] = b['wire']
                            final[i][target] = values(b)
                        deliveries += count
            for i, row in enumerate(final):
                assert row[0] == row[1] == row[2], (version, gc, i, 'final convergence', row)
            print(f'{version}, gc={gc}: {count} mixed-author histories passed', flush=True)
    assert exceptions['missing_moon_events'] == 0, exceptions
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'histories': count,
              'versions': ['v1', 'v2'], 'gc_modes': [False, True], 'editing_replicas': 3,
              'mixed_runtime_authorship': True, 'local_edits': edits, 'deliveries': deliveries,
              'snapshot_comparisons': checks, 'reference_query_and_observer_exceptions': exceptions,
              'checks': ['identical wire histories', 'causal clocks', 'weak identity boundaries',
                         'bounded and unbounded views', 'duplicate delivery', 'final convergence'],
              'status': 'partial: views and convergence passed with recorded reference query/event exceptions'}
    (ROOT / 'validation/weak-network-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
