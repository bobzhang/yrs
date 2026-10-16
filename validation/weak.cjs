const fs=require('node:fs');
const {evaluate}=require('../_build/js/release/build/validation/weak/weak.js');
for(const line of fs.readFileSync(0,'utf8').trim().split('\n')) console.log(evaluate(line,process.argv.includes('v2'),process.argv.includes('gc'),process.argv.includes('raw-bounds')));
