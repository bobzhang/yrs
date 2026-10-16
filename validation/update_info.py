#!/usr/bin/env python3
"""Compare decoded update metadata, including GC and sparse partial packets."""
import random,json
from compare import ROOT,run
from updates import execute

def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml'])
 run(['moon','build','validation/update_info','--target','js','--release'])
 cases=[]
 for seed in range(64):
  rng=random.Random(20000+seed);commands=[['trace',0]]
  for _ in range(80):
   op=rng.choice(['i','i','d','s','m','M']);x=rng.randrange(3)
   if op=='i':cmd=[op,x,rng.randrange(100),'abc']
   elif op=='d':cmd=[op,x,rng.randrange(100),rng.randrange(8)]
   elif op=='m':cmd=[op,x,'key'+str(rng.randrange(3)),rng.randrange(99)]
   elif op=='M':cmd=[op,x,'key'+str(rng.randrange(3))]
   else:cmd=[op,x,(x+1)%3]
   commands.append(cmd)
  cases.append(commands)
 packets=['0000','010101000a0300'] # empty and skip-only updates
 for gc in [False,True]:
  rows=execute(['validation/rust/target/release/yrs-reference','v1']+(['--gc'] if gc else []),cases)
  for row in rows:packets.extend(row['updates']);packets.extend(h[2] for h in row['history'])
 packets=list(dict.fromkeys(packets))
 requests=[[packet,[[c,(i*7+c*11)%100] for c in [1,2,3]]] for i,packet in enumerate(packets)]
 requests.append(json.loads((ROOT/'validation/fixtures/decoded-deleted-insertions.json').read_text()))
 for i in range(96):
  sticky={'assoc':-1 if i%2 else 0}
  if i%3==0:sticky['tname']='root界🦀'+str(i)
  else:sticky['item' if i%3==1 else 'type']={'client':i+1,'clock':i*997}
  requests.append({'sticky':sticky,'client':i+1,'clock':i*997})
 a=execute(['validation/rust/target/release/update_info'],requests);b=execute(['node','validation/update_info.cjs'],requests)
 for case,x,y in zip(requests,a,b):
  if x!=y:
   (ROOT/'validation/fixtures/update-info-failure.json').write_text(json.dumps(case));print('Mismatch',case,x,y);raise AssertionError(case)
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','histories':64,'gc_modes':[False,True],'packets':len(packets),'v2_metadata_cases':96,'checks':['empty and skip-only','contiguous upper vector','lower vector','insertions including GC','delete sets','state extension'],'status':'passed'}
 (ROOT/'validation/update-info-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
