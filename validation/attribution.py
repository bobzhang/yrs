#!/usr/bin/env python3
"""Attributed identity ranges, algebra and exact v1/v2 codecs against pinned Yrs."""
import json,random
from compare import ROOT,run
from updates import execute

def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','attribution'])
 run(['moon','build','validation/attribution','--target','js','--release'])
 cases=[]
 for seed in range(128):
  rng=random.Random(21000+seed);ops=[]
  for _ in range(160):
   op=rng.choice(['insert']*8+['remove','merge','intersect','diff','filter','from','reload1','reload2']);x=rng.randrange(3)
   if op in ['insert','remove','from']:
    r=[rng.randrange(1,6),rng.randrange(100),rng.randrange(1,30) if op=='from' else rng.randrange(30)]
    cmd=[op,x,r]
    if op!='remove':cmd.append([[rng.choice(['author','reviewer','标签🦀']),rng.choice(['alice','bob','界'])] for _ in range(rng.randrange(4))])
   elif op in ['merge','intersect','diff']:cmd=[op,x,rng.randrange(3)]
   elif op=='filter':cmd=[op,x,rng.choice(['author','reviewer','标签🦀'])]
   else:cmd=[op,x]
   ops.append(cmd)
  cases.append(ops)
 cases.append(json.loads((ROOT/'validation/fixtures/attribution-dictionary-aliases.json').read_text()))
 cases.append(json.loads((ROOT/'validation/fixtures/attribution-duplicate-tail.json').read_text()))
 a=execute(['validation/rust/target/release/attribution'],cases);b=execute(['node','validation/attribution.cjs'],cases)
 exact=sum(p['v1']==q['v1'] and p['v2']==q['v2'] for x,y in zip(a,b) for p,q in zip(x,y))
 def semantic(row):return {k:v for k,v in row.items() if k not in ['v1','v2']}
 for i,(x,y) in enumerate(zip(a,b)):
  if [semantic(r) for r in x]!=[semantic(r) for r in y]:
   j=next(j for j,(p,q) in enumerate(zip(x,y)) if semantic(p)!=semantic(q))
   (ROOT/'validation/fixtures/attribution-failure.json').write_text(json.dumps(cases[i][:j+1]))
   print('Mismatch',i,j,'Rust',x[j],'MoonBit',y[j]);raise AssertionError(i)
 transfers=[]
 for rows in a+b:
  for row in rows[::8]:
   transfers.append([['load1',0,row['v1']],['load2',1,row['v2']]])
 ta=execute(['validation/rust/target/release/attribution'],transfers);tb=execute(['node','validation/attribution.cjs'],transfers)
 assert [[semantic(r) for r in rows] for rows in ta]==[[semantic(r) for r in rows] for rows in tb]
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','histories':len(cases),'exact_codec_snapshots':exact,'snapshots':sum(map(len,a)),'cross_runtime_imports':2*len(transfers),'checks':['overlap attribution union','remove','merge','intersection','difference','filter','IdSet conversion','gap queries','v1/v2 cross-runtime decoding and canonical encoding','Unicode dictionary entries'],'status':'passed'}
 (ROOT/'validation/attribution-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
