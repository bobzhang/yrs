#!/usr/bin/env python3
"""Reduced evidence for the pinned sparse retry and per-client blocking behavior."""
import json
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'pending'])
    run(['moon', 'build', 'validation/pending', '--target', 'js', '--release'])
    fixture = json.loads((ROOT / 'validation/fixtures/upstream-pending-watermark-blocking.json').read_text())
    packets = fixture['packets']
    cases = [{'packets': packets[:i]} for i in range(1, len(packets) + 1)]
    rust = execute(['validation/rust/target/release/pending'], cases)
    moon = execute(['node', 'validation/pending.cjs'], cases)
    before_gap_fill = [[1, 0, 3], [1, 30, 33]]
    assert rust[5]['before']['diff']['inserted'] == moon[5]['before']['diff']['inserted'] == before_gap_fill
    assert rust[6]['before']['diff']['inserted'] == [[1, 0, 3], [1, 6, 9], [1, 30, 33]]
    assert moon[6]['before']['diff']['inserted'] == [[1, 0, 3], [1, 6, 12], [1, 18, 21], [1, 30, 36]]
    assert rust[7]['settled']['diff']['inserted'] == moon[6]['before']['diff']['inserted']
    expected = [[1, 0, 3], [1, 6, 12], [1, 18, 21], [1, 30, 36], [1, 42, 45]]
    assert moon[7]['before']['diff']['inserted'] == expected
    raw = [dict(fixture, replay_original=True)]
    a = execute(['validation/rust/target/release/pending'], raw)[0]
    b = execute(['node', 'validation/pending.cjs'], raw)[0]
    assert a == b
    assert a['replayed_original']['diff']['inserted'] == expected
    result = {
        'upstream': 'ac339600c712642e556895426113c3f9c117de39',
        'packets': len(packets),
        'prefixes': [{'delivered': i + 1, 'rust': r['before']['diff']['inserted'],
                      'moon': m['before']['diff']['inserted']}
                     for i, (r, m) in enumerate(zip(rust, moon))],
        'rust_after_merged_pending_retries': rust[-1]['settled']['diff']['inserted'],
        'both_after_original_packet_replay': a['replayed_original']['diff']['inserted'],
        'status': 'reference retry watermark and per-client head blocking reproduced; eager port behavior intentionally differs',
    }
    (ROOT / 'validation/pending-scheduling-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result['status'])


if __name__ == '__main__':
    main()
