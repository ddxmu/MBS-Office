#!/usr/bin/env python3
"""Assign Mbs-owned AI ribbon icons without changing commands or actions."""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

def configure(app):
    resources = app / 'Contents/Resources/MbsEngine.app/Contents/Resources/office6/res/commands'
    assets = Path(__file__).resolve().parent.parent / 'assets/mbs-ai-icons'
    for component in ('wps', 'et', 'wpp'):
        path = resources / component / 'ongmani/CT_MbsAI.kuip'
        original = path.read_text()
        before = ET.fromstring(original)
        def replace(match):
            tag = match.group(0)
            command = ET.fromstring(tag).get('id')
            icon = {'MbsLocalAccount': 'MbsAiAccount', 'MbsUpdates': 'MbsAiUpdates'}.get(command, command)
            assert (assets / f'{icon}.svg').is_file(), f'Missing icon: {icon}'
            return re.sub(r'\bicon="[^"]*"', f'icon="{icon}"', tag)
        changed = re.sub(r'<KTriggerCommand\b[^>]+/>', replace, original)
        after = ET.fromstring(changed)
        for old, new in zip(before.iter(), after.iter()):
            old.attrib.pop('icon', None)
            new.attrib.pop('icon', None)
        assert ET.tostring(before) == ET.tostring(after), 'Only icons may change'
        if changed != original:
            path.write_text(changed)
        print(f'{component}: AI icons configured')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    configure(parser.parse_args().app)
