#!/usr/bin/env python3
"""Lossless typed lib0 conversion versus Rust's public serde adapter."""
import json
import math
import random
import struct
from compare import ROOT, run
from updates import execute, varuint


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'value_decode'])
    run(['moon', 'build', 'validation/value_decode', '--target', 'js', '--release'])
    rng = random.Random(987123)
    integers = [0, -1, 1, -(1 << 63), (1 << 63)-1]
    for power in [31, 32, 53, 62]:
        integers += [sign*((1 << power)+offset) for sign in [-1, 1] for offset in [-1, 0, 1]]
    integers += [rng.randrange(-(1 << 63), 1 << 63) for _ in range(512)]
    floating = [float(x) for x in integers[:29]] + [0.0, -0.0, 1.5, -1.5, float('inf'), float('-inf'), float('nan')]
    for value in [-(1 << 63), 1 << 63, -(1 << 31), 1 << 32]:
        floating += [math.nextafter(float(value), float('-inf')), math.nextafter(float(value), float('inf'))]
    floating += [rng.uniform(-1e20, 1e20) for _ in range(128)]
    values = [bytes([122])+struct.pack('>q', n) for n in integers]
    values += [bytes([123])+struct.pack('>d', n) for n in floating]
    values += [bytes([127]), bytes([126]), bytes([120]), bytes([121]), bytes([116,2,0,255])]
    values += [bytes([119])+varuint(len(s.encode()))+s.encode() for s in ['', 'Moon🌙', '9223372036854775807']]
    values += [bytes([117])+varuint(len(items))+b''.join(items) for items in [[],values[:4],values[-3:],values[:32]]]
    kinds = ['i64','i32','u32','u64','f64','f32','bool','string','optional','array']
    cases = [[kind, list(value)] for value in values for kind in kinds]
    rust = execute(['validation/rust/target/release/value_decode'], cases)
    moon = execute(['node', 'validation/value_decode.cjs'], cases)
    for i, (a,b) in enumerate(zip(rust,moon)):
        assert a == b, (i,cases[i],a,b)
    result = {'upstream':'ac339600c712642e556895426113c3f9c117de39',
              'values':len(values),'conversions':len(cases),
              'checks':['integer limits and lossless numeric conversion','floating-point bit patterns including NaN infinity and signed zero',
                        'null and undefined options','arrays','type rejection','Rust saturating float-to-integer endpoint'],
              'status':'passed'}
    (ROOT/'validation/value-decode-results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(result)


if __name__ == '__main__':
    main()
