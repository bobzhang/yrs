#!/usr/bin/env python3
"""Unicode cursor identity/offset checks; pinned Rust byte-unit defects counted."""
import json, random
from compare import ROOT, run
from updates import execute

def main():
    run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','cursor_offsets'])
    run(['moon','build','validation/cursor_offsets','--target','js','--release'])
    rng=random.Random(29000)
    cases=[]
    for _ in range(128):
        value=''.join(rng.choice(['a','中','é','🦀','👩‍💻','é','\ufeff']) for _ in range(8))
        u=b=0
        for c in value+'Z':
            for before in [False,True]:cases.append([value,u,b,before])
            u+=len(c.encode('utf-16-le'))//2;b+=len(c.encode())
    rust=execute(['validation/rust/target/release/cursor_offsets'],cases)
    moon=execute(['node','validation/cursor_offsets.cjs'],cases)
    mismatch=checks=0
    for request,a,b in zip(cases,rust,moon):
        for x,y in zip(a,b):
            assert (x['text'],x['utf'],x['utf_offset'])==(y['text'],y['utf'],y['utf_offset'])
            assert y['bytes']==y['utf'], ('wire identity',request,y)
            index=y['utf_offset']
            expected=None if index is None else len(y['text'].encode('utf-16-le')[:index*2].decode('utf-16-le').encode())
            assert y['byte_offset']==y['byte_own_offset']==expected, (request,y,expected)
            if (x['bytes'],x['byte_offset'],x['byte_own_offset'])!=(y['bytes'],expected,expected):
                mismatch+=1
                if mismatch==1:
                    (ROOT/'validation/fixtures/upstream-byte-cursor-units.json').write_text(json.dumps({'request':request,'rust':x,'expected':y},indent=2)+'\n')
            checks+=1
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39','documents':128,'cursor_cases':len(cases),'snapshots':checks,'reference_byte_mode_mismatches':mismatch,'status':'UTF16 reference parity and cross-mode identity/offset invariants passed; Rust byte-mode unit defect differs'}
    (ROOT/'validation/cursor-offset-results.json').write_text(json.dumps(result,indent=2)+'\n');print(result)
if __name__=='__main__':main()
