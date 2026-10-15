const fs=require('node:fs');
const bridge=require('../_build/js/release/build/validation/presence/presence.js');
for(const line of fs.readFileSync(0,'utf8').trim().split('\n')) console.log(bridge.evaluate(line));
