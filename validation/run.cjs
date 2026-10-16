const fs = require('node:fs');
const readline = require('node:readline');
const bridge = require('../_build/js/release/build/validation/bridge/bridge.js');
const name = process.argv.includes('utilities') ? 'utilities' : 'evaluate';
const evaluate = bridge[name + (process.argv.includes('v2') ? '_v2' : '') + (process.argv.includes('--gc') ? '_gc' : '')];
async function main() {
  const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of lines) {
    if (!line.trim()) continue;
    // Oracle results can be large. Synchronous writes apply pipe backpressure;
    // console.log queues the entire run when Python cannot drain it fast enough.
    fs.writeSync(1, evaluate(line) + '\n');
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
