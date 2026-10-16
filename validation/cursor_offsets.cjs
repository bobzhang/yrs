const fs = require('node:fs');
const { evaluate } = require('../_build/js/release/build/validation/cursor_offsets/cursor_offsets.js');
for (const line of fs.readFileSync(0, 'utf8').trim().split('\n')) console.log(evaluate(line));
