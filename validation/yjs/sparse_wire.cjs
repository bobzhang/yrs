const Y = require('yjs');
const fs = require('node:fs');
const bytes = x => Uint8Array.from(x);
const arr = x => Array.from(x);
const state = x => [...Y.decodeStateVector(bytes(x))].sort((a,b)=>a[0]-b[0]);
function info(packet, v2) {
  const update = (v2 ? Y.decodeUpdateV2 : Y.decodeUpdate)(bytes(packet));
  const inserted = [];
  for(const s of update.structs) {
    if(s instanceof Y.Skip) continue;
    const row = [s.id.client, s.id.clock, s.id.clock+s.length];
    const prev = inserted.at(-1);
    if(prev && prev[0]===row[0] && prev[2]===row[1]) prev[2]=row[2];
    else inserted.push(row);
  }
  return {inserted:inserted.sort((a,b)=>a[0]-b[0]||a[1]-b[1]),
    deleted:[...update.ds.clients].flatMap(([c,rs])=>rs.map(r=>[c,r.clock,r.clock+r.len])).sort((a,b)=>a[0]-b[0]||a[1]-b[1])};
}
function produce(seed, gc) {
  let s=seed+1;
  const next=n=>{s=(Math.imul(s,1664525)+1013904223)>>>0;return s%n};
  const docs=[1,2,3].map(clientID=>{const d=new Y.Doc({gc});d.clientID=clientID;return d});
  const packets=[];
  for(const d of docs)d.on('update',u=>packets.push(arr(u)));
  for(let i=0;i<80;i++) {
    const d=docs[next(3)],t=d.getText('text'),a=d.getArray('array'),m=d.getMap('map');
    d.transact(()=>{
      switch(next(8)) {
        case 0: case 1: t.insert(next(2)?0:t.length,['abc','漢','🌙'][next(3)]);break;
        case 2: if(t.length)t.delete(0,t.length);break;
        case 3: if(t.length)t.format(0,t.length,{bold:next(2)===0});break;
        case 4: a.insert(next(a.length+1),[next(100),{label:'Moon'}]);break;
        case 5: if(a.length)a.delete(next(a.length),1);break;
        case 6: {const n=new Y.Map();n.set('value',next(100));m.set('k'+next(4),n);break;}
        case 7: m.delete('k'+next(4));break;
      }
    });
    // Exchanges change causal context; their duplicate events stay in the corpus.
    if(i%7===0)Y.applyUpdate(docs[next(3)],Y.encodeStateAsUpdate(d));
  }
  return packets;
}
function evaluate(x) {
  if('produce' in x)return produce(x.produce,x.gc);
  if(x.state_only) {
    const d=new Y.Doc({gc:false});
    for(const p of x.packets)Y.applyUpdate(d,bytes(p));
    return arr(Y.encodeStateVector(d));
  }
  if('inspect' in x)return {info:info(x.inspect,x.version===2),state:state(x.state)};
  if(x.convert)return x.packets.map(p=>arr(x.version===2?Y.convertUpdateFormatV1ToV2(bytes(p)):Y.convertUpdateFormatV2ToV1(bytes(p))));
  if(x.apply) {
    const d=new Y.Doc({gc:x.gc});d.clientID=99;
    for(const p of x.packets)(x.version===2?Y.applyUpdateV2:Y.applyUpdate)(d,bytes(p));
    return {text:d.getText('text').toString(),array:d.getArray('array').toJSON(),map:d.getMap('map').toJSON(),
      state:arr(Y.encodeStateVector(d)),wire:arr(Y.encodeStateAsUpdateV2(d)),pending:d.store.pendingStructs!==null||d.store.pendingDs!==null};
  }
  const v2=x.version===2;
  const merged=(v2?Y.mergeUpdatesV2:Y.mergeUpdates)(x.packets.map(bytes));
  return {merged:arr(merged),diff:arr((v2?Y.diffUpdateV2:Y.diffUpdate)(merged,bytes(x.remote))),
    vector:arr((v2?Y.encodeStateVectorFromUpdateV2:Y.encodeStateVectorFromUpdate)(merged))};
}
for(const line of fs.readFileSync(0,'utf8').trim().split('\n'))console.log(JSON.stringify(evaluate(JSON.parse(line))));
