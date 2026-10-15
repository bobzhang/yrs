#!/usr/bin/env python3
"""Compare nested and XML event batches, relative paths, deltas and final states."""
import json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def execute(cmd,cases):
 p=subprocess.run(cmd,cwd=ROOT,input=''.join(json.dumps(c)+'\n' for c in cases),text=True,capture_output=True,timeout=240)
 if p.returncode:raise RuntimeError(p.stderr)
 rows=[json.loads(line) for line in p.stdout.splitlines()];assert len(rows)==len(cases)
 for i,row in enumerate(rows):
  if 'error' in row:raise RuntimeError((i,row))
 return rows

def canonical(snapshot):
 snapshot=json.loads(json.dumps(snapshot))
 for batch in snapshot['notifications']:
  events=batch.get('events',[])
  depths=[len(e['path']) for e in events];assert depths==sorted(depths),'events must be shallowest first'
  events.sort(key=lambda e:(len(e['path']),json.dumps(e['path']),e['kind']))
  for event in events+[batch]:
   if 'delta' not in event:continue
   out=[]
   for op in event['delta']:
    key=next(k for k in ['insert','delete','retain'] if k in op)
    if out and key in out[-1] and op.get('attributes',{})==out[-1].get('attributes',{}) and (key!='insert' or type(op[key])==type(out[-1][key]) and isinstance(op[key],(str,list))):out[-1][key]+=op[key]
    else:out.append(op)
   event['delta']=out
 snapshot['notifications'].sort(key=lambda b:(b['doc'],b['scope']))
 return snapshot

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','events'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/events','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
 for seed in range(96):
  rng=random.Random(12000+seed);commands=[]
  for _ in range(150):
   x=rng.randrange(3)
   if rng.randrange(4)==0:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
   else:commands.append(['batch',x,[[rng.choice(['new','remove','edit','shift','xnew','xremove','xedit']),rng.randrange(100)] for _ in range(rng.randrange(1,5))]])
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 checks=events=batches=0
 for version in ['v1','v2']:
  print('checking '+version,flush=True)
  a,b=execute(['validation/rust/target/release/events',version],cases),execute(['node','validation/events.cjs',version],cases)
  for seed,(r,m) in enumerate(zip(a,b)):
   assert len(r['snapshots'])==len(m['snapshots'])==len(cases[seed])
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    checks+=1;batches+=len(x['notifications']);events+=sum(len(n.get('events',[])) for n in x['notifications'])
    x,y=canonical(x),canonical(y)
    if x!=y:
     Path('/tmp/yrs-events-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n');raise AssertionError(f'{version} seed={seed} step={step} op={cases[seed][step]} Rust={x!r} Moon={y!r}')
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'wire_versions':['v1','v2'],'transaction_snapshots':checks,'notification_batches':batches,'deep_events':events,'status':'passed'}
 (ROOT/'validation/event-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
