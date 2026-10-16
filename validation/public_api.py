#!/usr/bin/env python3
"""Inventory the pinned public Rust API from rustdoc, not source-text regexes.

This records declarations, not conformance. Trait implementations supplied by
Rust's standard library, blanket implementations, and private internals are not
counted as public declarations. Public trait members and inherent methods are.
"""
import argparse
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = 'ac339600c712642e556895426113c3f9c117de39'
REFERENCE_DIR = ROOT / '.repos/y-crdt'
OUTPUT = ROOT / 'validation/public-api-inventory.json'


def inventory(document):
    index = document['index']
    exports = {}
    def walk(item_id, path, ancestors=()):
        item = index.get(str(item_id))
        if item is None or item['crate_id'] != 0 or item_id in ancestors:
            return
        kind, detail = next(iter(item['inner'].items()))
        if kind == 'use':
            if detail['is_glob']:
                walk(detail['id'], path, ancestors + (item_id,))
            else:
                walk(detail['id'], path + [detail['name']], ancestors + (item_id,))
            return
        if kind == 'module':
            for child_id in detail['items']:
                child = index[str(child_id)]
                if child['visibility'] == 'public':
                    child_path = path if 'use' in child['inner'] else path + [child['name']]
                    walk(child_id, child_path, ancestors + (item_id,))
        else:
            exports.setdefault(str(item_id), set()).add('::'.join(path))

    walk(document['root'], ['yrs'])
    rows = []
    for item_id, paths in exports.items():
        item = index[item_id]
        kind, detail = next(iter(item['inner'].items()))
        # Prefer the shortest public alias; retain every module-qualified alias.
        aliases = sorted(paths, key=lambda path: (path.count('::'), path))
        members = []
        def add_member(member_id, context):
            member = index[str(member_id)]
            member_kind = next(iter(member['inner']))
            span = member['span']
            members.append({'name': member['name'], 'kind': member_kind,
                            'context': context,
                            'source': None if span is None else f"{span['filename']}:{span['begin'][0]}"})
        if kind == 'trait':
            for member in detail['items']:
                add_member(member, 'trait')
        if kind == 'enum':
            for member in detail['variants']:
                add_member(member, 'variant')
        if kind == 'struct' and isinstance(detail['kind'], dict):
            if 'plain' in detail['kind']:
                fields = detail['kind']['plain']['fields']
            else:
                fields = detail['kind'].get('tuple', [])
            for member in fields:
                if member is not None and index[str(member)]['visibility'] == 'public':
                    add_member(member, 'field')
        for impl_id in (detail.get('impls', []) if isinstance(detail, dict) else []):
            implementation = index[str(impl_id)]['inner']['impl']
            if implementation['trait'] is None:
                for member in implementation['items']:
                    if index[str(member)]['visibility'] == 'public':
                        add_member(member, 'inherent')
        span = item['span']
        rows.append({'path': aliases[0], 'aliases': sorted(aliases), 'kind': kind,
                     'source': None if span is None else f"{span['filename']}:{span['begin'][0]}",
                     'members': sorted(members, key=lambda m: (m['context'], m['name'] or ''))})
    return {'upstream': REFERENCE, 'rust_version': '1.97.1', 'features': ['weak'],
            'scope': 'Public declarations, inherent methods, trait members, public fields and variants; not a semantic compatibility report.',
            'declarations': sorted(rows, key=lambda row: row['path'])}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if the committed inventory differs')
    parser.add_argument('--cached', action='store_true', help='Read already-generated rustdoc JSON')
    args = parser.parse_args()
    head = subprocess.check_output(['git', '-C', str(REFERENCE_DIR), 'rev-parse', 'HEAD'], text=True).strip()
    assert head == REFERENCE, f'Unexpected reference: {head}'
    assert not subprocess.check_output(['git', '-C', str(REFERENCE_DIR), 'diff', '--name-only', 'HEAD', '--', 'yrs/src'], text=True).strip(), 'Reference source is modified'
    if not args.cached:
        # Stable rustdoc gates JSON output. Bootstrap is limited to this docs
        # subprocess; reference production/test binaries keep their normal flags.
        env = dict(os.environ, RUSTC_BOOTSTRAP='1')
        subprocess.run(['cargo', '+1.97.1', 'rustdoc', '--locked', '--manifest-path',
                        str(REFERENCE_DIR / 'yrs/Cargo.toml'), '--features', 'weak', '--lib',
                        '--', '-Z', 'unstable-options', '--output-format', 'json'],
                       cwd=ROOT, env=env, check=True)
    document = json.loads((REFERENCE_DIR / 'target/doc/yrs.json').read_text())
    result = inventory(document)
    encoded = json.dumps(result, indent=2) + '\n'
    if args.check:
        assert OUTPUT.read_text() == encoded, 'Public API inventory changed; regenerate and review it'
    else:
        OUTPUT.write_text(encoded)
    rows = result['declarations']
    print(json.dumps({'declarations': len(rows), 'members': sum(len(row['members']) for row in rows),
                      'status': 'inventory verified' if args.check else 'inventory generated'}))


if __name__ == '__main__':
    main()
