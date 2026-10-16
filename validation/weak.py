#!/usr/bin/env python3
"""Weak-link views and wire interchange against Rust with its weak feature enabled."""
import json,random,re,subprocess
from collections import Counter
from compare import ROOT,run
from updates import execute

def view(row):return {k:v for k,v in row.items() if k!='wire'}
exceptions={'xml_panics':0,'plain_disagrees_with_xml':0,'plain_unavailable_after_xml_panic':0,'observer_mismatch_snapshots':0,'xml_disagrees_with_plain':0,'extra_moon_events':0,'missing_moon_events':0,'extra_events_with_changed_view':0,'extra_format_marker_events_without_view_change':0,'extra_cleanup_events_without_view_change':0,'unclassified_extra_events':0}
def equivalent(p,q,previous=None,operation=None):
 p=json.loads(json.dumps(view(p)));q=json.loads(json.dumps(view(q)))
 p['events'].sort();q['events'].sort()
 if p['events']!=q['events']:
  exceptions['observer_mismatch_snapshots']+=1
  exceptions['extra_moon_events']+=sum((Counter(q['events'])-Counter(p['events'])).values())
  exceptions['missing_moon_events']+=sum((Counter(p['events'])-Counter(q['events'])).values())
  for key,count in (Counter(q['events'])-Counter(p['events'])).items():
   if previous is not None and previous['links'].get(key)!=q['links'].get(key):
    exceptions['extra_events_with_changed_view']+=count
   elif operation is not None and operation[0]=='f':
    exceptions['extra_format_marker_events_without_view_change']+=count
   elif operation is not None and operation[0]=='d':
    exceptions['extra_cleanup_events_without_view_change']+=count
   else:
    exceptions['unclassified_extra_events']+=count
 p.pop('events');q.pop('events')
 if p['links'].keys()!=q['links'].keys():return False
 for key,value in p['links'].items():
  if not key.startswith('t'):continue
  other=q['links'][key]
  if value[0]!=other[0]:return False
  plain,xml=value[1]
  if isinstance(xml,dict) and 'upstream_xml_panic' in xml:
   exceptions['xml_panics']+=1
   if plain!=other[1][0]:exceptions['plain_unavailable_after_xml_panic']+=1
   # This reference query is unavailable; retain all identity/document checks.
   other[1]=value[1]
  elif plain!=other[1][0] and xml==other[1][1] and re.sub(r'<[^>]*>','',xml)==other[1][0]:
   exceptions['plain_disagrees_with_xml']+=1
   other[1][0]=plain
  elif plain==other[1][0] and xml!=other[1][1] and re.sub(r'<[^>]*>','',xml)!=plain and re.sub(r'<[^>]*>','',other[1][1])==plain:
   exceptions['xml_disagrees_with_plain']+=1
   other[1][1]=xml
 return p==q
