#!/usr/bin/env python3
"""Build the self-owned Mbs wordmark, AI and resource icon archive."""
import json
from pathlib import Path
import struct

repo = Path(__file__).resolve().parent.parent
spec = json.loads((repo/'assets/mbs-wordmark-paths.json').read_text())
artwork = (repo/'assets/mbs-wordmark.svg').read_bytes()
files = {path: artwork for path in spec['paths']}
for icon in sorted((repo/'assets/mbs-ai-icons').glob('*.svg')):
    for size in (16, 24, 32):
        files[f'/icons_svg/{size}x{size}/{icon.name}'] = icon.read_bytes()
files['/icons_svg/16x16/tpdocerresourceshop.svg'] = (
    repo/'assets/mbs-resource-icons/tpdocerresourceshop.svg').read_bytes()

def name_hash(value):
    result = 0
    for character in value:
        result = (result << 4) + ord(character)
        result ^= (result & 0xf0000000) >> 23
        result &= 0x0fffffff
    return result

assert all(name_hash(name) == value for name, value in spec['nameHashes'].items())
root = {'name': '', 'children': {}}
for path, content in files.items():
    node = root
    for name in path.strip('/').split('/'):
        node = node['children'].setdefault(name, {'name': name, 'children': {}})
    node['content'] = content
nodes = [root]
for node in nodes:
    children = sorted(node['children'].values(), key=lambda child: (name_hash(child['name']), child['name']))
    node['first'] = len(nodes)
    nodes.extend(children)
names = bytearray()
offsets = {}
for node in nodes:
    name = node['name']
    if name not in offsets:
        offsets[name] = len(names)
        names.extend(struct.pack('>HI', len(name), name_hash(name)))
        names.extend(name.encode('utf-16be'))
tree = bytearray()
payload = bytearray()
contents = {}
for node in nodes:
    is_file = 'content' in node
    tree.extend(struct.pack('>IH', offsets[node['name']], 0 if is_file else 2))
    if is_file:
        content = node['content']
        if content not in contents:
            contents[content] = len(payload)
            payload.extend(struct.pack('>I', len(content)) + content)
        tree.extend(struct.pack('>HHI', 0, 1, contents[content]))
    else:
        tree.extend(struct.pack('>II', len(node['children']), node['first']))
data = b'qres' + struct.pack('>4I', 1, 20+len(payload)+len(names), 20, 20+len(payload))
output = repo/'build/mbs-wordmark.rcc'
output.parent.mkdir(exist_ok=True)
output.write_bytes(data+payload+names+tree)
