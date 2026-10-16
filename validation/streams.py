#!/usr/bin/env python3
"""Public lib0 streams: exact byte encoding, cross-decoding and truncation."""
import json
import random
from compare import ROOT, run
from updates import execute


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'streams'])
    run(['moon', 'build', 'validation/streams', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/streams']
    moon = ['node', 'validation/streams.cjs']
    rng = random.Random(991828)
    boundary = []
    for kind, bits in [('u8', 8), ('u16', 16), ('u32', 32), ('u32be', 32), ('u64', 64), ('varuint', 64)]:
        boundary += [[kind, str(n)] for n in sorted({0, 1, (1 << bits) - 1, (1 << (bits-1))} | {n for p in range(bits) for n in [(1 << p)-1, 1 << p, (1 << p)+1] if n < (1 << bits)})]
    for kind in ['i64', 'varint', 'signed']:
        boundary += [[kind, str(n)] for n in sorted({0, -(1 << 63)+1, (1 << 63)-1} | {s*n for p in range(63) for n in [(1 << p)-1, 1 << p, (1 << p)+1] for s in [-1, 1]})]
    boundary += [['i64', str(-(1 << 63))]]
    # Quiet NaNs preserve their payload on JS too; avoid signaling NaN arithmetic.
    for kind, nums in [('f32', [0, 1, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00001, 0x3fc00000]), ('f64', [0, 1, 1 << 63, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000001, 0x3ff8000000000000])]:
        boundary += [[kind, str(n)] for n in nums]
    boundary += [['string', s] for s in ['', '\ufeffMoon🌙\x00', '中文', 'a'*128]]
    boundary += [['buf', list(range(256))], ['buf', []]]
    cases = [{'ops': [op]} for op in boundary]
    for _ in range(256):
        ops = [rng.choice(boundary) for _ in range(32)]
        # Exercise random full-width integer payloads independently of boundaries.
        ops += [['varuint', str(rng.getrandbits(64))], ['varint', str(rng.randrange(-(1 << 63)+1, 1 << 63))]]
        cases.append({'ops': ops})
    expected = execute(rust, cases)
    actual = execute(moon, cases)
    for i, (a, b) in enumerate(zip(expected, actual)):
        assert a == b, (i, cases[i], a, b)
    cross = [dict(case, bytes=out['encoded'] + [238]) for case, out in zip(cases, expected)]
    assert execute(rust, cross) == execute(moon, cross)
    truncated = []
    for case, out in zip(cases[:len(boundary)], expected):
        for end in range(len(out['encoded'])):
            truncated.append(dict(case, bytes=out['encoded'][:end]))
    assert execute(rust, truncated) == execute(moon, truncated)
    # Rust's signed writer negates MIN in i64 and emits negative zero. The port
    # uses an unsigned magnitude; both decoders accept its lossless representation.
    minimum = [{'ops': [[kind, str(-(1 << 63))]]} for kind in ['varint', 'signed']]
    reference_min = execute(rust, minimum)
    port_min = execute(moon, minimum)
    for case, ref, port in zip(minimum, reference_min, port_min):
        assert ref['encoded'] == [64] and ref['encoded'] != port['encoded']
        decoded = execute(rust, [dict(case, bytes=port['encoded'])])[0]
        assert decoded['decoded'] == port['decoded']
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'exact_cases': len(cases),
              'encoded_fields': sum(len(c['ops']) for c in cases), 'cross_decode_with_trailing_byte': len(cross),
              'truncated_inputs': len(truncated), 'reference_min_i64_encoder_defects': len(minimum),
              'checks': ['fixed integer endian order', 'full-width varints', 'negative zero', 'float bit patterns',
                         'UTF-8 including BOM and astral characters', 'byte arrays', 'cursor positions'],
              'status': 'passed with explicit reference minimum signed integer encoder exception'}
    (ROOT / 'validation/stream-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)

if __name__ == '__main__':
    main()
