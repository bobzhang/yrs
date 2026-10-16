const Y = require('yjs');
const doc = new Y.Doc({gc:false});
const text = doc.getText('text');
text.insert(0, '🦀');
text.format(1, 1, {bold:true});
const formatted = text.toDelta();
text.delete(1, 1);
console.log(JSON.stringify({formatted, deleted:text.toDelta()}));
