#!/usr/bin/env python3
import json, random, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def run(command, **kwargs):
    result = subprocess.run(command,cwd=ROOT,text=True,timeout=240,**kwargs)
    if result.returncode:
        raise RuntimeError(f"{command} failed: {result.stderr}")
    return result

def main():
    run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml'])
    run(['moon','build','--release','--target','js'])
    scenarios=[]
    for seed in range(128):
        rng=random.Random(seed)
        commands=[]
        for step in range(160):
            kind=rng.choice(['i','i','i','d','d','s','q','r'])
            x=rng.randrange(3)
            if kind=='i': cmd=[kind,x,rng.randrange(999),rng.choice(['a','bb','XYZ','hello',' '])]
            elif kind=='d': cmd=[kind,x,rng.randrange(999),rng.randrange(50)]
            elif kind in ('s','q'): cmd=[kind,x,(x+rng.randrange(1,3))%3]
            else: cmd=[kind,rng.randrange(999)]
            commands.append(cmd)
        for _ in range(3):
            for x in range(3):
                for y in range(3):
                    if x!=y: commands.append(['s',x,y])
        scenarios.append(commands)
    scenarios.append([['i',0,0,'A🌍中文\ufeffZ'],['s',0,1],['i',0,3,'!'],['i',1,7,'é'],['s',0,1],['s',1,0]])
    def execute(command, cases):
        inp=''.join(json.dumps(case,ensure_ascii=False)+'\n' for case in cases)
        return [json.loads(line) for line in run(command,input=inp,capture_output=True).stdout.splitlines()]
    rust_cmd=['validation/rust/target/release/yrs-reference']
    moon_cmd=['node','validation/run.cjs']
    rust=execute(rust_cmd,scenarios)
    moon=execute(moon_cmd,scenarios)
    assert len(rust)==len(moon)==len(scenarios)
    for seed,(a,b) in enumerate(zip(rust,moon)):
        for index,(ra,mb) in enumerate(zip(a['snapshots'],b['snapshots'])):
            assert ra==mb, f'seed={seed} step={index} op={scenarios[seed][index]} Rust={ra!r} Moon={mb!r}'
        assert [[[str(c),n] for c,n in state] for state in a['states']]==b['states'],f'state vector differs seed={seed}'
    for source,receiver in [(rust,moon_cmd),(moon,rust_cmd)]:
        cases=[[['a',i,update] for i,update in enumerate(result['updates'])] for result in source]
        received=execute(receiver,cases)
        for seed,(original,actual) in enumerate(zip(source,received)):
            assert original['snapshots'][-1]==actual['snapshots'][-1],f'cross-runtime update differs seed={seed}'
            assert [[[str(c),n] for c,n in state] for state in original['states']]==[[[str(c),n] for c,n in state] for state in actual['states']]
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(scenarios),'operation_snapshots':sum(map(len,scenarios)),'cross_runtime_documents':len(scenarios)*6,'status':'passed'}
    (ROOT/'validation/results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
if __name__=='__main__': main()
