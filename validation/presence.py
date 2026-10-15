#!/usr/bin/env python3
"""Compare presence metadata, observer events and sync handshakes with pinned Yrs."""
import json, random, subprocess
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

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','presence'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/presence','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
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
 comparisons=0
 for seed,(r,m) in enumerate(zip(a,b)):
  for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
   comparisons+=1
   if x!=y:
    Path('/tmp/yrs-presence-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n')
    raise AssertionError(f'seed={seed} step={step} op={cases[seed][step]} Rust={x} Moon={y}')
 transfers=0
 for source in [a,b]:
  cases=[[['apply',i,u] for i,u in enumerate(row['updates'])] for row in source]
  ra,mb=run(rust,cases),run(moon,cases)
  for x,y in zip(ra,mb):
   assert x['snapshots']==y['snapshots'];transfers+=3
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(a),'operation_snapshots':comparisons,'cross_runtime_awareness_transfers':transfers,'checks':['presence metadata','change and update observers','stale duplicate and delayed updates','remote local-state removal protection','default sync handshakes','awareness queries'],'status':'passed'}
 (ROOT/'validation/presence-results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
if __name__=='__main__':main()
