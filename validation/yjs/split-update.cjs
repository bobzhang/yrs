// Decode and re-encode complete struct boundaries with the pinned Yjs codec.
// This changes packet boundaries only, never an operation's identity or content.
const Y = require('yjs');
const E = require('lib0/encoding');
const fs = require('node:fs');
for (const line of fs.readFileSync(0, 'utf8').trim().split('\n')) {
  const {structs, ds} = Y.decodeUpdate(Buffer.from(JSON.parse(line), 'hex'));
  const packets = [];
  for (const item of structs) {
    if (item instanceof Y.Skip) continue;
    const e = new Y.UpdateEncoderV1();
    E.writeVarUint(e.restEncoder, 1); // one client
    E.writeVarUint(e.restEncoder, 1); // one struct
    e.writeClient(item.id.client);
    E.writeVarUint(e.restEncoder, item.id.clock);
    item.write(e, 0);
    E.writeVarUint(e.restEncoder, 0); // deletions follow in a separate packet
    packets.push(Buffer.from(e.toUint8Array()).toString('hex'));
  }
  const e = new Y.UpdateEncoderV1();
  E.writeVarUint(e.restEncoder, 0);
  E.writeVarUint(e.restEncoder, ds.clients.size);
  for (const [client, ranges] of [...ds.clients].sort((a,b) => b[0]-a[0])) {
    e.resetDsCurVal();
    E.writeVarUint(e.restEncoder, client);
    E.writeVarUint(e.restEncoder, ranges.length);
    for (const r of ranges) { e.writeDsClock(r.clock); e.writeDsLen(r.len); }
  }
  packets.push(Buffer.from(e.toUint8Array()).toString('hex'));
  console.log(JSON.stringify(packets));
}
