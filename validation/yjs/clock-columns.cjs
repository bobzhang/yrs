const fs = require('node:fs');
const Y = require('yjs');
const decoding = require('lib0/decoding');
for (const line of fs.readFileSync(0, 'utf8').trim().split('\n')) {
  const request = JSON.parse(line);
  const encoder = new Y.UpdateEncoderV2();
  for (const [field, [client, clock]] of request.ops) {
    encoder[field === 'left' ? 'writeLeftID' : 'writeRightID'](Y.createID(Number(client), clock));
  }
  const encoded = [...encoder.toUint8Array()];
  const decoder = new Y.UpdateDecoderV2(decoding.createDecoder(new Uint8Array(request.bytes || encoded)));
  const values = request.ops.map(([field]) => {
    const id = decoder[field === 'left' ? 'readLeftID' : 'readRightID']();
    return [String(id.client), id.clock];
  });
  process.stdout.write(JSON.stringify({encoded, decoded: {values, tail: [...decoding.readTailAsUint8Array(decoder.restDecoder)]}})+'\n');
}
