#!/bin/sh
set -eu
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
app='/Applications/Mbs Office.app'
current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
case "$current" in
  0.1.27) echo '当前已安装 Mbs Office 0.1.27。'; exit 0 ;;
  0.1.26) ;;
  *) echo '此增量包适用于 0.1.26，其他版本请使用完整安装包。'; exit 1 ;;
esac
package="$directory/MbsOffice-modules-0.1.27-from-$current.zip"
signature="$package.sig"
"$app/Contents/Resources/MbsModuleInstaller" --verify-only --app "$app" --package "$package" --signature "$signature"
pid=$(/usr/bin/pgrep -f '^/Applications/Mbs Office[.]app/Contents/Resources/MbsEngine[.]app/Contents/MacOS/wpsoffice($| )' | /usr/bin/head -n 1 || true)
if [ -z "$pid" ]; then pid=2147483647; fi
echo '更新已验证。请保存文档并正常退出，安装后会自动重新打开。'
"$app/Contents/Resources/MbsModuleInstaller" --app "$app" --package "$package" --signature "$signature" --wait-pid "$pid"
