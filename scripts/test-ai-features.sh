#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temporary=$(mktemp -d -t mbs-ai-features)
clang++ -std=c++17 -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness \
    tests/ai_features_test.mm src/MbsAiPresentation.mm -framework AppKit -framework Security -o "$temporary/test"
MBS_AI_TEST_HOME="$temporary" "$temporary/test" "$temporary/export.pptx"
python3 - "$temporary/export.pptx" <<'PY'
from pathlib import Path
import posixpath
import sys
from zipfile import ZipFile
import xml.etree.ElementTree as ET

with ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    names = set(archive.namelist())
    for name in names:
        if name.endswith(('.xml', '.rels')):
            root = ET.fromstring(archive.read(name))
            if name.endswith('.rels'):
                base = '' if name == '_rels/.rels' else name.rsplit('/_rels/', 1)[0]
                for relationship in root:
                    if relationship.get('TargetMode') != 'External':
                        assert posixpath.normpath(posixpath.join(base, relationship.get('Target'))) in names
    slide = archive.read('ppt/slides/slide1.xml').decode()
    assert '测试 &amp; &lt;标题&gt;' in slide and '事实二' in slide
print('PASS exported PPTX XML, relationships, editable text and ZIP integrity')
PY
