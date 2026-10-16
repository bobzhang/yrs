const fs=require('node:fs');
const bridge=require('../_build/js/release/build/validation/undo/undo.js');
const evaluate=process.argv.includes('--gc') ? (line => bridge.evaluate_gc(line,process.argv.includes('v2'))) : bridge[process.argv.includes('v2')?'evaluate_v2':'evaluate'];
for(const line of fs.readFileSync(0,'utf8').trim().split('\n')) console.log(evaluate(line));
