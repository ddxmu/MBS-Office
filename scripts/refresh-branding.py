#!/usr/bin/env python3
"""Replace only the Mbs homepage wordmark in a stopped, staged application."""
import argparse
import json
from pathlib import Path
import struct

RESOURCE_PATHS = [
    'mui/default/prometheus_shared_res.rcc',
    'skins/2018white_vip/default/prometheus_wpsoffice_res.rcc',
    'skins/2018white_dark/default/prometheus_wpsoffice_res.rcc',
    'skins/2018white_dark_vip/default/prometheus_wpsoffice_res.rcc',
]


def entries(data):
    if data[:4] != b'qres':
        raise ValueError('Invalid RCC header')
    version, tree, payload, names = struct.unpack_from('>4I', data, 4)
    if version not in (1, 2) or not 20 <= payload <= names <= tree <= len(data):
        raise ValueError('Unsupported RCC layout')
    stride = 22 if version == 2 else 14

    def walk(index, parent=''):
        pos = tree + index * stride
        name_offset, flags = struct.unpack_from('>IH', data, pos)
        path = parent
        if index:
            npos = names + name_offset
            length = struct.unpack_from('>H', data, npos)[0]
            path += '/' + data[npos + 6:npos + 6 + length * 2].decode('utf-16be')
        if flags & 2:
            count, first = struct.unpack_from('>II', data, pos + 6)
            for child in range(first, first + count):
                yield from walk(child, path)
        else:
            offset = payload + struct.unpack_from('>I', data, pos + 10)[0]
            size = struct.unpack_from('>I', data, offset)[0]
            yield path, pos, flags, data[offset + 4:offset + 4 + size]

    return list(walk(0))


def replace_wordmark(original, artwork):
    before = entries(original)
    selected = [e for e in before if b'Mbs Office</text>' in e[3] or b'id="mbs-wordmark"' in e[3]]
    if not selected:
        raise ValueError('Expected an existing Mbs wordmark')
    if all(e[3] == artwork for e in selected):
        return original
    result = bytearray(original)
    _, tree, payload, names = struct.unpack_from('>4I', result, 4)
    extra = struct.pack('>I', len(artwork)) + artwork
    for _, pos, flags, _ in selected:
        struct.pack_into('>H', result, pos + 4, flags & ~1)
        struct.pack_into('>I', result, pos + 10, names - payload)
    result = result[:names] + extra + result[names:]
    struct.pack_into('>I', result, 8, tree + len(extra))
    struct.pack_into('>I', result, 16, names + len(extra))
    after = {p: raw for p, _, _, raw in entries(result)}
    targets = {p for p, _, _, _ in selected}
    assert after.keys() == {p for p, _, _, _ in before}
    assert all(after[p] == (artwork if p in targets else raw) for p, _, _, raw in before)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    root = args.app / 'Contents/Resources/MbsEngine.app/Contents/Resources/office6'
    artwork = (Path(__file__).resolve().parent.parent / 'assets/mbs-wordmark.svg').read_bytes()
    changed = []
    for relative in RESOURCE_PATHS:
        path = root / relative
        original = path.read_bytes()
        result = replace_wordmark(original, artwork)
        if result != original:
            path.write_bytes(result)
            changed.append(relative)
    print(json.dumps({'changed': changed}))
