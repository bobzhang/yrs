const fs=require('node:fs');
const bridge=require('../_build/js/release/build/validation/transactions/transactions.js');
const evaluate=bridge[process.argv.includes('v2')?'evaluate_v2':'evaluate'];
for(const line of fs.readFileSync(0,'utf8').trim().split('\n')) console.log(evaluate(line));
