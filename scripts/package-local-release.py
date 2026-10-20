#!/usr/bin/env python3
"""Stage a local full app and a self-developed-only module update. No uploads."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--app', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
args = p.parse_args()
repo = Path(__file__).resolve().parent.parent
version = (repo/'VERSION').read_text().strip()
assert not args.work.exists(), 'Use a new release work directory'
args.work.mkdir()
source = args.app.resolve()
outer = plistlib.loads((source/'Contents/Info.plist').read_bytes())
assert outer['CFBundleShortVersionString'] == '0.1.18', 'This package supports the verified 0.1.18 baseline only'
stage = args.work/'dmg-root'
stage.mkdir()
app = stage/'Mbs Office.app'
subprocess.run(['/bin/cp','-cRp',str(source),str(app)],check=True)
paths = {'Contents/Resources/MbsEngine.app/Contents/MacOS/MbsOfflineFlags.dylib':repo/'build/MbsOfflineFlags.dylib',
         'Contents/Resources/MbsModuleInstaller':repo/'build/MbsModuleInstaller'}
for name, file in paths.items():
    shutil.copy2(file,app/name)
    subprocess.run(['codesign','--force','--sign','-',str(app/name)],check=True)
outer['CFBundleShortVersionString'] = version
outer['CFBundleVersion'] = str(int(outer['CFBundleVersion'])+1)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(outer))
engine = app/'Contents/Resources/MbsEngine.app'
inner = plistlib.loads((engine/'Contents/Info.plist').read_bytes())
inner['MbsModuleVersion'] = version
(engine/'Contents/Info.plist').write_bytes(plistlib.dumps(inner))
for target in [engine,app]:
    subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
(stage/'Applications').symlink_to('/Applications')
(stage/'修复说明.txt').write_text((repo/f'release-notes/{version}.md').read_text(),encoding='utf-8')
assets = args.work/'assets'
assets.mkdir()
payload = {name:(app/name).read_bytes() for name in paths}
manifest = {'format':'mbs-modules-v1','fromVersion':'0.1.18','toVersion':version,
            'files':[{'path':name,'sha256':hashlib.sha256(data).hexdigest()} for name,data in payload.items()]}
package = assets/f'MbsOffice-modules-{version}-from-0.1.18.zip'
with zipfile.ZipFile(package,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for name,data in {'manifest.json':(json.dumps(manifest,sort_keys=True)+'\n').encode(),**payload}.items():
        entry = zipfile.ZipInfo(name,(2020,1,1,0,0,0))
        entry.create_system = 3
        entry.external_attr = (0o100644 if name == 'manifest.json' else 0o100755)<<16
        entry.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(entry,data)
shutil.copy2(app/'Contents/Resources/MbsModuleInstaller',assets/f'MbsModuleInstaller-{version}')
(assets/'manifests.json').write_text(json.dumps([manifest],indent=2)+'\n')
print(json.dumps({'app':str(app),'package':str(package),'version':version}))
