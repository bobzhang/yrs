#!/usr/bin/env python3
"""Cross-check cursor identities, resolved offsets and historical snapshots."""
import json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def execute(cmd,cases):
 p=subprocess.run(cmd,cwd=ROOT,text=True,input=''.join(json.dumps(c)+'\n' for c in cases),capture_output=True,timeout=180)
 if p.returncode:raise RuntimeError(p.stderr)
 rows=[json.loads(line) for line in p.stdout.splitlines()];assert len(rows)==len(cases)
 for i,row in enumerate(rows):
  if 'error' in row:
   Path('/tmp/yrs-history-failure.json').write_text(json.dumps(cases[i])+'\n');raise RuntimeError(row)
 return rows

def main():
 subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','history'],cwd=ROOT,check=True)
 regression=json.loads(subprocess.check_output(['validation/rust/target/release/history','--reference-snapshot-regression'],cwd=ROOT,text=True))
 assert regression['reference_decode_error'].startswith('EndOfBuffer')
 subprocess.run(['moon','build','validation/history','--release','--target','js'],cwd=ROOT,check=True)
 cases=[]
 for seed in range(64):
  rng=random.Random(9000+seed);commands=[]
  for _ in range(100):
   op=rng.choice(['i','i','d','s','mark','mark','boundary','snapshot']);x=rng.randrange(3)
   if op=='i':c=[op,x,rng.randrange(999),rng.choice(['a','xyz','Moon'])]
   elif op=='d':c=[op,x,rng.randrange(999),rng.randrange(30)]
   elif op=='s':c=[op,x,(x+rng.randrange(1,3))%3]
   elif op=='mark':c=[op,x,rng.randrange(999),rng.choice([-1,0])]
   elif op=='boundary':c=[op,x,rng.choice([-1,0])]
   else:c=[op,x]
   commands.append(c)
  commands += [['s',x,y] for _ in range(3) for x in range(3) for y in range(3) if x!=y]
  cases.append(commands)
 checks=transfers=offsets=restores=0
 for version in ['v1','v2']:
  print('checking '+version,flush=True)
  rust=['validation/rust/target/release/history',version];moon=['node','validation/history.cjs',version]
  ra,mb=execute(rust,cases),execute(moon,cases)
  for seed,(r,m) in enumerate(zip(ra,mb)):
   for step,(x,y) in enumerate(zip(r['snapshots'],m['snapshots'])):
    checks+=1;offsets+=sum(3 for c in x['cursors'] if c);restores+=len(x['past'])
    if x!=y:
     Path('/tmp/yrs-history-failure.json').write_text(json.dumps(cases[seed][:step+1])+'\n');raise AssertionError(f'{version} seed={seed} step={step} op={cases[seed][step]} Rust={x!r} Moon={y!r}')
  for source in [ra,mb]:
   cross=[]
   for row in source:
    cross.append([['apply',i,u] for i,u in enumerate(row['updates'])]+[['cursor_bytes',0,c] for c in row['marks']]+[['snapshot_bytes',i,s,expected] for i,s,expected in row['saved']])
   received_rust,received_moon=execute(rust,cross),execute(moon,cross)
   for case,(r,m) in enumerate(zip(received_rust,received_moon)):
    if r['snapshots']!=m['snapshots']:
     Path('/tmp/yrs-history-failure.json').write_text(json.dumps(cross[case])+'\n');raise AssertionError(f'{version} cross-runtime case {case}')
    transfers+=len(cross[case])
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(cases),'wire_versions':['v1','v2'],'operation_snapshots':checks,'resolved_cursor_offsets':offsets,'historical_reconstructions':restores,'cross_runtime_payloads':transfers,'snapshot_oracle':'historical content captured at snapshot creation plus independent snapshot metadata decoding', 'reference_snapshot_encoder_regression':regression, 'status':'passed'}
 (ROOT/'validation/history-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
