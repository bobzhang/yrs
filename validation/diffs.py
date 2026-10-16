#!/usr/bin/env python3
"""Historical rich text and change annotation comparison with pinned Rust."""
import json,random,subprocess
from compare import ROOT,run
from updates import execute

def normalized(chunks):
 # Adjacent chunks may reflect different internal compaction boundaries. Merge
 # only when attributes and every annotated character's CRDT identity agree.
 out=[]
 for chunk in chunks:
  chunk=json.loads(json.dumps(chunk))
  if out and isinstance(chunk['insert'],str) and isinstance(out[-1]['insert'],str) and chunk['attrs']==out[-1]['attrs']:
   a,b=out[-1]['change'],chunk['change']
   contiguous=(a is None and b is None) or (a is not None and b is not None and a[:2]==b[:2] and a[2]+len(out[-1]['insert'].encode('utf-16-le'))//2==b[2])
   if contiguous:out[-1]['insert']+=chunk['insert'];continue
  out.append(chunk)
 return out

def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','diffs'])
 run(['moon','build','validation/diffs','--target','js','--release'])
 regression=json.loads((ROOT/'validation/fixtures/upstream-format-surrogate.json').read_text())
 crash=subprocess.run(['validation/rust/target/release/diffs'],cwd=ROOT,input=json.dumps(regression)+'\n',text=True,capture_output=True)
 assert crash.returncode!=0 and "Couldn't remove 1 elements" in crash.stderr
 yjs=json.loads(run(['node','validation/yjs/surrogate.cjs'],capture_output=True).stdout)
 assert yjs=={'formatted':[{'insert':'�'},{'insert':'�','attributes':{'bold':True}}],'deleted':[{'insert':'�'}]}
 cases=[]
 for seed in range(96):
  rng=random.Random(18000+seed);commands=[['s']]
  for _ in range(160):
   op=rng.choice(['i','i','d','f','e','s'])
   if op=='i':cmd=[op,rng.randrange(1000),rng.choice(['a','bc','界','漢字','é'])]
   elif op=='d':cmd=[op,rng.randrange(1000),rng.randrange(1,8)]
   elif op=='f':cmd=[op,rng.randrange(1000),rng.randrange(1,8),rng.choice([True,False])]
   elif op=='e':cmd=[op,rng.randrange(1000),rng.randrange(20)]
   else:cmd=[op]
   commands.extend([cmd,['q',rng.randrange(-1,30),rng.randrange(-1,30)]])
  cases.append(commands)
 histories=execute(['validation/rust/target/release/diffs'],cases)
 frames=[dict(frame,cleanup=cleanup) for history in histories for frame in history for cleanup in [False,True]]
 a=execute(['validation/rust/target/release/diffs'],frames);b=execute(['node','validation/diffs.cjs'],frames)
 for index,(x,y) in enumerate(zip(a,b)):
  x=normalized(x);y=normalized(y)
  if x!=y:
   (ROOT/'validation/fixtures/diff-failure.json').write_text(json.dumps(frames[index]))
   print('Mismatch',index,'Rust',x,'MoonBit',y);raise AssertionError(index)
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','histories':96,'queries':30720,'cleanup_formatting_modes':[False,True],'checks':['identical wire state and snapshot imports','historical content','attributes','embeds','added and removed annotation clock spans','BMP and combining Unicode'],'reference_exception':'half-surrogate formatting panic retained separately','status':'passed'}
 (ROOT/'validation/diff-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
