#!/usr/bin/env python3
"""Pending update lifecycle, integrated-only differences and scoped collection.

Full encodings must preserve the union of incoming insertion identities. Check
that invariant independently of apply/prune, because pinned Yrs's sparse update
merger can shift clocks while encoding Skip blocks.
"""
import json
import random
from compare import ROOT, run
from updates import execute


def union(ranges):
    result = []
    for client, start, end in sorted((int(c), s, e) for c, s, e in ranges):
        if result and result[-1][0] == client and result[-1][2] >= start:
            result[-1][2] = max(result[-1][2], end)
        else:
            result.append([client, start, end])
    return result


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'pending', '--bin', 'update_info'])
    run(['moon', 'build', 'validation/pending', '--target', 'js', '--release'])
    run(['moon', 'build', 'validation/update_info', '--target', 'js', '--release'])
    # GC/deleted structs are deletions in their own right, even when the sender
    # omitted the redundant delete-set entry. Their deletion must be relayed.
    collected_cases = [{'packets': [list(bytes.fromhex(packet))]} for packet in [
        '01010700000100', '01010700010104746578740100']]
    reference_collected = execute(['validation/rust/target/release/pending'], collected_cases)
    port_collected = execute(['node', 'validation/pending.cjs'], collected_cases)
    assert reference_collected == port_collected, 'GC/deleted block deletion-set propagation'
    for row in port_collected:
        assert row['before']['full']['deleted'] == [[7, 0, 1]]
    histories = execute(['validation/rust/target/release/pending'],
                        [{'produce': seed} for seed in range(64)])
    packets = {bytes(packet).hex() for history in histories for packet in history}
    queries = [[packet, []] for packet in sorted(packets)]
    reference_info = execute(['validation/rust/target/release/update_info'], queries)
    port_info = execute(['node', 'validation/update_info.cjs'], queries)
    assert reference_info == port_info, 'source packet metadata'
    packet_info = dict(zip(sorted(packets), reference_info))
    cases = []
    for seed, history in enumerate(histories):
        rng = random.Random(23000 + seed)
        for _ in range(8):
            cases.append({'packets': rng.sample(history, rng.randrange(1, len(history))), 'complete': history})
        for start, length in [(0, 0), (0, 1), (1, 2), (2, 20), (0, 96)]:
            cases.append({'packets': history, 'gc': [[1, start, length]]})
    a = execute(['validation/rust/target/release/pending'], cases)
    b = execute(['node', 'validation/pending.cjs'], cases)
    # Separate item integration from pending-store scheduling. Retry each
    # original packet, dropping unready buffered blocks before the next one,
    # until the integrated wire stops changing. The unchanged Yrs integrator
    # and the port must agree exactly on this independent schedule.
    replay_cases = [dict(case, replay_original=True) for case in cases if 'gc' not in case]
    raw_reference = execute(['validation/rust/target/release/pending'], replay_cases)
    raw_port = execute(['node', 'validation/pending.cjs'], replay_cases)
    assert raw_reference == raw_port, 'original-packet fixed-point integration'
    # An eager receiver must already contain exactly the causal fixed point,
    # not merely converge after somebody resends the missing dependency later.
    # Compare its integrated-only state with unchanged Rust replaying originals
    # to exhaustion, bypassing Rust's lossy pending-update merge.
    eager_cases = [row for case, row in zip(cases, b) if 'gc' not in case]
    for i, (eager, replay) in enumerate(zip(eager_cases, raw_reference)):
        assert eager['after'] == replay['replayed_original'], ('eager causal fixed point', i, eager['after'], replay['replayed_original'])
    layouts = reference_encoding_errors = reference_roundtrip_errors = redundant_pending_deletes = 0
    reference_retry_stalls = 0
    sparse_integration_differences = 0
    stale_pending_flags = 0
    for i, (x, y) in enumerate(zip(a, b)):
        x.pop('retry_rounds')
        assert y.pop('retry_rounds') == 0
        source_ids = union([r for packet in cases[i]['packets']
                            for r in packet_info[bytes(packet).hex()]['all']])
        partition = union(y['after']['diff']['inserted'] +
                          (y['pending']['inserted'] if y['pending'] else []))
        assert partition == source_ids, ('pruned partition', i, partition, source_ids)
        assert y['before'] == y['restored'], ('port roundtrip', i, y)
        reference_roundtrip_errors += x['before']['full'] != x['restored']['full']
        for phase in ['before', 'after', 'restored', 'settled']:
            layouts += x[phase]['wire'] != y[phase]['wire']
            x[phase].pop('wire')
            y[phase].pop('wire')
            expected = source_ids if phase != 'after' else y['after']['diff']['inserted']
            assert y[phase]['full']['inserted'] == expected, ('port full identities', i, phase)
            if x[phase]['full']['inserted'] != expected:
                reference_encoding_errors += 1
                if reference_encoding_errors == 1:
                    (ROOT / 'validation/fixtures/upstream-pending-skip-encoding.json').write_text(
                        json.dumps({'case': cases[i], 'phase': phase,
                                    'expected': expected, 'actual': x[phase]['full']['inserted']}, indent=2) + '\n')
            # These identities are independently checked above. Do not count a
            # reference encoding failure as a successful full-state comparison.
            x[phase]['full'].pop('inserted')
            y[phase]['full'].pop('inserted')
        if x['pending'] is not None and y['pending'] is not None:
            xp, yp = x['pending']['deleted'], y['pending']['deleted']
            if xp != yp:
                # Rust's apply_delete computes Skip length from the original
                # block start even when a range begins inside it. Only tolerate
                # redundant already-applied deletions, never a lost delete.
                integrated = y['after']['diff']['deleted']
                assert union(xp + integrated) == union(yp + integrated), ('pending delete coverage', i)
                assert union(xp + yp) == xp, ('reference missing pending deletes', i)
                redundant_pending_deletes += 1
            x['pending'].pop('deleted')
            y['pending'].pop('deleted')
        layouts += x['completed']['wire'] != y['completed']['wire']
        x['completed'].pop('wire')
        y['completed'].pop('wire')
        assert y['completed']['missing'] is False, ('port completed pending state', i)
        stale_pending_flags += x['completed']['missing']
        x['completed']['missing'] = False
        assert x['completed'] == y['completed'], ('completed history', i, x['completed'], y['completed'])
        if x != y and x['settled'] == y['settled'] and 'gc' not in cases[i]:
            reference_retry_stalls += 1
            if reference_retry_stalls == 1:
                (ROOT / 'validation/fixtures/upstream-pending-retry-stall.json').write_text(
                    json.dumps(cases[i], indent=2) + '\n')
            continue
        assert x['completed'] == y['completed'], ('completed history', i, x['completed'], y['completed'])
        if x != y:
            assert 'gc' not in cases[i], ('scoped GC mismatch', i, x, y)
            sparse_integration_differences += 1
            if sparse_integration_differences == 1:
                (ROOT / 'validation/fixtures/pending-sparse-integration-difference.json').write_text(
                    json.dumps(cases[i], indent=2) + '\n')
    result = {
        'upstream': 'ac339600c712642e556895426113c3f9c117de39',
        'histories': 64, 'pending_cases': 512, 'scoped_gc_cases': 320,
        'snapshots': len(cases) * 5, 'source_packets_checked': len(packets),
        'original_packet_fixed_point_cases': len(replay_cases),
        'eager_fixed_point_comparisons': len(eager_cases),
        'maximum_original_packet_passes': max(case['rounds'] for case in raw_reference),
        'different_block_encodings': layouts,
        'reference_full_encoding_identity_failures': reference_encoding_errors,
        'reference_pending_roundtrip_failures': reference_roundtrip_errors,
        'reference_redundant_pending_deletions': redundant_pending_deletes,
        'reference_pending_retry_stalls': reference_retry_stalls,
        'sparse_integration_differences': sparse_integration_differences,
        'reference_stale_pending_flags_after_complete_delivery': stale_pending_flags,
        'checks': ['eager integrated state equals independent Rust original-packet fixed point in all sparse cases',
                   'exact original-packet fixed-point integration including wire and pass count',
                   'pending block and deletion pruning', 'integrated-only difference',
                   'exact port prune/reapply roundtrip', 'state-vector bounds', 'root text views',
                   'GC retained content via historical reconstruction',
                   'full insertion identities equal union of independently decoded source packets'],
        'status': 'passed CRDT contract: eager causal fixed point, complete histories and scoped GC; exact Rust pending lifecycle intentionally differs',
    }
    (ROOT / 'validation/pending-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
