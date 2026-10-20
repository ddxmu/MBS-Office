#!/bin/sh
set -eu
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
app='/Applications/Mbs Office.app'
package="$directory/MbsOffice-modules-0.1.20-from-0.1.18.zip"
signature="$package.sig"
current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [ "$current" = '0.1.20' ]; then
    echo '当前已安装 Mbs Office 0.1.20。'
    exit 0
fi
if [ "$current" != '0.1.18' ]; then
    echo '此增量包仅适用于 0.1.18，请使用完整安装包。'
    exit 1
fi
# The already-installed verifier authenticates the archive before any new code
# is extracted or executed. Its output stays attached while it verifies.
"$app/Contents/Resources/MbsModuleInstaller" --verify-only --app "$app" --package "$package" --signature "$signature"
temporary=$(/usr/bin/mktemp -d -t MbsOfficeUpdate)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
/usr/bin/unzip -p "$package" Contents/Resources/MbsModuleInstaller > "$temporary/installer"
/bin/chmod 700 "$temporary/installer"
pid=$(/usr/bin/pgrep -f '^/Applications/Mbs Office[.]app/Contents/Resources/MbsEngine[.]app/Contents/MacOS/wpsoffice($| )' | /usr/bin/head -n 1 || true)
if [ -z "$pid" ]; then pid=2147483647; fi
echo '正在更新。请保存文档并正常退出 Mbs Office；安装后会自动重新打开。'
"$temporary/installer" --app "$app" --package "$package" --signature "$signature" --wait-pid "$pid"
