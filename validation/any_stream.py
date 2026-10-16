#!/usr/bin/env python3
"""Unframed lib0 values preserve subsequent application bytes across runtimes."""
import json
import random
import struct
from compare import ROOT, run
from updates import execute, varuint


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path', 'validation/rust/Cargo.toml', '--bin', 'value_encode'])
    run(['moon', 'build', 'validation/value_encode', '--target', 'js', '--release'])
    rust = ['validation/rust/target/release/value_encode']
    moon = ['node', 'validation/value_encode.cjs']
    rng = random.Random(821301)
    values = [bytes([n]) for n in [127,126,121,120]]
    values += [bytes([122])+struct.pack('>q',n) for n in [-(1<<63), (1<<63)-1, 0, 1, -1, 1<<53]]
    values += [bytes([123])+struct.pack('>d',n) for n in [0.0,-0.0,1.25,1.1,float('inf'),float('-inf'),float('nan')]]
    for s in ['', 'Moon🌙', 'a\u0000b', '\ufeff']:
        b=s.encode(); values.append(bytes([119])+varuint(len(b))+b)
    values += [bytes([116])+varuint(len(b))+b for b in [b'', bytes(range(256))]]
    for _ in range(512):
        if rng.randrange(2): values.append(bytes([122])+struct.pack('>q',rng.randrange(-(1<<63),1<<63)))
        else: values.append(bytes([123])+struct.pack('>Q',rng.randrange(1<<64)))
    for _ in range(256):
        entries = rng.choices(values[:535], k=rng.randrange(7))
        values.append(bytes([117])+varuint(len(entries))+b''.join(entries))
        keys=[('key'+str(i)).encode() for i in range(len(entries))]
        values.append(bytes([118])+varuint(len(entries))+b''.join(varuint(len(k))+k+v for k,v in zip(keys,entries)))
    suffix = b'\xfa\xfb\xfc'
    cases = [['stream',list(value+suffix)] for value in values]
    r,m = execute(rust,cases),execute(moon,cases)
    for i,(a,b) in enumerate(zip(r,m)):
        assert a['value']==b['value'] and a['tail']==b['tail']==list(suffix), (i,a,b)
    # Every MoonBit generic writer output must decode exactly in Rust, including
    # integer endpoints for which Rust's own writer chooses a rounded float.
    received = execute(rust,[['stream',row['encoded']+list(suffix)] for row in m])
    for i,(a,b) in enumerate(zip(m,received)):
        assert a['value']==b['value'] and b['tail']==list(suffix), (i,a,b)
    truncations = [value[:end] for value in values[:23] for end in range(len(value))]
    rejected = execute(moon,[['stream',list(value)] for value in truncations])
    assert all(row=={'rejected':True} for row in rejected)
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39', 'framed_values':len(cases),
            'port_writer_to_rust_decodes':len(received),'rejected_truncations':len(rejected),
            'checks':['nested arrays and objects','exact numeric variants and bit patterns','custom trailing frame bytes','lossless integer endpoints'],
            'status':'passed; writer byte equality is not required'}
    (ROOT/'validation/any-stream-results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(result)


if __name__=='__main__': main()
