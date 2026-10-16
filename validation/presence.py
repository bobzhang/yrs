#!/usr/bin/env python3
"""Compare presence metadata, observer events and sync handshakes with pinned Yrs."""
import copy, json, random, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def run(cmd, cases):
 p=subprocess.run(cmd,cwd=ROOT,input=''.join(json.dumps(c)+'\n' for c in cases),text=True,capture_output=True,timeout=120)
 if p.returncode: raise RuntimeError(p.stderr)
 result=[json.loads(line) for line in p.stdout.splitlines()]
 assert len(result)==len(cases)
 for i,r in enumerate(result):
  assert 'error' not in r,(i,r)
 return result

def uint(n):
 out=[]
 while n>127:out.append((n&127)|128);n>>=7
 return bytes(out+[n])

def update(client,clock,value):
 raw=value.encode()
 return (b'\x01'+uint(client)+uint(clock)+uint(len(raw))+raw).hex()

# Pinned Rust omits on_change and labels absent->present as updated when a
# tombstone is retained. Normalize exactly that independently observed state
# transition; document state, clocks, origins and all other events remain exact.
def restored_presence(reference, previous):
 result=copy.deepcopy(reference)
 restored={}
 for owner,(old,new) in enumerate(zip(previous['docs'],reference['docs'])):
  before={row[0]:row for row in old['states']}
  restored[owner]={row[0] for row in new['states'] if row[0] in before and before[row[0]][3] is None and row[3] is not None}
 events=[];corrections=0
 for event in result['events']:
  owner,kind,added,updated,removed=event
  ids=restored[owner].intersection(updated) if kind=='update' else set()
  if ids:
   corrections+=len(ids)
   event[2]=sorted(added+list(ids));event[3]=[v for v in updated if v not in ids]
   if events and events[-1][0:2]==[owner,'change']:
    events[-1][2]=sorted(events[-1][2]+list(ids))
   else:events.append([owner,'change',sorted(ids),[],[]])
  events.append(event)
 result['events']=events
 return result,corrections

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','presence'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/presence','--release','--target','js'],cwd=ROOT,check=True)
 witness=[['set',0,'{"name":"A"}'],['send',0,1],['remove',1,1],['set',0,'{"name":"A"}'],['set',0,'{"name":"A"}'],['send',0,1]]
 cases=[witness]
 for seed in range(128):
  rng=random.Random(8000+seed);commands=[]
  for step in range(240):
   op=rng.choice(['set','set','remove','send','queue','deliver','apply','insert','connect','query']);x=rng.randrange(3)
   if op=='set':c=[op,x,rng.choice(['{}','{"name":"Moon"}','{"cursor":3}','null','not json'])]
   elif op=='remove':c=[op,x,rng.randrange(1,5)]
   elif op in ('send','queue','connect','query'):c=[op,x,(x+rng.randrange(1,3))%3]
   elif op=='deliver':c=[op,rng.randrange(999)]
   elif op=='insert':c=[op,x,rng.choice(['a','Moon','🌍'])]
   else:c=[op,x,update(rng.randrange(1,5),rng.randrange(0,30),rng.choice(['null','{}','{"cursor":0}']))]
   commands.append(c)
  commands += [['connect',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 rust=['validation/rust/target/release/presence'];moon=['node','validation/presence.cjs']
 a,b=run(rust,cases),run(moon,cases)
 assert a[0]['snapshots'][-1]['events']==[[1,'update',[],[1],[]]]
 assert b[0]['snapshots'][-1]['events']==[[1,'change',[1],[],[]],[1,'update',[1],[],[]]]
 comparisons=0;corrections=0
 for seed,(r,m) in enumerate(zip(a,b)):
  for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
   comparisons+=1
   previous=r['snapshots'][step-1] if step else {'docs':[{'states':[]} for _ in range(3)]}
   expected,count=restored_presence(x,previous);corrections+=count
   if expected!=y:
    Path('/tmp/yrs-presence-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n')
    raise AssertionError(f'seed={seed} step={step} op={cases[seed][step]} Rust={x} Moon={y}')
 transfers=0
 for source in [a,b]:
  cases=[[['apply',i,u] for i,u in enumerate(row['updates'])] for row in source]
  ra,mb=run(rust,cases),run(moon,cases)
  for x,y in zip(ra,mb):
   assert x['snapshots']==y['snapshots'];transfers+=3
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(a),'operation_snapshots':comparisons,'cross_runtime_awareness_transfers':transfers,'checks':['presence metadata','change and update observers','stale duplicate and delayed updates','remote local-state removal protection','default sync handshakes','awareness queries'],'rust_restoration_event_corrections':corrections,'status':'passed'}
 (ROOT/'validation/presence-results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
if __name__=='__main__':main()
