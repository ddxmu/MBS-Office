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
p.add_argument('--from-version', required=True)
p.add_argument('--full-only', action='store_true', help='Stage the complete app without creating a module-only update')
args = p.parse_args()
repo = Path(__file__).resolve().parent.parent
version = (repo/'VERSION').read_text().strip()
assert not args.work.exists(), 'Use a new release work directory'
args.work.mkdir()
source = args.app.resolve()
outer = plistlib.loads((source/'Contents/Info.plist').read_bytes())
assert outer['CFBundleShortVersionString'] == args.from_version, 'Installed app does not match the requested baseline'
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
subprocess.run(['python3',str(repo/'scripts/refresh-branding.py'),str(app)],check=True)
res = 'Contents/Resources/MbsEngine.app/Contents/Resources/office6/res/'
ribbon_paths = [res+'wppongmani.kui',res+'commands/wpp/ongmani/CT_MbsAI.kuip']
subprocess.run(['python3',str(repo/'scripts/configure-presentation-ai.py'),str(app)],check=True)
if not args.full_only and any((source/path).read_bytes() != (app/path).read_bytes() for path in ribbon_paths):
    p.error('Presentation ribbon changes require --full-only; a module-only update cannot apply these UI changes.')
inner = plistlib.loads((engine/'Contents/Info.plist').read_bytes())
inner['MbsModuleVersion'] = version
(engine/'Contents/Info.plist').write_bytes(plistlib.dumps(inner))
for target in [engine,app]:
    subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
(stage/'Applications').symlink_to('/Applications')
(stage/'修复说明.txt').write_text((repo/f'release-notes/{version}.md').read_text(),encoding='utf-8')
if args.full_only:
    print(json.dumps({'app':str(app),'package':None,'version':version,'fullOnly':True}))
    raise SystemExit(0)
assets = args.work/'assets'
assets.mkdir()
payload = {name:(app/name).read_bytes() for name in paths}
manifest = {'format':'mbs-modules-v1','fromVersion':args.from_version,'toVersion':version,
            'files':[{'path':name,'sha256':hashlib.sha256(data).hexdigest()} for name,data in payload.items()]}
package = assets/f'MbsOffice-modules-{version}-from-{args.from_version}.zip'
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
