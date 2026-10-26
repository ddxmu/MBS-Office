#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mbs_baseline=${1:-'/Applications/Mbs Office.app'}
mbs_tmp=$(mktemp -d -t mbs-brand-resource)
trap 'rm -rf "$mbs_tmp"' EXIT HUP INT TERM
python3 scripts/build-branding-resource.py
mbs_frameworks="$mbs_baseline/Contents/Resources/MbsEngine.app/Contents/Frameworks/office6"
clang++ -std=c++17 -fobjc-arc tests/native_brand_resource_test.mm -framework Foundation \
  -F"$mbs_frameworks" -framework QtCoreKso -Wl,-rpath,"$mbs_frameworks" -o "$mbs_tmp/check"
clang++ -std=c++17 -dynamiclib src/MbsBrandResources.mm -F"$mbs_frameworks" -framework QtCoreKso \
  -Wl,-rpath,"$mbs_frameworks" -Wl,-sectcreate,__TEXT,__mbs_brand,build/mbs-wordmark.rcc -o "$mbs_tmp/branding.dylib"
python3 - "$mbs_baseline" "$mbs_tmp" <<'PY'
from pathlib import Path
import runpy,subprocess,sys,xml.etree.ElementTree as ET,zlib
m=runpy.run_path('scripts/refresh-branding.py')
base=Path(sys.argv[1])/'Contents/Resources/MbsEngine.app/Contents/Resources/office6'
temporary=Path(sys.argv[2]); originals=[str(base/p) for p in m['RESOURCE_PATHS']]
originals.append(str(base/'mui/default/prometheus_kso_res.rcc'))
source={p:(zlib.decompress(raw[4:]) if flags&1 else raw)
        for p,_,flags,raw in m['entries'](Path(originals[-1]).read_bytes())}
ns={'svg':'http://www.w3.org/2000/svg'}
icon=ET.parse('assets/mbs-resource-icons/tpdocerresourceshop.svg').getroot()
paths=icon.findall('svg:path',ns)
assert len(paths)==1
assert paths[0].get('d')==ET.fromstring(source['/icons_svg/16x16/tpdocerresourceshop.svg']).find('svg:path',ns).get('d')
assert len(icon.findall('.//svg:circle',ns))==3
archive={p for p,_,_,_ in m['entries'](Path('build/mbs-wordmark.rcc').read_bytes())}
assert '/icons_svg/16x16/tpdocerresourceshop.svg' in archive
assert not any(p.endswith('/ChangeTheme.svg') or p.endswith('/ChangeThemeStatusBar.svg') for p in archive)
entry=('/icons_svg/16x16/ChangeThemeStatusBar.svg',source['/icons_svg/16x16/ChangeThemeStatusBar.svg'])
(temporary/'unrelated.bin').write_bytes(entry[1])
for first in ['build/mbs-wordmark.rcc',str(temporary/'branding.dylib')]:
    subprocess.run([str(temporary/'check'),first,'assets/mbs-wordmark.svg','assets/mbs-wordmark-paths.json',
                    *originals,entry[0],str(temporary/'unrelated.bin')],check=True)
PY
