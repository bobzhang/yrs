// Small packets exercising full unsigned clock ranges; no per-clock allocation.
const fs = require('node:fs');
const Y = require('yjs');
const hex = b => Buffer.from(b).toString('hex');
const bytes = s => new Uint8Array(Buffer.from(s, 'hex'));
const v2 = process.argv.includes('v2');
const apply = v2 ? Y.applyUpdateV2 : Y.applyUpdate;
const encode = v2 ? Y.encodeStateAsUpdateV2 : Y.encodeStateAsUpdate;
const merge = v2 ? Y.mergeUpdatesV2 : Y.mergeUpdates;
const diff = v2 ? Y.diffUpdateV2 : Y.diffUpdate;
const vector = v2 ? Y.encodeStateVectorFromUpdateV2 : Y.encodeStateVectorFromUpdate;
const states = sv => [...Y.decodeStateVector(sv)].map(([c,n]) => [String(c),n]);
for (const line of fs.readFileSync(0, 'utf8').trim().split('\n')) {
  const request = JSON.parse(line);
  let result;
  if (process.argv.includes('convert')) {
    result = request.map(s => hex(Y.convertUpdateFormatV1ToV2(bytes(s))));
  } else if (process.argv.includes('utilities')) {
    const merged = merge(request.updates.map(bytes));
    result = {merged: hex(merged), diff: hex(diff(merged, bytes(request.remote))), states: states(vector(merged))};
  } else {
    const docs = Array.from({length: 3}, () => new Y.Doc({gc: process.argv.includes('--gc')}));
    for (const [op, i, data] of request) {
      if (op !== 'a') throw new Error('unsupported operation');
      apply(docs[i], bytes(data));
    }
    result = {states: docs.map(d => states(Y.encodeStateVector(d))), updates: docs.map(d => hex(encode(d)))};
    docs.forEach(d => d.destroy());
  }
  process.stdout.write(JSON.stringify(result)+'\n');
}
