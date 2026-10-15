const fs = require('node:fs');
const bridge = require('../_build/js/release/build/validation/bridge/bridge.js');
const name = process.argv.includes('utilities') ? 'utilities' : 'evaluate';
const evaluate = bridge[name + (process.argv.includes('v2') ? '_v2' : '') + (process.argv.includes('--gc') ? '_gc' : '')];
for (const line of fs.readFileSync(0, 'utf8').trim().split('\n')) console.log(evaluate(line));
