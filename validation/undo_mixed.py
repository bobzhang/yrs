#!/usr/bin/env python3
"""Live mixed-runtime undo with identical wire history at each replica.

Each logical replica has one editing owner and a mirror in the other runtime.
Only the owner executes local edits/undo; both receive exactly the same remote
packets. Every local commit is also replayed into its mirror. This avoids
assuming independently allocated restored IDs must produce identical conflicts.
"""
import argparse,json,random,subprocess,select,tempfile
from pathlib import Path
from undo import canonical,ROOT
from events import canonical as canonical_events
from updates import varuint

class Session:
 def __init__(self,command):
  self.calls=[]
  self.errors=tempfile.TemporaryFile(mode='w+t')
  self.proc=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors,text=True,bufsize=1)
 def call(self,commands):
  self.calls.append(commands)
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

def causal(row):
 result=[]
 for doc in row['causal']:
  ranges=[]
  for client,start,end in sorted((int(c),s,e) for c,s,e in doc['deleted'] if s<e):
   if ranges and ranges[-1][0]==client and start<=ranges[-1][2]:
    ranges[-1][2]=max(ranges[-1][2],end)
   else:ranges.append([client,start,end])
  result.append({'state':sorted([int(c),n] for c,n in doc['state'] if n),'deleted':ranges})
 return result

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--gc',choices=['both','on','off'],default='both')
 parser.add_argument('--owner',choices=['mixed','moon','rust'],default='mixed')
 parser.add_argument('--reference',choices=['rust','yjs'],default='rust')
 parser.add_argument('--target',choices=['js','native'],default='js')
 parser.add_argument('--seeds',type=int,default=96)
 parser.add_argument('--seed-start',type=int,default=0)
 parser.add_argument('--initial-clock',type=int,default=0,help='seed compressed GC history before editing (Yjs reference only)')
 parser.add_argument('--report',type=Path,help='write this scoped run, including failures, to a separate report')
 args=parser.parse_args()
 if args.seeds<=0 or args.seed_start<0:parser.error('seeds must be positive and seed-start nonnegative')
 if args.initial_clock and (args.reference!='yjs' or not 0 < args.initial_clock <= (1 << 32)-1-65536):parser.error('initial-clock requires Yjs and at least 65,536 remaining clocks')
 gc_modes=[False,True] if args.gc=='both' else [args.gc=='on']
 authorship=args.owner
 seeds=list(range(args.seed_start,args.seed_start+args.seeds))
 report=args.report
 if report is None and args.initial_clock==0 and args.gc=='both' and authorship=='mixed' and args.seeds==96 and args.seed_start==0:
  name='undo-mixed' if args.reference=='rust' else 'undo-yjs'
  report=ROOT/('validation/'+name+('-native' if args.target=='native' else '')+'-results.json')
 if args.reference=='yjs':
  assert authorship!='rust','Use --owner mixed or moon with the Yjs reference'
  assert json.loads((ROOT/'validation/yjs/node_modules/yjs/package.json').read_text())['version']=='13.6.27'
 scope={'upstream':'ac339600c712642e556895426113c3f9c117de39','reference':args.reference,'moonbit_target':args.target,'yjs_version':'13.6.27' if args.reference=='yjs' else None,'scenarios':len(seeds),'seed_start':args.seed_start,'gc_modes':gc_modes,'wire_versions':['v1','v2'],'authorship':authorship,'mixed_authorship':authorship=='mixed'}
 scope['initial_clock']=args.initial_clock
 def save_report(result):
  if report is not None:report.write_text(json.dumps(result,indent=2)+'\n')
 if args.reference=='rust':subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','undo'],cwd=ROOT,check=True)
 package='validation/undo_native' if args.target=='native' else 'validation/undo'
 subprocess.run(['moon','build',package,'--release','--target',args.target],cwd=ROOT,check=True)
 checked=duplicates=undo_actions=reconciliations=0
 observer_checks=notification_batches=deep_events=0
 local_undo_checks=local_edit_checks=local_batches=local_events=0
 reconciliation_kinds={'rendered_content':0,'xml_attributes_only':0,'causal_state_only':0}
 def notifications(row):
  return canonical_events({'notifications':row['snapshots'][-1]['notifications']})['notifications']
 def compare_events(rows, version, seed, step, command):
  a,b=map(notifications,rows)
  if a!=b:
   Path('/tmp/yrs-undo-mixed-events-failure.json').write_text(json.dumps({'version':version,'gc':gc,'seed':seed,'step':step,'command':command,'reference_engine':args.reference,'reference':rows[0],'moon':rows[1]})+'\n')
   raise AssertionError(('remote events',version,seed,step,command,a,b))
  return len(a),sum(len(batch.get('events',[])) for batch in a)
 for gc,version in [(gc,v) for gc in gc_modes for v in ['v1','v2']]:
  flags=['--gc'] if gc else []
  for seed in seeds:
   reference=['validation/rust/target/release/undo',version,'--live'] if args.reference=='rust' else ['node','validation/yjs/undo-live.cjs',version]
   port=['_build/native/release/build/validation/undo_native/undo_native.exe',version,'--live'] if args.target=='native' else ['node','validation/undo-live.cjs',version]
   sessions=[Session(reference+flags),Session(port+flags)]
   commands=history(seed)
   step=-1
   try:
    if args.initial_clock:
     packet=varuint(3)+b''.join(varuint(1)+varuint(c)+varuint(0)+bytes([0])+varuint(args.initial_clock) for c in [3,2,1])+bytes([0])
     bootstrap=[['seed',x,packet.hex()] for x in range(3)]
     last=[s.call(bootstrap) for s in sessions]
     assert all(row['result']==args.initial_clock for result in last for row in result['snapshots'])
    else:
     last=[s.call([]) for s in sessions]
    for step,c in enumerate(commands):
     op,x=c[:2];owner=(x+seed)%2 if authorship=='mixed' else (1 if authorship=='moon' else 0)
     if op=='tick':
      last=[s.call([c]) for s in sessions]
     elif op=='sync':
      packet=last[owner]['updates'][x];target=c[2]
      last=[s.call([['apply',target,packet]]) for s in sessions]
      batches,events=compare_events(last,version,seed,step,c)
      observer_checks+=1;notification_batches+=batches;deep_events+=events
     else:
      last[owner]=sessions[owner].call([c])
      packet=last[owner]['updates'][x]
      last[1-owner]=sessions[1-owner].call([['apply',x,packet]])
      if op in ('undo','redo'):undo_actions+=1
      # For MoonBit-owned edits, compare locally generated events directly with
      # the unchanged reference applying the generated update to its mirror.
      if owner==1 and op in ('undo','redo','batch'):
       batches,events=compare_events(last,version,seed,step,c)
       local_batches+=batches;local_events+=events
       if op=='batch':local_edit_checks+=1
       else:local_undo_checks+=1
     a,b=state(last[0]),state(last[1])
     # Imports can generate extra deletions, including undo-restored XML
     # attributes. Compare structured XML as well as rendered strings; exchange
     # generated operations before asserting convergence and count both causes.
     for round in range(3):
      if a==b and causal(last[0])==causal(last[1]):break
      for target in range(3):
       if a[target]!=b[target] or causal(last[0])[target]!=causal(last[1])[target]:
        last[0]=sessions[0].call([['apply',target,last[1]['updates'][target]]])
        last[1]=sessions[1].call([['apply',target,last[0]['updates'][target]]])
        reconciliations+=1
        rendered=lambda d:{k:v for k,v in d.items() if k!='xml_nodes'}
        kind='causal_state_only' if a[target]==b[target] else ('xml_attributes_only' if rendered(a[target])==rendered(b[target]) else 'rendered_content')
        reconciliation_kinds[kind]+=1
      a,b=state(last[0]),state(last[1])
     if a!=b or causal(last[0])!=causal(last[1]):
      Path('/tmp/yrs-undo-mixed-failure.json').write_text(json.dumps({'version':version,'gc':gc,'seed':seed,'commands':commands[:step+1],'reference_engine':args.reference,'reference':last[0],'moon':last[1]})+'\n')
      raise AssertionError((version,seed,step,c,a,b))
     checked+=3
     if step%11==0:
      before=a;before_causal=causal(last[0]);packet=last[owner]['updates'][x]
      last=[s.call([['apply',x,packet]]) for s in sessions]
      assert state(last[0])==state(last[1])==before,(version,seed,step,'duplicate')
      assert causal(last[0])==causal(last[1])==before_causal,(version,seed,step,'duplicate changed causal history')
      duplicates+=1
      batches,events=compare_events(last,version,seed,step,['duplicate',x])
      assert batches==0,(version,seed,step,'duplicate emitted events')
      observer_checks+=1
    final=state(last[0]);assert final[0]==final[1]==final[2],(version,seed,'convergence',final)
    final_causal=causal(last[0]);assert final_causal[0]==final_causal[1]==final_causal[2],(version,seed,'causal convergence',final_causal)
   except Exception as error:
    failure={**scope,'version':version,'gc':gc,'seed':seed,'step':step,'error':str(error),'calls':[s.calls for s in sessions]}
    Path('/tmp/yrs-undo-mixed-execution-failure.json').write_text(json.dumps(failure)+'\n')
    save_report({**scope,'status':'failed','version':version,'gc':gc,'seed':seed,'step':step,'error':str(error),'replica_state_comparisons_before_failure':checked})
    raise
   finally:
    for s in sessions:s.close()
   if (seed-args.seed_start)%16==15:print(f'{version} gc={gc} owner={authorship}: {seed-args.seed_start+1}/{len(seeds)} histories passed',flush=True)
 result={**scope,'replica_state_comparisons':checked,'causal_state_comparisons':checked,'causal_metadata':['state vectors','normalized deletion intervals'],'duplicate_deliveries':duplicates,'undo_redo_actions':undo_actions,'reconciliation_rounds':reconciliations,'reconciliation_kinds':reconciliation_kinds,'independent_restoration_identity_equality_required':False,'structured_xml_attributes_compared':True,'observer_events_compared':'identical remote sync/duplicate transactions and port-owned local edits/undo/redo versus reference wire mirrors, after prior state reconciliation','observer_transaction_comparisons':observer_checks,'port_local_undo_redo_observer_comparisons':local_undo_checks,'port_local_edit_observer_comparisons':local_edit_checks,'port_local_notification_batches':local_batches,'port_local_deep_events':local_events,'notification_batches':notification_batches,'deep_events':deep_events,'status':'passed'}
 save_report(result)
 print(json.dumps(result))
if __name__=='__main__':main()
