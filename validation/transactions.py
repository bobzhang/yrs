#!/usr/bin/env python3
"""Compare batched mutation lifecycle metadata and replay every emitted update."""
import json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def execute(cmd,cases):
 p=subprocess.run(cmd,cwd=ROOT,text=True,input=''.join(json.dumps(c)+'\n' for c in cases),capture_output=True,timeout=180)
 if p.returncode:raise RuntimeError(p.stderr)
 rows=[json.loads(line) for line in p.stdout.splitlines()];assert len(rows)==len(cases)
 for i,row in enumerate(rows):
  if 'error' in row:Path('/tmp/yrs-transactions-failure.json').write_text(json.dumps(cases[i])+'\n');raise RuntimeError(row)
 return rows

def canonical(snapshot):
 snapshot=json.loads(json.dumps(snapshot));result=[];pending=[]
 for event in snapshot['events']+[{'phase':'sentinel'}]:
  if event['phase'] in ['map','text','array']:
   if 'delta' in event:
    merged=[]
    for op in event['delta']:
     key=next(k for k in ['insert','delete','retain'] if k in op)
     if merged and key in merged[-1] and op.get('attributes',{})==merged[-1].get('attributes',{}) and (key!='insert' or type(op[key])==type(merged[-1][key]) and isinstance(op[key],(str,list))):merged[-1][key]+=op[key]
     else:merged.append(op)
    event['delta']=merged
   pending.append(event)
  else:
   result.extend(sorted(pending,key=lambda e:(e['doc'],e['phase'])));pending=[]
   if event['phase']!='sentinel':result.append(event)
 snapshot['events']=result;return snapshot

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','transactions'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/transactions','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
 for seed in range(96):
  rng=random.Random(10000+seed);commands=[]
  for step in range(120):
   x=rng.randrange(3)
   if rng.randrange(4)==0:c=['sync',x,(x+rng.randrange(1,3))%3]
   else:
    ops=[]
    for _ in range(rng.randrange(0,5)):
     op=rng.choice(['i','d','t','f','m','M'])
     if op in ['i','t']:args=[op,rng.randrange(999),rng.choice(['a','Moon','xyz']),rng.choice([True,False])]
     elif op in ['d','f']:args=[op,rng.randrange(999),rng.randrange(30),rng.choice([True,False])]
     elif op=='m':args=[op,'key'+str(rng.randrange(3)),rng.randrange(30)]
     else:args=[op,'key'+str(rng.randrange(3))]
     ops.append(args)
    c=['batch',x,ops,rng.choice(['user','undo','remote'])]
   commands.append(c)
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 for seed in range(64):
  rng=random.Random(11000+seed);commands=[]
  for _ in range(120):
   x=rng.randrange(3)
   if rng.randrange(4)==0:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
   else:
    ops=[]
    for _ in range(rng.randrange(0,5)):
     if rng.randrange(2):ops.append(['I',rng.randrange(999),[rng.randrange(30) for _ in range(rng.randrange(1,4))]])
     else:ops.append(['D',rng.randrange(999),rng.randrange(30)])
    commands.append(['batch',x,ops,'array'])
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 checks=events=updates=map_events=text_events=array_events=0
 for version in ['v1','v2']:
  print('checking '+version,flush=True)
  a,b=execute(['validation/rust/target/release/transactions',version],cases),execute(['node','validation/transactions.cjs',version],cases)
  for seed,(r,m) in enumerate(zip(a,b)):
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    checks+=1;events+=sum(e['phase'] not in ['map','text','array'] for e in x['events']);text_events+=sum(e['phase']=='text' for e in x['events']);array_events+=sum(e['phase']=='array' for e in x['events']);map_events+=sum(e['phase']=='map' for e in x['events']);updates+=sum(e['phase'] in ['v1','v2'] for e in x['events'])
    x,y=canonical(x),canonical(y)
    if x!=y:
     Path('/tmp/yrs-transactions-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n');raise AssertionError(f'{version} seed={seed} step={step} op={cases[seed][step]} Rust={x!r} Moon={y!r}')
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'wire_versions':['v1','v2'],'transaction_snapshots':checks,'lifecycle_event_comparisons':events,'emitted_updates_replayed':updates,'map_event_comparisons':map_events,'text_event_comparisons':text_events,'array_event_comparisons':array_events,'status':'passed'}
 (ROOT/'validation/transaction-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
