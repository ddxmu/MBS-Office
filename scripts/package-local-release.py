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
p.add_argument('--authorization-base-library', type=Path,
               help='Audited original libauth used to build the website-only manager adapter; requires --full-only')
p.add_argument('--native-state-routing',action='store_true',
               help='Route the inspected original login/trial/license state methods to Mbs')
p.add_argument('--account-authorization-base-library',type=Path,
               help='Audited original ksolite used to route native account login/logout and authorization queries')
args = p.parse_args()
if (args.authorization_base_library or args.account_authorization_base_library) and not args.full_only:
    p.error('Native authorization changes require --full-only; a module-only update cannot apply them.')
if args.native_state_routing and not (args.authorization_base_library and args.account_authorization_base_library):
    p.error('Native state routing requires both audited authorization and account base libraries.')
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
if args.authorization_base_library:
    adapter = args.work/'libauth-website.dylib'
    command = ['python3',str(repo/'scripts/patch-editor-authorization.py'),
                    '--input',str(args.authorization_base_library),'--output',str(adapter),
                    '--exclusive-manager-checks']
    if args.native_state_routing: command.append('--native-state-routing')
    subprocess.run(command,check=True)
    library = engine/'Contents/Frameworks/office6/libauth.dylib'
    shutil.copy2(adapter,library)
    subprocess.run(['codesign','--force','--sign','-',str(library)],check=True)
if args.account_authorization_base_library:
    adapter = args.work/'ksolite-website'
    subprocess.run(['python3',str(repo/'scripts/patch-account-authorization.py'),
                    '--input',str(args.account_authorization_base_library),'--output',str(adapter)],check=True)
    library = engine/'Contents/Frameworks/office6/ksolite.framework/Versions/A/ksolite'
    shutil.copy2(adapter,library)
    subprocess.run(['codesign','--force','--sign','-',str(library.parent.parent.parent)],check=True)
subprocess.run(['python3',str(repo/'scripts/refresh-branding.py'),str(app)],check=True)
res = 'Contents/Resources/MbsEngine.app/Contents/Resources/office6/res/'
ribbon_shell = res+'wppongmani.kui'
subprocess.run(['python3',str(repo/'scripts/configure-presentation-ai.py'),str(app)],check=True)
subprocess.run(['python3',str(repo/'scripts/configure-ai-icons.py'),str(app)],check=True)
if not args.full_only and (source/ribbon_shell).read_bytes() != (app/ribbon_shell).read_bytes():
    p.error('Presentation ribbon changes require --full-only; a module-only update cannot apply these UI changes.')
for component in ('wps', 'et', 'wpp', 'pdf'):
    name = res+f'commands/{component}/ongmani/CT_MbsAI.kuip'
    paths[name] = app/name
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
        entry.external_attr = (0o100644 if name == 'manifest.json' or name.endswith('.kuip') else 0o100755)<<16
        entry.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(entry,data)
shutil.copy2(app/'Contents/Resources/MbsModuleInstaller',assets/f'MbsModuleInstaller-{version}')
(assets/'manifests.json').write_text(json.dumps([manifest],indent=2)+'\n')
print(json.dumps({'app':str(app),'package':str(package),'version':version}))
