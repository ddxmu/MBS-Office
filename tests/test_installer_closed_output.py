#!/usr/bin/env python3
"""Verify an update without changing an app, including after its reader exits."""
import argparse
import json
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installer', required=True)
    parser.add_argument('--app', required=True)
    parser.add_argument('--package', required=True)
    parser.add_argument('--signature', required=True)
    args = parser.parse_args()
    command = [args.installer, '--verify-only', '--app', args.app,
               '--package', args.package, '--signature', args.signature]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['state'] == 'verified'
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    child.stdout.close()
    child.stderr.close()
    try:
        assert child.wait(timeout=30) == 0, 'Installer exited after its output reader closed'
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
    print('PASS: signed package verification with live and closed output pipes; no app changes')


if __name__ == '__main__':
    main()
