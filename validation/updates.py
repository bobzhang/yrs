#!/usr/bin/env python3
"""Rust oracle for incomplete-history relays and stateless update utilities."""
import json, random, subprocess, signal
from pathlib import Path
from compare import run, canonical_snapshot, ROOT

def execute(command, cases):
    result=run(command,input=''.join(json.dumps(x)+'\n' for x in cases),capture_output=True)
    rows=[json.loads(line) for line in result.stdout.splitlines()]
    assert len(rows)==len(cases)
    for i,row in enumerate(rows):
        if 'error' in row:
            Path('/tmp/yrs-update-failure.json').write_text(json.dumps(cases[i]))
            raise AssertionError(row)
    return rows

def states(value):
    return [[str(client),clock] for client,clock in value]

def varuint(n):
    out=[]
    while n>127:out.append((n&127)|128);n>>=7
    out.append(n);return bytes(out)

def main():
    run(['cargo','+1.97.1','build','--release','--locked','--manifest-path','validation/rust/Cargo.toml'])
    run(['moon','build','--release','--target','js'])
    scenarios=[]
    for seed in range(32):
        rng=random.Random(5000+seed);commands=[['trace',0]]
        for _ in range(120):
            kind=rng.choice(['i','i','d','m','M','n','e','s','q','r','u','u']);x=rng.randrange(3)
            if kind=='i':cmd=[kind,x,rng.randrange(999),rng.choice(['a','bb','Moon'])]
            elif kind=='d':cmd=[kind,x,rng.randrange(999),rng.randrange(30)]
            elif kind=='m':cmd=[kind,x,'key'+str(rng.randrange(3)),rng.randrange(100)]
            elif kind=='M':cmd=[kind,x,'key'+str(rng.randrange(3))]
            elif kind=='n':cmd=[kind,x,'key'+str(rng.randrange(3)),'title']
            elif kind=='e':cmd=[kind,x,'key'+str(rng.randrange(3)),rng.randrange(999)]
            elif kind in ('s','q'):cmd=[kind,x,(x+rng.randrange(1,3))%3]
            elif kind=='u':cmd=[kind,x,(x+rng.randrange(1,3))%3,[[c,rng.randrange(40)] for c in [1,2,3]]]
            else:cmd=[kind,rng.randrange(999)]
            commands.append(cmd)
        for _ in range(3):
            commands.extend(['s',x,y] for x in range(3) for y in range(3) if x!=y)
        scenarios.append(commands)
    snapshots=0;replayed=0;converged=0;utility_cases=0;reference_failures=[]
    for version in ['v1']:
      for gc in [False,True]:
        rust=['validation/rust/target/release/yrs-reference',version]+(['--gc'] if gc else [])
        moon=['node','validation/run.cjs',version]
        active=[]
        a=[]
        if gc:
            for seed,case in enumerate(scenarios):
                proc=subprocess.run(rust,cwd=ROOT,input=json.dumps(case)+'\n',text=True,capture_output=True,timeout=30)
                if proc.returncode:
                    # Pinned upstream has a reproducible sparse/GC bus error.
                    # Do not silently skip arbitrary reference failures.
                    assert seed==28 and proc.returncode in (-signal.SIGBUS,-signal.SIGSEGV),(seed,proc.returncode,proc.stderr)
                    reference_failures.append({'wire_version':version,'rust_gc':True,'scenario':seed,'signal':signal.Signals(-proc.returncode).name})
                    continue
                row=json.loads(proc.stdout)
                if gc:
                    # This pinned GC history emits a wrapped skip of UINT32_MAX.
                    # Preserve strict decoder overflow checks instead of accepting it.
                    probe={'updates':[cmd[2] for cmd in row['history']],'remote':'00'}
                    decoded=subprocess.run(moon+['utilities'],cwd=ROOT,input=json.dumps(probe)+'\n',text=True,capture_output=True,timeout=30)
                    assert decoded.returncode==0
                    error=json.loads(decoded.stdout).get('error')
                    if error is not None:
                        assert error=='clock overflow',error
                        reference_failures.append({'wire_version':version,'rust_gc':True,'scenario':seed,'error':'reference emitted an overflowing skip block'})
                        continue
                a.append(row);active.append(case)
        else:
            active=scenarios;a=execute(rust,active)
        b=execute(moon,active)
        for seed,(ra,mb) in enumerate(zip(a,b)):
            assert len(ra['snapshots'])==len(mb['snapshots'])==len(active[seed])-1
            # Different GC policies change intermediate readiness, which in
            # turn changes later position-based edits. Compare each producer's
            # convergence, and compare runtimes using identical wire below.
            if gc:
                for produced in [ra,mb]:
                    final=canonical_snapshot(produced['snapshots'][-1])
                    assert final[0]==final[1]==final[2],f'producer did not converge {version} seed={seed}'
                    vectors=[states(s) for s in produced['states']]
                    assert vectors[0]==vectors[1]==vectors[2]
                    converged+=1
                continue
            pairs=list(enumerate(zip(ra['snapshots'],mb['snapshots'])))
            for step,(x,y) in pairs:
                if canonical_snapshot(x)!=canonical_snapshot(y):
                    Path('/tmp/yrs-relay-failure.json').write_text(json.dumps(active[seed][:step+2]))
                    print('Rust',x,'Moon',y,flush=True)
                assert canonical_snapshot(x)==canonical_snapshot(y),f'relay {version} gc={gc} seed={seed} step={step}'
                snapshots+=1
            assert [states(s) for s in ra['states']]==[states(s) for s in mb['states']]
        for source in [a,b]:
            traces=[row['history'] for row in source]
            for offset in range(0,len(traces),8):
                batch=traces[offset:offset+8]
                rr,mm=execute(rust,batch),execute(moon,batch)
                for seed,(ra,mb) in enumerate(zip(rr,mm)):
                    for step,(x,y) in enumerate(zip(ra['snapshots'],mb['snapshots'])):
                        if canonical_snapshot(x)!=canonical_snapshot(y):
                            Path('/tmp/yrs-relay-wire-failure.json').write_text(json.dumps(batch[seed][:step+1]))
                            raise AssertionError(f'relay wire differs {version} gc={gc} trace={offset+seed} step={step} Rust={x} Moon={y}')
                        replayed+=1
                    assert [states(s) for s in ra['states']]==[states(s) for s in mb['states']]
        cases=[]
        for source in [a,b]:
            for seed,row in enumerate(source):
                rng=random.Random(6000+seed)
                updates=[cmd[2] for cmd in row['history']]
                for _ in range(4):
                    subset=rng.choices(updates,k=rng.randrange(0,50))
                    remote=varuint(3)+b''.join(varuint(c)+varuint(rng.randrange(80)) for c in [1,2,3])
                    cases.append({'updates':subset,'remote':remote.hex()})
        ra,mb=execute(rust+['utilities'],cases),execute(moon+['utilities'],cases)
        for i,(x,y) in enumerate(zip(ra,mb)):
            assert states(x['states'])==states(y['states']),f'extracted state differs case={i} {x} {y}'
        imports=lambda rows:[[['a',0,row['merged']],['a',1,row['diff']]] for row in rows]
        # Both engines must accept each producer's merged and differential wire.
        for output in [ra,mb]:
            x,y=execute(rust,imports(output)),execute(moon,imports(output))
            for i,(xr,ym) in enumerate(zip(x,y)):
                assert canonical_snapshot(xr['snapshots'][-1])==canonical_snapshot(ym['snapshots'][-1]),f'utility import differs case={i}'
                assert [states(s) for s in xr['states']]==[states(s) for s in ym['states']]
        # Different valid block layouts must represent the same integrated state.
        x,y=execute(rust,imports(ra)),execute(rust,imports(mb))
        for i,(xr,yr) in enumerate(zip(x,y)):
            assert canonical_snapshot(xr['snapshots'][-1])==canonical_snapshot(yr['snapshots'][-1]),f'merge/diff differs case={i}'
            assert [states(s) for s in xr['states']]==[states(s) for s in yr['states']]
        utility_cases+=len(cases)
    result={'upstream':'ac339600c712642e556895426113c3f9c117de39','relay_scenarios':len(scenarios),'wire_versions':['v1'],'rust_gc_modes':[False,True],'independent_relay_snapshots':snapshots,'wire_replay_snapshots':replayed,'gc_producer_convergence_checks':converged,'stateless_merge_diff_cases':utility_cases,'reference_failures':reference_failures,'status':'passed_available_reference_cases'}
    (ROOT/'validation/update-results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
if __name__=='__main__':main()
