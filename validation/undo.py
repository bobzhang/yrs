#!/usr/bin/env python3
"""Compare selective undo/redo, history capture, nested restoration and remote delivery."""
import json,random,subprocess,os
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
 # Independent undo restoration allocates item IDs in Rust HashSet order. This
 # oracle checks user-visible state, stack depths and undo/redo return values.
 # Exact collection notifications are checked separately by events.py against
 # histories that do not independently allocate restored identities.
 snapshot=json.loads(json.dumps(snapshot));snapshot.pop('notifications',None)
 for doc in snapshot['docs']:
  merged=[]
  for chunk in doc['delta']:
   if merged and chunk['attributes']==merged[-1]['attributes'] and isinstance(chunk['insert'],str) and isinstance(merged[-1]['insert'],str):merged[-1]['insert']+=chunk['insert']
   else:merged.append(chunk)
  doc['delta']=merged
 return snapshot

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','undo'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/undo','--release','--target','js'],cwd=ROOT,check=True)
 concurrent=os.environ.get("YRS_UNDO_CONCURRENT")=="1"
 cases=[]
 for seed in range(96):
  rng=random.Random(13000+seed);commands=[]
  for _ in range(160):
   x=rng.randrange(3) if concurrent else 0;kind=rng.randrange(12)
   if kind==0:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
   elif kind<4:commands.append(['undo' if kind<3 else 'redo',x])
   elif kind==4:commands.append(['reset',x])
   elif kind==5:commands.append(['tick',x,rng.choice([100,600])])
   else:
    choices=['i','d','f','m','remove'] if seed<48 else ['new','remove','edit','shift','xnew','xremove','xedit']
    commands.append(['batch',x,[[rng.choice(choices),rng.randrange(100)] for _ in range(rng.randrange(1,4))]])
  commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 checks=events=batches=transfers=0; alternative_runs=[]
 for version in ['v1','v2']:
  print('checking '+version,flush=True)
  a,b=execute(['validation/rust/target/release/undo',version],cases),execute(['node','validation/undo.cjs',version],cases)
  for seed,(r,m) in enumerate(zip(a,b)):
   assert len(r['snapshots'])==len(m['snapshots'])==len(cases[seed])
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    checks+=1;batches+=len(x['notifications']);events+=sum(len(n.get('events',[])) for n in x['notifications'])
    x,y=canonical(x),canonical(y)
    if x!=y:
     # Undo restores a HashSet of items. The pinned reference can emit different
     # histories across fresh processes; require an entire matching prefix,
     # never accept a mismatch merely because it involves an undo operation.
     prefix=cases[seed][:step+1]
     expected=[canonical(v) for v in m['snapshots'][:step+1]]
     matched=False
     for attempt in range(64):
      replay=execute(['validation/rust/target/release/undo',version],[prefix])[0]
      if [canonical(v) for v in replay['snapshots']]==expected:
       matched=True;alternative_runs.append({'version':version,'scenario':seed,'step':step,'attempt':attempt+1});break
     if not matched:
      Path('/tmp/yrs-undo-failure.json').write_text(json.dumps(prefix)+'\n');raise AssertionError(f'{version} seed={seed} step={step} op={cases[seed][step]} Rust={x!r} Moon={y!r}')
  for source,target in [(a,['node','validation/undo.cjs',version]),(b,['validation/rust/target/release/undo',version])]:
   packets=[];expected=[]
   for row in source:
    for index,payload in enumerate(row['updates']):
     packets.append([['apply',0,payload]]);expected.append(row['snapshots'][-1]['docs'][index])
   replicas=execute(target,packets)
   for expected,replica in zip(expected,replicas):
    actual=replica['snapshots'][-1]['docs'][0]
    def doc(v):return canonical({'docs':[v],'notifications':[]})['docs'][0]
    assert doc(expected)==doc(actual),(expected,actual)
    transfers+=1
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'concurrent_undo_authors':concurrent,'cross_runtime_transfers':transfers,'wire_versions':['v1','v2'],'transaction_snapshots':checks,'observer_events_compared':False,'alternate_reference_runs':alternative_runs,'status':'passed_observed_reference_outcomes' if alternative_runs else 'passed'}
 (ROOT/('validation/undo-concurrent-results.json' if concurrent else 'validation/undo-results.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
