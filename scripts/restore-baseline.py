#!/usr/bin/env python3
"""Verify a frozen Mbs baseline; restore only after Mbs has fully exited."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import uuid


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def verify_signature(app):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


def verify_backup(root):
    data = root / 'manifest.json'
    if digest(data) != (root / 'manifest.sha256').read_text().split()[0]:
        raise ValueError('备份清单校验失败，未恢复任何文件。')
    manifest = json.loads(data.read_text())
    if manifest['format'] != 'mbs-baseline-backup-v1' or manifest['version'] != '0.1.40':
        raise ValueError('备份不是指定的 0.1.40 基线。')
    for item in manifest['files']:
        name = Path(item['path'])
        if name.is_absolute() or '..' in name.parts:
            raise ValueError('备份路径不合法。')
        path = root / name
        if 'symlink' in item:
            valid = path.is_symlink() and os.readlink(path) == item['symlink']
        else:
            valid = not path.is_symlink() and path.is_file() and digest(path) == item['sha256']
        if not valid:
            raise ValueError('备份文件校验失败：' + str(name))
    app = root / 'Mbs Office.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != '0.1.40':
        raise ValueError('备份程序版本不匹配。')
    verify_signature(app)
    return info


def is_running(app):
    # Check executable paths only; do not inspect session tokens or user documents.
    output = subprocess.check_output(['ps', '-axo', 'comm='], text=True)
    return any(line.strip().startswith(str(app) + '/') for line in output.splitlines())


def clone(source, target):
    subprocess.run(['/bin/cp', '-cRp', str(source), str(target)], check=True)


def restore(root, app):
    expected = verify_backup(root)
    if is_running(app):
        raise ValueError('请先保存文档并完全退出 Mbs Office，再运行回退。')
    current = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if current.get('CFBundleIdentifier') != expected.get('CFBundleIdentifier'):
        raise ValueError('当前程序身份不匹配，未覆盖。')
    suffix = uuid.uuid4().hex
    staged = app.with_name('Mbs Office.rollback-' + suffix + '.app')
    displaced = app.with_name('Mbs Office.before-rollback-' + suffix + '.app')
    clone(root / 'Mbs Office.app', staged)
    verify_signature(staged)
    # Recheck after staging, in case the user opened Mbs while copying.
    if is_running(app):
        raise ValueError('复制期间 Mbs 已打开，停止替换。候选副本仍保留在：' + str(staged))
    app.rename(displaced)
    try:
        staged.rename(app)
    except Exception:
        displaced.rename(app)
        raise
    return displaced


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--app', type=Path, default=Path('/Applications/Mbs Office.app'))
    parser.add_argument('--restore', action='store_true', help='保存退出后恢复程序；不覆盖当前账号、授权或文档')
    args = parser.parse_args()
    try:
        if args.restore:
            previous = restore(args.backup, args.app)
            print('已恢复 Mbs Office 0.1.40。替换前版本保留在：' + str(previous))
        else:
            verify_backup(args.backup)
            print('0.1.40 备份校验通过；未修改安装程序、账号或文档。')
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
