#!/usr/bin/env python3
"""Verify the website snapshot; optionally roll back only Mbs server code."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.request

FILES = ('admin_app.py', 'mbs_activation_codes.py', 'mbs_activation_routes.py', 'mbs_editor_licenses.py')
SERVICE = 'taotie-yishi-admin.service'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            value.update(block)
    return value.hexdigest()


def read_code(backup):
    manifest = json.loads((backup / 'manifest.json').read_text())
    archive = backup / 'website-code-and-private-config.tar.gz'
    if digest(archive) != manifest['sha256'][archive.name]:
        raise ValueError('网站代码备份校验失败。')
    result = {}
    with tarfile.open(archive, 'r|gz') as tar:
        for member in tar:
            prefix = 'opt/taotie-yishi-admin/'
            name = member.name[len(prefix):] if member.name.startswith(prefix) else member.name
            if name not in FILES or member.name != 'opt/taotie-yishi-admin/' + name:
                continue
            if not member.isfile() or member.size > 2*1024*1024:
                raise ValueError('备份代码成员类型或大小异常。')
            result[name] = tar.extractfile(member).read()
            compile(result[name], name, 'exec')
    if set(result) != set(FILES):
        raise ValueError('网站代码备份不完整。')
    return result


def service(action):
    subprocess.run(['systemctl', action, SERVICE], check=True)


def healthy():
    deadline = time.monotonic()+10
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:8091/api/settings', timeout=2) as response:
                if response.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def replace_code(root, files):
    for name, content in files.items():
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('当前代码路径异常：' + name)
        with tempfile.NamedTemporaryFile(dir=root, delete=False) as stream:
            stream.write(content)
            temporary = Path(stream.name)
        shutil.copystat(path, temporary)
        temporary.replace(path)


def restore(backup, root):
    baseline = read_code(backup)
    previous = {name:(root/name).read_bytes() for name in FILES}
    # Retain current code even when health verification or restoration fails.
    saved = Path(tempfile.mkdtemp(prefix='before-code-rollback-', dir=backup))
    for name, content in previous.items():
        (saved/name).write_bytes(content)
    service('stop')
    try:
        replace_code(root, baseline)
        service('start')
        if not healthy():
            raise RuntimeError('回退版本健康检查未通过。')
    except Exception:
        service('stop')
        replace_code(root, previous)
        service('start')
        raise
    return saved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup', type=Path, default=Path('/var/backups/taotie-yishi/mbs-auth-baseline-20261025'))
    parser.add_argument('--code-root', type=Path, default=Path('/opt/taotie-yishi-admin'))
    parser.add_argument('--restore-code', action='store_true')
    args = parser.parse_args()
    if args.restore_code:
        print('已恢复网站代码；原代码保留在：' + str(restore(args.backup, args.code_root)))
    else:
        read_code(args.backup)
        print('网站代码备份校验通过；未修改服务、授权数据库或账号。')


if __name__ == '__main__':
    main()
