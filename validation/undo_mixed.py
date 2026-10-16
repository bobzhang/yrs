#!/usr/bin/env python3
"""Live mixed-runtime undo with identical wire history at each replica.

Each logical replica has one editing owner and a mirror in the other runtime.
Only the owner executes local edits/undo; both receive exactly the same remote
packets. Every local commit is also replayed into its mirror. This avoids
assuming independently allocated restored IDs must produce identical conflicts.
"""
import json,random,subprocess,select,tempfile
from pathlib import Path
from undo import canonical,ROOT

class Session:
 def __init__(self,command):
  self.errors=tempfile.TemporaryFile(mode='w+t')
  self.proc=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors,text=True,bufsize=1)
 def call(self,commands):
  self.proc.stdin.write(json.dumps(commands)+'\n');self.proc.stdin.flush()
  if not select.select([self.proc.stdout],[],[],30)[0]:raise RuntimeError('live session timed out')
  line=self.proc.stdout.readline()
  if not line:
   self.errors.seek(0);raise RuntimeError(self.errors.read())
  row=json.loads(line)
  if 'error' in row:raise RuntimeError(row)
  return row
 def close(self):
  self.proc.stdin.close()
  try:self.proc.wait(timeout=5)
  except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()
  self.proc.stdout.close();self.errors.close()

def history(seed):
 rng=random.Random(13000+seed);commands=[]
 for _ in range(160):
  x=rng.randrange(3);kind=rng.randrange(12)
  if kind==0:commands.append(['sync',x,(x+rng.randrange(1,3))%3])
  elif kind<4:commands.append(['undo' if kind<3 else 'redo',x])
  elif kind==4:commands.append(['reset',x])
  elif kind==5:commands.append(['tick',x,rng.choice([100,600])])
  else:
   choices=['i','d','f','m','remove'] if seed<48 else ['new','remove','edit','shift','xnew','xremove','xedit']
   commands.append(['batch',x,[[rng.choice(choices),rng.randrange(100)] for _ in range(rng.randrange(1,4))]])
 commands += [['sync',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
 return commands

def state(row):return canonical({'docs':row['snapshots'][-1]['docs']})['docs']

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','undo'],cwd=ROOT,check=True)
 subprocess.run(['moon','build','validation/undo','--release','--target','js'],cwd=ROOT,check=True)
 checked=duplicates=undo_actions=reconciliations=0
 for version in ['v1','v2']:
  for seed in range(96):
   sessions=[Session(['validation/rust/target/release/undo',version,'--live']),Session(['node','validation/undo-live.cjs',version])]
   commands=history(seed)
   try:
    last=[s.call([]) for s in sessions]
    for step,c in enumerate(commands):
     op,x=c[:2];owner=(x+seed)%2
     if op=='tick':
      last=[s.call([c]) for s in sessions]
     elif op=='sync':
      packet=last[owner]['updates'][x];target=c[2]
      last=[s.call([['apply',target,packet]]) for s in sessions]
     else:
      last[owner]=sessions[owner].call([c])
      packet=last[owner]['updates'][x]
      last[1-owner]=sessions[1-owner].call([['apply',x,packet]])
      if op in ('undo','redo'):undo_actions+=1
     a,b=state(last[0]),state(last[1])
     # A remote rich-text import can generate additional formatting deletions.
     # Those are new CRDT operations, so they must flow back to the sender
     # before convergence is asserted; compare all content after reconciliation.
     for round in range(3):
      if a==b:break
      for target in range(3):
       if a[target]!=b[target]:
        last[0]=sessions[0].call([['apply',target,last[1]['updates'][target]]])
        last[1]=sessions[1].call([['apply',target,last[0]['updates'][target]]])
        reconciliations+=1
      a,b=state(last[0]),state(last[1])
     if a!=b:
      Path('/tmp/yrs-undo-mixed-failure.json').write_text(json.dumps({'version':version,'seed':seed,'commands':commands[:step+1],'rust':last[0],'moon':last[1]})+'\n')
      raise AssertionError((version,seed,step,c,a,b))
     checked+=3
     if step%11==0:
      before=a;packet=last[owner]['updates'][x]
      last=[s.call([['apply',x,packet]]) for s in sessions]
      assert state(last[0])==state(last[1])==before,(version,seed,step,'duplicate')
      duplicates+=1
    final=state(last[0]);assert final[0]==final[1]==final[2],(version,seed,'convergence',final)
   finally:
    for s in sessions:s.close()
   if seed%16==15:print(f'{version}: {seed+1}/96 mixed histories passed',flush=True)
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':96,'wire_versions':['v1','v2'],'mixed_authorship':True,'replica_state_comparisons':checked,'duplicate_deliveries':duplicates,'undo_redo_actions':undo_actions,'format_cleanup_reconciliation_rounds':reconciliations,'independent_restoration_identity_equality_required':False,'observer_events_compared':False,'status':'passed'}
 (ROOT/'validation/undo-mixed-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
