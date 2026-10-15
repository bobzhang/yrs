#!/usr/bin/env python3
"""Subdocument data, lifecycle, registry and Rust wire interoperability."""
import json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def execute(command,cases):
 p=subprocess.run(command,cwd=ROOT,input=''.join(json.dumps(c)+'\n' for c in cases),text=True,capture_output=True,timeout=180)
 if p.returncode:raise RuntimeError(p.stderr)
 rows=[json.loads(line) for line in p.stdout.splitlines()]
 assert len(rows)==len(cases)
 assert all('error' not in row for row in rows), rows
 return rows

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','subdocs'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/subdocs','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
 for seed in range(96):
  rng=random.Random(17000+seed); commands=[]
  for step in range(140):
   x=rng.randrange(3); key='file'+str(rng.randrange(4));kind=rng.randrange(8)
   if kind<3:commands.append(['put',x,key,'guid'+str(rng.randrange(8)),rng.choice([True,False]),rng.choice([True,False])])
   elif kind==3:commands.append(['remove',x,key])
   elif kind==4:commands.append(['load',x,key])
   elif kind==5:commands.append(['edit',x,key,rng.choice(['hello','世界','🦀'])])
   elif kind==6:commands.append(['childsync',x,key,(x+rng.randrange(1,3))%3])
   else:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 destroy_cases=[]
 for seed,commands in enumerate(cases[:32]):
  commands=[c.copy() for c in commands]
  for i,c in enumerate(commands):
   if c[0]=='load' and i%2==0:c[0]='destroy'
  destroy_cases.append(commands)
 checks=events=transfers=destroy_checks=0
 for version in ['v1','v2']:
  rust=['validation/rust/target/release/subdocs',version];moon=['node','validation/subdocs.cjs',version]
  a,b=execute(rust,cases),execute(moon,cases)
  for seed,(r,m) in enumerate(zip(a,b)):
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    if x!=y:
     Path('/tmp/yrs-subdocs-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n')
     raise AssertionError((version,seed,step,cases[seed][step],x,y))
    checks+=1;events+=len(x['events'])
  # Feed each emitted wire state independently to both implementations. Remote
  # load flags are intentionally local and child content is not parent content.
  for source in [a,b]:
   packets=[[['apply',0,update]] for row in source for update in row['updates']]
   rs,ms=execute(rust,packets),execute(moon,packets)
   for r,m in zip(rs,ms):
    assert r['snapshots']==m['snapshots'],(r,m)
    transfers+=1
  da,db=execute(rust,destroy_cases),execute(moon,destroy_cases)
  for seed,(r,m) in enumerate(zip(da,db)):
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    # Explicitly audited divergence: Rust keeps the pre-destroy handle in
    # its registry. Compare all actual child handles and lifecycle events;
    # independently require the MoonBit registry to contain exactly live slots.
    for doc in y['docs']:
     assert doc['registered']==sorted(d['guid'] for d in doc['files'].values()),doc
    for doc in x['docs']+y['docs']:doc.pop('registered')
    if x!=y:
     Path('/tmp/yrs-subdocs-destroy-failure.json').write_text(json.dumps(destroy_cases[seed][:step+1])+'\n')
     raise AssertionError(('destroy',version,seed,step,x,y))
    destroy_checks+=1
  print(version+' passed',flush=True)
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'wire_versions':['v1','v2'],'transaction_snapshots':checks,'lifecycle_events':events,'wire_replay_cases':transfers,'destroy_snapshots_without_reference_registry':destroy_checks,'explicit_destroy_registry':'upstream stale registration retained as a separate known divergence','status':'passed'}
 (ROOT/'validation/subdoc-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
