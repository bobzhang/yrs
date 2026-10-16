const fs=require('node:fs');
const bridge=require('../_build/js/release/build/validation/typed_v2/typed_v2.js');
for(const line of fs.readFileSync(0,'utf8').trim().split('\n')) console.log(bridge.evaluate(line));
