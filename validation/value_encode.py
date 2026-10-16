#!/usr/bin/env python3
"""Typed application serialization compared with Rust serde::to_any."""
import json
import random
import struct
from compare import ROOT, run
from updates import execute, varuint


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'value_encode'])
    run(['moon', 'build', 'validation/value_encode', '--target', 'js', '--release'])
    rng = random.Random(710993)
    signed = [-(1 << 63), (1 << 63)-1, 0, -1, 1] + [rng.randrange(-(1 << 63), 1 << 63) for _ in range(300)]
    unsigned = [0, 1, (1 << 63)-1, 1 << 63, (1 << 64)-1] + [rng.randrange(1 << 64) for _ in range(300)]
    f64 = [0, 1 << 63, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000]
    f64 += [struct.unpack('>Q', struct.pack('>d', float(n)))[0] for n in signed[:50]]
    f64 += [rng.randrange(1 << 64) for _ in range(300)]
    f32 = [0, 1 << 31, 0x7f800000, 0xff800000, 0x7fc00000] + [rng.randrange(1 << 32) for _ in range(300)]
    cases = [['i64', str(n)] for n in signed] + [['u64', str(n)] for n in unsigned]
    cases += [['f64', str(n)] for n in f64] + [['f32', n] for n in f32]
    cases += [['i32', n] for n in [-(1 << 31), -1, 0, (1 << 31)-1]]
    cases += [['u32', n] for n in [0, (1 << 32)-1]]
    cases += [['unit', None], ['optional', None], ['bool', False], ['bool', True]]
    cases += [['string', s] for s in ['', 'Moon🌙', 'a\u0000b', '\ufeff']]
    cases += [['bytes', b] for b in [[], [0, 255, 128], list(range(256))]]
    for i, n in enumerate(unsigned):
        cases += [['optional', str(n)], ['array', ['0', str(n)]], ['map', {'n': str(n)}], ['tuple', ['id', str(n)]],
                  ['record', {'id': str(n), 'title': 'Moon🌙', 'flags': [True, False], 'extra': str(signed[i]) if i % 2 else None}]]
    wire = [bytes([122])+struct.pack('>q', n) for n in signed]
    wire += [bytes([123])+struct.pack('>Q', n) for n in f64]
    wire += [bytes([127]), bytes([126]), bytes([120]), bytes([121]), bytes([116, 2, 0, 255])]
    wire += [bytes([117])+varuint(len(values))+b''.join(values) for values in [[], wire[:15], wire[-10:]]]
    # Serde recursively maps Undefined to Null, including object fields.
    wire += [bytes([118, 1, 1])+b'x'+bytes([117, 2, 127, 126])]
    cases += [['any', list(packet)] for packet in wire]
    rust = execute(['validation/rust/target/release/value_encode'], cases)
    moon = execute(['node', 'validation/value_encode.cjs'], cases)
    for index, (a, b) in enumerate(zip(rust, moon)):
        assert a == b, (index, cases[index], a, b)
    result = {'upstream': 'ac339600c712642e556895426113c3f9c117de39', 'conversions': len(cases),
              'rejected_unrepresentable_values': sum(not row['ok'] for row in rust),
              'checks': ['exact integer and floating-point variants', 'unsigned overflow including nested values',
                         'signed zero, infinities and NaN bit patterns', 'typed arrays, maps, tuples, optional values and custom records',
                         'byte buffers', 'recursive Any serde normalization'], 'status': 'passed'}
    (ROOT / 'validation/value-encode-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
