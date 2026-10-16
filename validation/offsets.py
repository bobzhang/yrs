#!/usr/bin/env python3
"""Mixed UTF-8/UTF-16 replica edits, clocks, rich-text events and wire replay."""
import json,random,subprocess
from pathlib import Path
from subdocs import execute,ROOT

def canonical(row):
 row=json.loads(json.dumps(row))
 def chunks(delta):
  out=[]
  for op in delta:
   if out and set(op)==set(out[-1]) and op.get('attributes')==out[-1].get('attributes'):
    kind=next((k for k in ('insert','retain','delete') if k in op),None)
    if kind and (kind!='insert' or isinstance(op[kind],str) and isinstance(out[-1][kind],str)):
     out[-1][kind]+=op[kind];continue
   out.append(op)
  return out
 for doc in row['docs']:doc['delta']=chunks(doc['delta'])
 for event in row['events']:event['delta']=chunks(event['delta'])
 return row

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','offsets'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/offsets','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
 for seed in range(96):
  rng=random.Random(19000+seed);commands=[]
  for step in range(160):
   x=rng.randrange(3);kind=rng.randrange(6);p=rng.randrange(100)
   if kind<2:commands.append(['i',x,p,rng.choice(['abc','界','🦀','a界🦀','é','e\u0301','👩\u200d💻','\n'])])
   elif kind==2:commands.append(['d',x,p,rng.randrange(100)])
   elif kind in (3,4):commands.append(['f' if kind==3 else 'delta',x,p,rng.randrange(100),rng.randrange(2)])
   else:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 checks=events=transfers=0
 for version in ['v1','v2']:
  rust=['validation/rust/target/release/offsets',version];moon=['node','validation/offsets.cjs',version]
  a,b=execute(rust,cases),execute(moon,cases)
  for seed,(r,m) in enumerate(zip(a,b)):
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    if canonical(x)!=canonical(y):
     Path('/tmp/yrs-offset-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n')
     raise AssertionError((version,seed,step,cases[seed][step],x,y))
    checks+=1;events+=len(x['events'])
  for source in [a,b]:
   packets=[[['apply',0,update]] for row in source for update in row['updates']]
   rs,ms=execute(rust,packets),execute(moon,packets)
   for r,m in zip(rs,ms):
    assert canonical(r['snapshots'][0])==canonical(m['snapshots'][0]),(r,m)
    transfers+=1
  print(version+' passed',flush=True)
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'offset_modes':['bytes','utf16','bytes'],'input_delta_operations':True,'wire_versions':['v1','v2'],'transaction_snapshots':checks,'text_events':events,'wire_replay_cases':transfers,'status':'passed'}
 (ROOT/'validation/offset-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
