const fs = require('node:fs');
const { evaluate } = require('../_build/js/release/build/validation/traces/traces.js');
const input = fs.readFileSync(process.argv[2], 'utf8');
console.log(evaluate(input));