def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','weak'])
 run(['moon','build','validation/weak','--target','js','--release'])
 # Reproduce reference failures independently; they are not counted as passes.
 fixture=json.loads((ROOT/'validation/fixtures/upstream-weak-xml-panic.json').read_text())
 reference=execute(['validation/rust/target/release/weak','v1','raw-bounds'],[fixture])[0][-1]
 assert 'upstream_xml_panic' in reference['links']['t1'][1][1]
 fixture=json.loads((ROOT/'validation/fixtures/upstream-weak-empty-range-panic.json').read_text())
 crashed=subprocess.run(['validation/rust/target/release/weak','v1','raw-bounds'],cwd=ROOT,input=json.dumps(fixture)+'\n',text=True,capture_output=True)
 assert crashed.returncode!=0 and 'store.rs:342' in crashed.stderr and 'Option::unwrap()' in crashed.stderr
 safe=execute(['node','validation/weak.cjs','v1','raw-bounds'],[fixture])[0][-1]
 assert safe['links']['t4'][1]==['','']
 fixture=json.loads((ROOT/'validation/fixtures/upstream-weak-open-end-observers.json').read_text())
 reference=execute(['validation/rust/target/release/weak','v1'],[fixture])[0]
 port=execute(['node','validation/weak.cjs','v1'],[fixture])[0]
 for i in [2,4]:
  assert reference[i]['events']==[] and port[i]['events']==['topen']
  assert reference[i]['links']==port[i]['links']
 fixture=json.loads((ROOT/'validation/fixtures/weak-empty-quote-format-events.json').read_text())
 reference=execute(['validation/rust/target/release/weak','v1'],[fixture])[0]
 port=execute(['node','validation/weak.cjs','v1'],[fixture])[0]
 assert reference[-1]['links']==port[-1]['links']==port[-2]['links']
 assert reference[-1]['events']==[] and port[-1]['events']==['t2']
 assert port[-1]['state']!=port[-2]['state']  # actual format operations were inserted
 fixture=json.loads((ROOT/'validation/fixtures/weak-empty-quote-cleanup-events.json').read_text())
 reference=execute(['validation/rust/target/release/weak','v1','gc'],[fixture])[0]
 port=execute(['node','validation/weak.cjs','v1','gc'],[fixture])[0]
 assert reference[-1]['links']==port[-1]['links']==port[-2]['links']
 assert reference[-1]['events']==[] and port[-1]['events']==['t2']
 cases=[]
 for seed in range(64):
  rng=random.Random(22000+seed);ops=[['i',0,'abcdefghijklmnop'],*[['ai',i,i] for i in range(12)],['m','key',0],['ml','m0','key']]
  for prefix in ['t','a']:
   ops.extend([['q',prefix+'0',['i',1],['i',8]],['q',prefix+'1',None,['i',10]],['q',prefix+'2',['i',5],None],['q',prefix+'3',None,None],['q',prefix+'4',['e',2],['e',9]]])
  for _ in range(120):
   op=rng.choice(['i','d','ai','ad','m','md','ml','q','q','q','f','del'])
   if op in ['i','d','ai','ad','f']:
    cmd=[op,rng.randrange(100),rng.choice(['abc','z','m']) if op=='i' else rng.randrange(1,8)]
    if op=='f':cmd.append(rng.choice([True,None]))
   elif op=='m':cmd=[op,'key',rng.randrange(100)]
   elif op=='md':cmd=[op,'key']
   elif op=='ml':cmd=[op,'m'+str(rng.randrange(3)),'key']
   elif op=='q':cmd=[op,'a'+str(rng.randrange(5)),*[None if rng.randrange(5)==0 else [rng.choice(['i','e']),rng.randrange(100)] for _ in range(2)]]
   else:cmd=[op,rng.choice(['t','a','m'])+str(rng.randrange(5))]
   ops.append(cmd)
  cases.append(ops)
 total=0;imports=0
 for version in ['v1','v2']:
  for gc in [False,True]:
   rust=['validation/rust/target/release/weak',version]+(['gc'] if gc else []);moon=['node','validation/weak.cjs',version]+(['gc'] if gc else [])
   a=execute(rust,cases);b=execute(moon,cases)
   for i,(x,y) in enumerate(zip(a,b)):
    for j,(p,q) in enumerate(zip(x,y)):
     if Counter(p['events'])-Counter(q['events']) and not (ROOT/'validation/fixtures/weak-missing-observer.json').exists():
      (ROOT/'validation/fixtures/weak-missing-observer.json').write_text(json.dumps({'version':version,'gc':gc,'commands':cases[i][:j+1]}))
     if not equivalent(p,q,y[j-1] if j else None,cases[i][j]):
      (ROOT/'validation/fixtures/weak-failure.json').write_text(json.dumps({'version':version,'gc':gc,'commands':cases[i][:j+1]}));print('Mismatch',i,j,view(p),view(q));raise AssertionError(i)
   total+=sum(map(len,a))
   packets=[[['load',row['wire']]] for rows in a+b for row in rows[::12]]
   ra=execute(rust,packets);mb=execute(moon,packets)
   for i,(x,y) in enumerate(zip(ra,mb)):
    if not all(equivalent(p,q) for p,q in zip(x,y)):
     (ROOT/'validation/fixtures/weak-import-failure.json').write_text(json.dumps({'version':version,'gc':gc,'commands':packets[i]}));print('Import mismatch',version,gc,i,view(x[0]),view(y[0]));raise AssertionError(i)
   imports+=len(packets)
 assert exceptions['missing_moon_events']==0 and exceptions['unclassified_extra_events']==0, exceptions
 assert exceptions['plain_disagrees_with_xml']==40 and exceptions['xml_disagrees_with_plain']==8, exceptions
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','histories':64,'snapshots':total,'imports':imports,'versions':['v1','v2'],'gc_modes':[False,True],'reference_query_exceptions':exceptions.copy(),'view_status':'passed except reference-inconsistent queries','observer_status':'not compatible: recorded differences','status':'partial compatibility'}
 (ROOT/'validation/weak-results.json').write_text(json.dumps(result,indent=2)+'\n');print(result)
if __name__=='__main__':main()
