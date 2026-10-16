#!/usr/bin/env python3
"""Compare Yrs JSONPath parsing and immutable/shared-document evaluation."""
import json,random
from compare import ROOT,run
from updates import execute

def main():
 run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','queries'])
 run(['moon','build','validation/queries','--release','--target','js'])
 cases=[]
 paths=['','$','$.users','$.users[0]','$.users[-1].name','$.users[2,0,-1,0].age','$.users[1:4:2].name','$.users[:].name','$.users[*].name',"$['users','missing','users'][0].name",'$..name','$..friends.*.name','$.users..age','$.users[1].missing','$.users[999]','$.users[-999]','$.data.*','$.data..name','$.name','$.名字','$.éclair','$.𐐀letter','$.bad!', '$.', '$[?(@.age>3)]', '$[not_an_index]', "$['unpaired]", '$[99999999999999]']
 for seed in range(64):
  rng=random.Random(19000+seed)
  users=[{'name':'user'+str(i),'age':rng.randrange(99),'friends':[{'name':'friend'+str(j),'age':rng.randrange(99)} for j in range(rng.randrange(5))]} for i in range(rng.randrange(1,9))]
  data={'users':users,'data':{'name':'outer','child':{'name':'inner','values':[1,2,3]}},'name':'top','名字':'名称','éclair':'cake','𐐀letter':'unicode'}
  generated=paths+[f'$.users[{rng.randrange(-12,12)}].friends[{rng.randrange(-6,6)}].name' for _ in range(32)]
  cases.append({'value':data,'paths':generated})
 a=execute(['validation/rust/target/release/queries'],cases);b=execute(['node','validation/queries.cjs'],cases)
 checks=0
 for case,x,y in zip(cases,a,b):
  for path,u,v in zip(case['paths'],x,y):
   if '*' in path or '..' in path:
    for row in [u,v]:
     for kind in ['any','doc']:
      if kind in row:row[kind].sort(key=lambda value:json.dumps(value,sort_keys=True))
   if u!=v:
    (ROOT/'validation/fixtures/query-failure.json').write_text(json.dumps({'value':case['value'],'paths':[path]},ensure_ascii=False))
    print('Mismatch',path,'Rust',u,'MoonBit',v);raise AssertionError(path)
   checks+=1
 result={'upstream':'ac339600c712642e556895426113c3f9c117de39','documents':64,'queries':checks,'evaluations':checks*2,'checks':['shared types','immutable values','unions and negative indices','recursive descent','slices','Unicode names','invalid syntax'],'status':'passed'}
 (ROOT/'validation/query-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
