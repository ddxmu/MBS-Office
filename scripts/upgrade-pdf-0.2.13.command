#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
fail() { printf '%s\n' "$*" >&2; exit 1; }
app="${1:-/Applications/Mbs Office.app}"
if [ ! -d "$app" ]; then
  app=$(/usr/bin/osascript -e 'POSIX path of (choose file of type {"app"} with prompt "请选择 Mbs Office 0.2.12")')
fi
app="${app%/}"
[ ! -L "$app" ] || fail '请选择实际的应用程序，不要选择替身或链接。'
info="$app/Contents/Info.plist"
engine='Contents/Resources/MbsEngine.app'
module="$engine/Contents/MacOS/MbsOfflineFlags.dylib"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" = 'com.mbs.office.launcher' ] || fail '这不是 Mbs Office。'
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" = '0.2.12' ] || fail '此增量包仅用于 0.2.12；其他版本请使用完整安装包。'
check_hash() {
  [ "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" = "$2" ] || fail "文件校验不符：$1。请使用完整安装包。"
}
check_hash "$app/$module" '7246154a4ba5f7bce9c855b181b3217bd4b0ca0eda4b996e33b05c78a2604b8c'
check_hash 'payload/MbsOfflineFlags.dylib' '@MBS_MODULE_SHA256@'
check_hash 'payload/MbsPdfEngine.zip' '@MBS_ENGINE_SHA256@'
/usr/bin/codesign --verify --deep --strict "$app"
processes=$(/bin/ps -axo command=)
if printf '%s\n' "$processes" | /usr/bin/awk -v prefix="$app/$engine/Contents/MacOS/wpsoffice" 'index($0,prefix)==1 {found=1} END {exit !found}'; then
  fail '请先保存文档并完全退出当前 Mbs Office，再重新运行升级。'
fi
parent="$(dirname "$app")"
stage=$(/usr/bin/mktemp -d "$parent/.MbsOffice-PDF-update.XXXXXX")
backup="$parent/.MbsOffice-0.2.12-backup.${stage##*.}"
cleanup() {
  status=$?
  if [ ! -e "$app" ] && [ -d "$backup" ]; then /bin/mv "$backup" "$app"; fi
  /bin/rm -rf "$stage"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
candidate="$stage/Mbs Office.app"
/bin/cp -cRp "$app" "$candidate"
/bin/cp 'payload/MbsOfflineFlags.dylib' "$candidate/$module"
/usr/bin/ditto -x -k 'payload/MbsPdfEngine.zip' "$candidate/$engine/Contents/Resources"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.2.13' "$candidate/Contents/Info.plist"
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build + 1))" "$candidate/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :MbsModuleVersion 0.2.13' "$candidate/$engine/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$candidate/$engine"
/usr/bin/codesign --force --sign - "$candidate"
/usr/bin/codesign --verify --deep --strict "$candidate"
/bin/mv "$app" "$backup"
/bin/mv "$candidate" "$app"
printf '已升级到 0.2.13。原版本备份：%s\n' "$backup"
if [ "${2:-}" != '--no-open' ]; then /usr/bin/open "$app" || true; fi
