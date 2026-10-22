#!/usr/bin/env python3
"""Configure the local app's presentation ribbon to use Mbs-owned AI commands."""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ACTIONS = [
    ('MbsAiPpt', 'AI 生成 PPT', 'NewSlide'),
    ('MbsAiDocumentPpt', '文档生成 PPT', 'InsertTextboxHorizontal'),
    ('MbsAiOutlinePpt', '大纲生成 PPT', 'NewSlideFromOutline'),
    ('MbsAiSlide', 'AI 生成单页', 'NewSlide'),
    ('MbsAiSlides', 'AI 生成多页', 'Duplicate'),
    ('MbsAiImage', 'AI 生成图片', 'InsertPicture'),
    ('MbsAiWrite', '帮我写', 'AiPolish'),
    ('MbsAiRewrite', '帮我改', 'AiPolish'),
    ('MbsAiExpand', '扩写', 'IncreaseSpace'),
    ('MbsAiShorten', '缩写', 'DecreaseSpace'),
    ('MbsAiPolish', '润色', 'AiPolish'),
    ('MbsAiMore', '发现更多', 'Options'),
    ('MbsAiHistory', '历史会话', 'RecentFile'),
    ('MbsAiSettings', '设置', 'Options'),
]

def configure(app):
    res = app / 'Contents/Resources/MbsEngine.app/Contents/Resources/office6/res'
    shell = res / 'wppongmani.kui'
    original = shell.read_text()
    root = ET.fromstring(original)
    assert len([e for e in root.iter() if e.get('id') == 'CT_MbsAI']) == 1
    text = re.sub(r'^.*<KRbTabProxyCommand\b[^\n]*\bid="CT_Copilot"[^\n]*/>\s*\n', '', original, flags=re.M)
    text = re.sub(r'^.*<KAlwaysShowSeparatorCommand\b[^\n]*\bidKey="WppCopilotAI"[^\n]*/>\s*\n', '', text, flags=re.M)
    ET.fromstring(text)
    assert 'id="CT_Copilot"' not in text
    ribbon = ET.Element('shell', component='wpp', tc='mbs.ai')
    commands = ET.SubElement(ribbon, 'commands')
    for identifier, title, icon in ACTIONS:
        ET.SubElement(commands, 'KTriggerCommand', id=identifier, text=title, icon=icon)
    groups = [
        ('MbsAiGenerate', '生成演示', [a[0] for a in ACTIONS[:6]]),
        ('MbsAiWriting', '写作', [a[0] for a in ACTIONS[6:11]]),
        ('MbsAiService', 'AI 服务', [a[0] for a in ACTIONS[11:]]),
    ]
    for identifier, title, actions in groups:
        group = ET.SubElement(commands, 'KListCommand', controlType='16', id=identifier, text=title)
        for action in actions:
            ET.SubElement(group, 'command', idQ=action)
    subcommands = ET.SubElement(ribbon, 'subcommands')
    tab = ET.SubElement(subcommands, 'subcommand', id='CT_MbsAI')
    for identifier, _, _ in groups:
        ET.SubElement(tab, 'command', idQ=identifier)
    ET.indent(ribbon, space='    ')
    output = res / 'commands/wpp/ongmani/CT_MbsAI.kuip'
    output.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(ribbon, encoding='unicode') + '\n')
    shell.write_text(text)
    print('Configured one presentation AI tab with 14 Mbs commands')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    configure(parser.parse_args().app)
