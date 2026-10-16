#!/usr/bin/env python3
"""Pinned Rust comparison for ID sets and saved undo stacks with event metadata."""
import json, random
from compare import ROOT, run
from updates import execute

def main():
    run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml','--bin','contracts'])
    run(['moon','build','validation/contracts','--release','--target','js'])
    cases=[]
    for seed in range(128):
        rng=random.Random(16000+seed)
        def ranges():
            result=[]
            for _ in range(rng.randrange(32)):
                start=rng.randrange(10000);result.append([rng.randrange(1,8),start,start+rng.randrange(1,4000)])
            return result
        cases.append(['sets',ranges(),ranges()])
    for seed in range(128):
        rng=random.Random(16800+seed)
        def sparse_ranges():
            rows=[]
            for client in range(1,9):
                for _ in range(rng.randrange(4)):
                    start=rng.randrange(100)
                    rows.append([client,start,start+(rng.randrange(1,20) if rng.randrange(3)==0 else 0)])
            return rows
        cases.append(['sets',sparse_ranges(),sparse_ranges()])
    set_count=len(cases)
    for seed in range(96):
        rng=random.Random(17000+seed);commands=[]
        for _ in range(180):
            op=rng.choice(['i','i','d','reset','undo','redo','reload'])
            if op=='i':command=[op,rng.randrange(1000),rng.choice(['a','bc','moon','界'])]
            elif op=='d':command=[op,rng.randrange(1000),rng.randrange(1,7)]
            else:command=[op]
            commands.append(command)
        cases.append(['undo',commands])
    generated=execute(['validation/rust/target/release/contracts'],cases[set_count:])
    cases=cases[:set_count]
    for history in generated:
        for row in history[::8]:
            for action in ['undo','redo']:
                cases.append(['restore',row['client'],row['state'],row['undo'],row['redo'],[[action]]])
    rust=execute(['validation/rust/target/release/contracts'],cases)
    moon=execute(['node','validation/contracts.cjs'],cases)
    for index,(a,b) in enumerate(zip(rust,moon)):
        if cases[index][0]=='restore':
            for rows in [a,b]:
                for row in rows:
                    for event in row['events']:event[3].sort(key=lambda p:json.dumps(p))
        if a!=b:
            (ROOT/'validation/fixtures/contracts-failure.json').write_text(json.dumps(cases[index]))
            print('Mismatch',index,'Rust',a,'MoonBit',b)
            raise AssertionError(index)
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39','id_set_cases':set_count,'empty_client_set_cases':128,'undo_histories':96,'source_history_snapshots':17280,'restored_stack_cases':len(cases)-set_count,'checks':['empty client counts lookup union subtraction and codec preservation','set algebra','v1/v2 exact set bytes','serde stack schema','identical saved-state imports','undo/redo results','stack metadata','changed-parent event multisets'],'status':'passed'}
    (ROOT/'validation/contracts-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
