#!/usr/bin/env python3
"""Check that the reviewed CRDT contract accounts for every pinned public declaration/member."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
inventory = json.loads((ROOT / 'validation/public-api-inventory.json').read_text())
contract = json.loads((ROOT / 'validation/api-contract.json').read_text())
assert contract['reference'] == inventory['upstream']
expected = {d['path']: [m['name'] for m in d['members']] for d in inventory['declarations']}
seen = {}
for name, group in contract['groups'].items():
    assert group['surface'] and group['adaptation'] and group['evidence'], name
    for evidence in group['evidence']:
        assert (ROOT / evidence).is_file(), (name, evidence)
    for path, members in group['declarations'].items():
        assert path not in seen, ('duplicate disposition', path)
        assert expected.get(path) == members, ('unreviewed declaration/member change', path)
        seen[path] = members
assert seen == expected, ('unreviewed declarations', set(expected) - set(seen))
print(f'CRDT API audit: {len(seen)} declarations, {sum(map(len, seen.values()))} members, '
      f'{len(contract["groups"])} capability/adaptation groups accounted for')
print('This is a completeness checklist; semantic evidence comes from the linked tests and oracles.')
