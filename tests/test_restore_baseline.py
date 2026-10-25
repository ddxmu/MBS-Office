import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('restore_baseline', Path(__file__).resolve().parents[1] / 'scripts/restore-baseline.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'backup'
        self.app = self.base / 'installed/Mbs Office.app'
        for app, version in [(self.root / 'Mbs Office.app', '0.1.40'), (self.app, '0.1.41')]:
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'test.mbs', 'CFBundleShortVersionString':version}))
            (app / 'Contents/data').write_text(version)
        files = [{'path':str(p.relative_to(self.root)), 'sha256':restore.digest(p)} for p in self.root.rglob('*') if p.is_file()]
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps({'format':'mbs-baseline-backup-v1','version':'0.1.40','files':files}))
        (self.root / 'manifest.sha256').write_text(restore.digest(manifest) + '  manifest.json\n')
        self.signatures = patch.object(restore, 'verify_signature')
        self.signatures.start()
        self.addCleanup(self.signatures.stop)

    def test_corrupt_baseline_never_replaces_installed_app(self):
        (self.root / 'Mbs Office.app/Contents/data').write_text('damaged')
        with self.assertRaises(ValueError):
            restore.restore(self.root, self.app)
        self.assertEqual((self.app / 'Contents/data').read_text(), '0.1.41')

    def test_busy_app_never_replaced(self):
        with patch.object(restore, 'is_running', return_value=True), self.assertRaises(ValueError):
            restore.restore(self.root, self.app)
        self.assertEqual((self.app / 'Contents/data').read_text(), '0.1.41')

    def test_swap_failure_automatically_restores_current_app(self):
        rename = Path.rename
        def fail_staging(path, target):
            if 'Mbs Office.rollback-' in path.name:
                raise OSError('simulated replacement failure')
            return rename(path, target)
        with patch.object(restore, 'is_running', return_value=False), patch.object(Path, 'rename', fail_staging), self.assertRaises(OSError):
            restore.restore(self.root, self.app)
        self.assertEqual((self.app / 'Contents/data').read_text(), '0.1.41')

    def test_success_preserves_displaced_version_and_account(self):
        account = self.base / 'current-account'
        account.write_text('current-session')
        with patch.object(restore, 'is_running', return_value=False):
            previous = restore.restore(self.root, self.app)
        self.assertEqual((self.app / 'Contents/data').read_text(), '0.1.40')
        self.assertEqual((previous / 'Contents/data').read_text(), '0.1.41')
        self.assertEqual(account.read_text(), 'current-session')


if __name__ == '__main__':
    unittest.main()
