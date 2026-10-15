#!/usr/bin/env python3
import json, random, subprocess, os, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def run(command, **kwargs):
    result = subprocess.run(command,cwd=ROOT,text=True,timeout=240,**kwargs)
    if result.returncode:
        raise RuntimeError(f"{command} failed: {result.stderr}")
    return result

def canonical_snapshot(snapshot):
    # Delta producers may split equivalent adjacent strings at different
    # internal format markers. Compare the rendered rich-text operation stream.
    snapshot=json.loads(json.dumps(snapshot))
    for document in snapshot:
        merged=[]
        for chunk in document.get('delta',[]):
            if merged and isinstance(chunk['insert'],str) and isinstance(merged[-1]['insert'],str) and chunk.get('attributes',{})==merged[-1].get('attributes',{}):
                merged[-1]['insert']+=chunk['insert']
            else: merged.append(chunk)
        document['delta']=merged
    return snapshot

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
    for seed in range(128):
        rng=random.Random(1000+seed)
        commands=[]
        for step in range(160):
            kind=rng.choice(['I','I','D','m','m','M','s','q','r'])
            x=rng.randrange(3)
            value=rng.choice([None,True,False,-42,0,123,1.5,'Moon🌍',{'nested':[1,'two',None]},[1,2,3]])
            if kind=='I': cmd=[kind,x,rng.randrange(999),[value]*rng.randrange(1,4)]
            elif kind=='D': cmd=[kind,x,rng.randrange(999),rng.randrange(50)]
            elif kind=='m': cmd=[kind,x,'key'+str(rng.randrange(5)),value]
            elif kind=='M': cmd=[kind,x,'key'+str(rng.randrange(5))]
            elif kind in ('s','q'): cmd=[kind,x,(x+rng.randrange(1,3))%3]
            else: cmd=[kind,rng.randrange(999)]
            commands.append(cmd)
        for _ in range(3):
            for x in range(3):
                for y in range(3):
                    if x!=y: commands.append(['s',x,y])
        scenarios.append(commands)
    for seed in range(128):
        rng=random.Random(2000+seed)
        commands=[]
        for step in range(160):
            kind=rng.choice(['n','e','e','M','s','q','r'])
            x=rng.randrange(3)
            key='key'+str(rng.randrange(3))
            if kind=='n': cmd=[kind,x,key,'title']
            elif kind=='e': cmd=[kind,x,key,rng.randrange(999)]
            elif kind=='M': cmd=[kind,x,key]
            elif kind in ('s','q'): cmd=[kind,x,(x+rng.randrange(1,3))%3]
            else: cmd=[kind,rng.randrange(999)]
            commands.append(cmd)
        for _ in range(3):
            for x in range(3):
                for y in range(3):
                    if x!=y: commands.append(['s',x,y])
        scenarios.append(commands)
    for seed in range(128):
        rng=random.Random(3000+seed)
        commands=[]
        for step in range(160):
            kind=rng.choice(['f','f','t','b','i','d','s','q','r'])
            x=rng.randrange(3)
            attrs={rng.choice(['bold','italic','color']):rng.choice([True,False,None,'red'])}
            if kind=='f': cmd=[kind,x,rng.randrange(999),rng.randrange(50),attrs]
            elif kind=='t': cmd=[kind,x,rng.randrange(999),rng.choice(['x','yz','Moon']),attrs]
            elif kind=='b': cmd=[kind,x,rng.randrange(999),{'image':'moon.png'},attrs]
            elif kind=='i': cmd=[kind,x,rng.randrange(999),'plain']
            elif kind=='d': cmd=[kind,x,rng.randrange(999),rng.randrange(50)]
            elif kind in ('s','q'): cmd=[kind,x,(x+rng.randrange(1,3))%3]
            else: cmd=[kind,rng.randrange(999)]
            commands.append(cmd)
        for _ in range(3):
            for x in range(3):
                for y in range(3):
                    if x!=y: commands.append(['s',x,y])
        scenarios.append([["trace",0]]+commands)
    start=int(os.environ.get('YRS_CASE_START','0'))
    scenarios=scenarios[start:]
    def execute(command, cases):
        inp=''.join(json.dumps(case,ensure_ascii=False)+'\n' for case in cases)
        results = [json.loads(line) for line in run(command,input=inp,capture_output=True).stdout.splitlines()]
        assert len(results)==len(cases), f'{command} returned {len(results)} results for {len(cases)} cases'
        for index, result in enumerate(results):
            if 'error' in result:
                Path('/tmp/yrs-failing-scenario.json').write_text(json.dumps(cases[index])+'\n')
                raise RuntimeError(f'{command} scenario={index}: {result}')
        return results
    rust_cmd=['validation/rust/target/release/yrs-reference']
    moon_cmd=['node','validation/run.cjs']
    base_rust,base_moon=rust_cmd,moon_cmd
    versions=os.environ.get('YRS_VERSIONS','v1,v2').split(',')
    gc_modes=[v=='1' for v in os.environ.get('YRS_GC','0,1').split(',')]
    checks={'independent_operation_snapshots':0,'wire_replay_snapshots':0,'same_state_local_operations':0}
    for version in versions:
      for gc in gc_modes:
        print(f'checking {version} gc={gc}',file=sys.stderr,flush=True)
        rust_cmd=base_rust+[version]+(['--gc'] if gc else [])
        moon_cmd=base_moon+[version]
        rust=execute(rust_cmd,scenarios)
        moon=execute(moon_cmd,scenarios)
        assert len(rust)==len(moon)==len(scenarios)
        for seed,(a,b) in enumerate(zip(rust,moon)):
            if scenarios[seed][0][0]=='trace':
                continue
            assert len(a['snapshots'])==len(b['snapshots'])==len(scenarios[seed])
            for index,(ra,mb) in enumerate(zip(a['snapshots'],b['snapshots'])):
                ra,mb=canonical_snapshot(ra),canonical_snapshot(mb)
                if ra != mb: Path('/tmp/yrs-failing-scenario.json').write_text(json.dumps(scenarios[seed][:index+1])+'\n')
                checks['independent_operation_snapshots']+=1
                assert ra==mb, f'seed={seed} step={index} op={scenarios[seed][index]} Rust={ra!r} Moon={mb!r}'
            assert [[[str(c),n] for c,n in state] for state in a['states']]==b['states'],f'state vector differs seed={seed}'
        # Attribute HashMap iteration makes independent Rust rich-text histories
        # nondeterministic. Replay identical wire histories, and compare local
        # edits starting from identical serialized documents, in both directions.
        for source in [rust,moon]:
            traces=[item['history'] for item in source if item['history']]
            for offset in range(0,len(traces),16):
                cases=traces[offset:offset+16]
                a,b=execute(rust_cmd,cases),execute(moon_cmd,cases)
                for seed,(ra,mb) in enumerate(zip(a,b)):
                    assert len(ra['snapshots'])==len(mb['snapshots'])==len(cases[seed])
                    for index,(x,y) in enumerate(zip(ra['snapshots'],mb['snapshots'])):
                        checks['wire_replay_snapshots']+=1
                        if canonical_snapshot(x)!=canonical_snapshot(y):
                            Path('/tmp/yrs-failing-trace.json').write_text(json.dumps(cases[seed][:index+1])+'\n')
                            raise AssertionError(f'wire replay differs trace={offset+seed} step={index} Rust={x!r} Moon={y!r}')
                    assert [[[str(c),n] for c,n in state] for state in ra['states']]==mb['states']
            local=[case for item in source for case in item['local_cases']]
            for offset in range(0,len(local),256):
                cases=local[offset:offset+256]
                a,b=execute(rust_cmd,cases),execute(moon_cmd,cases)
                for index,(ra,mb) in enumerate(zip(a,b)):
                    checks['same_state_local_operations']+=1
                    if canonical_snapshot(ra['snapshots'][-1])!=canonical_snapshot(mb['snapshots'][-1]):
                        Path('/tmp/yrs-failing-local.json').write_text(json.dumps(cases[index])+'\n')
                        raise AssertionError(f'local rich-text operation differs case={offset+index} op={cases[index][-1]} Rust={ra["snapshots"][-1]!r} Moon={mb["snapshots"][-1]!r}')
        for source,receiver in [(rust,moon_cmd),(moon,rust_cmd)]:
            cases=[[['a',i,update] for i,update in enumerate(result['updates'])] for result in source]
            received=execute(receiver,cases)
            for seed,(original,actual) in enumerate(zip(source,received)):
                assert canonical_snapshot(original['snapshots'][-1])==canonical_snapshot(actual['snapshots'][-1]),f'cross-runtime update differs seed={seed}'
                assert [[[str(c),n] for c,n in state] for state in original['states']]==[[[str(c),n] for c,n in state] for state in actual['states']]
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39','scenarios':len(scenarios),'wire_versions':versions,'rust_gc_modes':gc_modes,'checks':checks,'cross_runtime_documents':len(scenarios)*6*len(versions)*len(gc_modes),'status':'passed'}
    if not any(name.startswith('YRS_') for name in os.environ): (ROOT/'validation/results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
if __name__=='__main__': main()
