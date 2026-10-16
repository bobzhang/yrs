// Keep the reference's capture clock deterministic, before lib0 caches Date.now.
let tick = 100;
Date.now = () => tick;
// lib0 logs mirrored client-ID reassignment through console.log. Keep protocol
// stdout reserved for JSON while retaining those diagnostics on stderr.
console.log = (...args) => console.error(...args);
const Y = require('yjs');
const readline = require('node:readline');
const v2 = process.argv.includes('v2');
const gc = process.argv.includes('--gc');
const apply = v2 ? Y.applyUpdateV2 : Y.applyUpdate;
const encode = v2 ? Y.encodeStateAsUpdateV2 : Y.encodeStateAsUpdate;
const docs = [1, 2, 3].map(clientID => {
  const doc = new Y.Doc({gc});
  doc.clientID = clientID;
  return doc;
});
const roots = docs.map(d => d.getMap('root'));
const xmls = docs.map(d => d.getXmlFragment('xml'));
const texts = docs.map(d => d.getText('text'));
const managers = docs.map((_, i) => new Y.UndoManager([roots[i], xmls[i], texts[i]], {
  captureTimeout: 500, trackedOrigins: new Set(['user'])
}));
let notifications = [];
const value = v => v instanceof Y.AbstractType ? v.toJSON() : v;
function delta(ops) {
  return ops.map(op => {
    const out = {...op};
    if ('insert' in out) out.insert = Array.isArray(out.insert) ? out.insert.map(value) : value(out.insert);
    if (out.attributes && !Object.keys(out.attributes).length) delete out.attributes;
    return out;
  });
}
function keys(event) {
  const out = {};
  for (const [key, change] of event.changes.keys) {
    const row = {action: change.action};
    if (change.action !== 'add') row.old_value = value(change.oldValue);
    if (change.action !== 'delete') row.new_value = value(event.target instanceof Y.Map
      ? event.target.get(key) : event.target.getAttribute(key));
    out[key] = row;
  }
  return out;
}
function event(e) {
  const row = {path: e.path, target: value(e.target)};
  if (e.target instanceof Y.XmlText) Object.assign(row, {kind: 'xmltext', delta: delta(e.delta), keys: keys(e)});
  else if (e.target instanceof Y.XmlFragment) Object.assign(row, {kind: 'xml', delta: delta(e.changes.delta), keys: keys(e), children: e.childListChanged});
  else if (e.target instanceof Y.Text) Object.assign(row, {kind: 'text', delta: delta(e.delta)});
  else if (e.target instanceof Y.Array) Object.assign(row, {kind: 'array', delta: delta(e.changes.delta)});
  else if (e.target instanceof Y.Map) Object.assign(row, {kind: 'map', keys: keys(e)});
  else throw new Error('unknown event target');
  return row;
}
for (let i = 0; i < docs.length; i++) {
  roots[i].observeDeep(es => notifications.push({doc: i, scope: 'map', events: es.map(event)}));
  xmls[i].observeDeep(es => notifications.push({doc: i, scope: 'xml', events: es.map(event)}));
  xmls[i].observe(e => notifications.push({doc: i, scope: 'shallow', delta: delta(e.changes.delta), keys: keys(e), children: e.childListChanged}));
}
function xmlSnapshot(node) {
  if (node instanceof Y.XmlText) return {text: node.toString(), attributes: node.getAttributes()};
  if (node instanceof Y.XmlElement) return {tag: node.nodeName, attributes: node.getAttributes(), children: node.toArray().map(xmlSnapshot)};
  return {children: node.toArray().map(xmlSnapshot)};
}
function tree(root, key) {
  const m = new Y.Map(); root.set(key, m);
  const t = new Y.Text(); m.set('title', t); t.insert(0, 'hello');
  const list = new Y.Array(); m.set('list', list);
  const row = new Y.Map(); list.insert(0, [row]); row.set('done', false);
}
function batch(x, ops) {
  docs[x].transact(() => {
    for (const [op, n] of ops) {
      const key = `key${n % 3}`, text = texts[x], root = roots[x], xml = xmls[x];
      if (op === 'i') text.insert(n % (text.length + 1), 'abc');
      else if (op === 'd' || op === 'f') {
        const p = n % (text.length + 1), count = Math.floor(n / 3) % (text.length - p + 1);
        if (op === 'd') text.delete(p, count);
        else text.format(p, count, {bold: n % 2 === 0});
      } else if (op === 'm') root.set(key, n);
      else if (op === 'new') tree(root, key);
      else if (op === 'remove') root.delete(key);
      else if (op === 'edit' || op === 'shift') {
        const m = root.get(key);
        if (m instanceof Y.Map) {
          const t = m.get('title'), a = m.get('list');
          if (t instanceof Y.Text) t.insert(n % (t.length + 1), '!');
          if (a instanceof Y.Array) {
            const row = a.toArray().find(v => v instanceof Y.Map);
            if (row) row.set('done', true);
            a.insert(op === 'shift' ? 0 : a.length, [n]);
          }
        }
      } else if (op === 'xnew') {
        const e = new Y.XmlElement('p'); xml.insert(n % (xml.length + 1), [e]);
        e.setAttribute('class', 'entry');
        const t = new Y.XmlText(); e.insert(0, [t]); t.insert(0, 'hello');
      } else if (op === 'xremove') {
        if (xml.length) xml.delete(n % xml.length, 1);
      } else if (op === 'xedit') {
        const e = xml.length ? xml.get(n % xml.length) : null;
        if (e instanceof Y.XmlElement) {
          e.setAttribute('class', `c${n}`);
          const t = e.get(0);
          if (t instanceof Y.XmlText) {t.setAttribute('lang', 'en'); t.insert(n % (t.length + 1), '!');}
        }
      } else throw new Error(`unknown operation ${op}`);
    }
  }, 'user');
}
function snapshot(result) {
  return {result, notifications, stacks: managers.map(m => [m.undoStack.length, m.redoStack.length]),
    docs: docs.map((_, i) => ({map: roots[i].toJSON(), xml: xmls[i].toString(),
      xml_nodes: xmls[i].toArray().map(xmlSnapshot), text: texts[i].toString(),
      delta: texts[i].toDelta().map(d => ({insert: value(d.insert), attributes: d.attributes || null}))}))};
}
function run(commands) {
  const snapshots = [];
  for (const [op, x, arg] of commands) {
    notifications = [];
    let result = null;
    if (op === 'apply') apply(docs[x], Buffer.from(arg, 'hex'));
    else if (op === 'sync') apply(docs[arg], encode(docs[x], Y.encodeStateVector(docs[arg])));
    else if (op === 'undo') result = managers[x].undo() !== null;
    else if (op === 'redo') result = managers[x].redo() !== null;
    else if (op === 'reset') managers[x].stopCapturing();
    else if (op === 'clear') managers[x].clear();
    else if (op === 'tick') tick += arg;
    else if (op === 'batch') batch(x, arg);
    else throw new Error(`unknown command ${op}`);
    snapshots.push(snapshot(result));
  }
  if (!snapshots.length) {notifications = []; snapshots.push(snapshot(null));}
  return {snapshots, updates: docs.map(d => Buffer.from(encode(d)).toString('hex'))};
}
readline.createInterface({input: process.stdin}).on('line', line => {
  try {process.stdout.write(JSON.stringify(run(JSON.parse(line))) + '\n');}
  catch (error) {console.error(error.stack); process.exitCode = 1; process.stdout.write(JSON.stringify({error: error.message}) + '\n');}
});
