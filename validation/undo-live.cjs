const readline = require('node:readline');
const bridge = require('../_build/js/release/build/validation/undo/undo.js');
const v2 = process.argv.includes('v2');
const lines = readline.createInterface({input:process.stdin});
lines.on('line', line => { console.log(bridge.evaluate_live(line, v2)); });
