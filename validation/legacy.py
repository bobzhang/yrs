#!/usr/bin/env python3
"""Pinned Yjs legacy JSON and Yrs opaque type references in both wire formats."""
import json,subprocess
from pathlib import Path
from compare import ROOT,run,canonical_snapshot
from updates import varuint,execute,states

def string(s):
 b=s.encode();return varuint(len(b))+b

def fixture(reference,n):
 values=['undefined','{"x":1}','"hello"','🦀'][0:]+[str(i) for i in range(n)]
 # One client, three blocks: values; opaque branch; its map entry.
 data=varuint(1)+varuint(3)+varuint(1)+varuint(0)
 data+=bytes([8])+varuint(1)+string('items')+varuint(len(values))+b''.join(bytes([119])+string(s) for s in values)
 data+=bytes([0x87])+varuint(1)+varuint(len(values)-1)+bytes([reference])
 data+=bytes([0x28])+varuint(0)+varuint(1)+varuint(len(values))+string('key')+varuint(1)+bytes([119])+string('kept')
 return (data+varuint(0)).hex()

def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml'])
 run(['moon','build','validation/bridge','--release','--target','js'])
 fixtures=[fixture(tag,n) for tag in [5,9,15] for n in range(16)]
 converted=run(['validation/rust/target/release/convert'],input='\n'.join(fixtures)+'\n',capture_output=True).stdout.splitlines()
 checks=transfers=legacy_checks=0
 for version,packets in [('v1',fixtures),('v2',converted)]:
  for gc in [False,True]:
   cases=[]
   for i,packet in enumerate(packets):
    cases.append([['a',0,packet],['s',0,1],['D',0,1,1],['I',1,2,[42]],['s',0,1],['s',1,0],['a',2,packet],['s',0,2],['s',2,0]])
   rust=['validation/rust/target/release/yrs-reference',version]+(['--gc'] if gc else [])
   moon=['node','validation/run.cjs',version]+(['--gc'] if gc else [])
   a,b=execute(rust,cases),execute(moon,cases)
   for r,m in zip(a,b):
    assert len(r['snapshots'])==len(m['snapshots'])==9
    assert [states(v) for v in r['states']]==[states(v) for v in m['states']],(r['states'],m['states'])
    for x,y in zip(r['snapshots'],m['snapshots']):assert canonical_snapshot(x)==canonical_snapshot(y),(x,y);checks+=1
   for rows in [a,b]:
    cases=[[['a',i,u] for i,u in enumerate(row['updates'])] for row in rows]
    rs,ms=execute(rust,cases),execute(moon,cases)
    for r,m in zip(rs,ms):assert canonical_snapshot(r['snapshots'][-1])==canonical_snapshot(m['snapshots'][-1]);transfers+=3
 # The pinned Rust legacy JSON decoder has an off-by-one error. Verify
 # standards-compliant packets against pinned Yjs, retaining that exception.
 legacy=[]
 for n in range(32):
  values=[None,True,{'x':n},'🦀',n]+list(range(n))
  strings=['undefined']+[json.dumps(v,ensure_ascii=False,separators=(',',':')) for v in values]
  packet=(varuint(1)+varuint(1)+varuint(1)+varuint(0)+bytes([2])+varuint(1)+string('items')+varuint(len(strings))+b''.join(string(s) for s in strings)+varuint(0)).hex()
  legacy.append(packet)
 regression=json.loads((ROOT/'validation/fixtures/upstream-legacy-json.json').read_text())
 assert legacy[0]==regression['update_v1']
 failure=subprocess.run(['validation/rust/target/release/convert'],cwd=ROOT,input=legacy[0]+'\n',text=True,capture_output=True)
 assert failure.returncode!=0 and 'EndOfBuffer' in failure.stderr,failure.stderr
 for version in ['v1','v2']:
  yjs=execute(['node','validation/yjs/legacy.cjs',version],legacy)
  for expected in yjs:
   source=expected['source']
   cases=[[['a',0,source],['D',0,1,1]]]
   row=execute(['node','validation/run.cjs',version],cases)[0]
   assert row['snapshots'][0][0]['array']==expected['before'],(row,expected)
   assert row['snapshots'][1][0]['array']==expected['after'],(row,expected)
   replay=execute(['node','validation/yjs/legacy.cjs',version,'replay'],[row['updates'][0]])[0]
   assert replay['before']==expected['after'],(replay,expected)
   legacy_checks+=1
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','fixtures':48,'legacy_yjs_cases':legacy_checks,'legacy_rust_decoder':'known off-by-one exception','yjs_version':'13.6.27','opaque_type_refs':[5,9,15],'wire_versions':['v1','v2'],'gc_modes':[False,True],'snapshots':checks,'wire_replay_documents':transfers,'status':'passed'}
 (ROOT/'validation/legacy-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
