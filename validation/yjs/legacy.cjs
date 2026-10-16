const fs = require('node:fs');
const Y = require('yjs');
const v2 = process.argv.includes('v2');
const replay = process.argv.includes('replay');
for (const line of fs.readFileSync(0,'utf8').trim().split('\n')) {
  const packet = Buffer.from(JSON.parse(line), 'hex');
  const source = v2 && !replay ? Y.convertUpdateFormatV1ToV2(packet) : packet;
  const doc = new Y.Doc({gc:false});
  (v2 ? Y.applyUpdateV2 : Y.applyUpdate)(doc, source);
  const array = doc.getArray('items');
  const before = array.toJSON();
  if (!replay) array.delete(1,1);
  console.log(JSON.stringify({before,after:array.toJSON(),source:Buffer.from(source).toString('hex')}));
}
