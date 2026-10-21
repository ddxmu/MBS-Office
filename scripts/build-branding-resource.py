#!/usr/bin/env python3
"""Build an RCC containing only the self-owned Mbs wordmark and its aliases."""
import json
from pathlib import Path
import struct

repo = Path(__file__).resolve().parent.parent
spec = json.loads((repo/'assets/mbs-wordmark-paths.json').read_text())
artwork = (repo/'assets/mbs-wordmark.svg').read_bytes()
root = {'name': '', 'children': {}}
for path in spec['paths']:
    node = root
    for name in path.strip('/').split('/'):
        node = node['children'].setdefault(name, {'name': name, 'children': {}})
    node['file'] = True
nodes = [root]
for node in nodes:
    children = sorted(node['children'].values(), key=lambda child: spec['nameHashes'][child['name']])
    node['first'] = len(nodes)
    nodes.extend(children)
names = bytearray()
offsets = {}
for node in nodes:
    name = node['name']
    if name not in offsets:
        offsets[name] = len(names)
        names.extend(struct.pack('>HI', len(name), spec['nameHashes'].get(name, 0)))
        names.extend(name.encode('utf-16be'))
tree = bytearray()
for node in nodes:
    tree.extend(struct.pack('>IH', offsets[node['name']], 0 if node.get('file') else 2))
    tree.extend(struct.pack('>HHI', 0, 1, 0) if node.get('file') else
                struct.pack('>II', len(node['children']), node['first']))
payload = struct.pack('>I', len(artwork)) + artwork
data = b'qres' + struct.pack('>4I', 1, 20+len(payload)+len(names), 20, 20+len(payload))
output = repo/'build/mbs-wordmark.rcc'
output.parent.mkdir(exist_ok=True)
output.write_bytes(data+payload+names+tree)
