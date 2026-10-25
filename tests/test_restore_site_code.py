import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('restore_site', Path(__file__).resolve().parents[1] / 'scripts/restore-site-code.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class WebsiteRollbackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.backup = Path(self.temp.name) / 'backup'
        self.root = Path(self.temp.name) / 'code'
        self.backup.mkdir()
        self.root.mkdir()
        archive = self.backup / 'website-code-and-private-config.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name in restore.FILES:
                content = b'# baseline code\n'
                item = tarfile.TarInfo('opt/taotie-yishi-admin/'+name)
                item.size = len(content)
                tar.addfile(item, io.BytesIO(content))
                (self.root/name).write_text('# current code\n')
        (self.backup/'manifest.json').write_text(json.dumps({'sha256':{archive.name:restore.digest(archive)}}))
        self.database = Path(self.temp.name) / 'live.db'
        self.database.write_text('live business data')

    def test_corrupt_archive_rejected_without_stopping_service(self):
        with (self.backup/'website-code-and-private-config.tar.gz').open('ab') as stream:
            stream.write(b'damage')
        with patch.object(restore, 'service') as service, self.assertRaises(ValueError):
            restore.restore(self.backup, self.root)
        service.assert_not_called()

    def test_failed_health_check_restores_previous_code(self):
        with patch.object(restore, 'service'), patch.object(restore, 'healthy', return_value=False), self.assertRaises(RuntimeError):
            restore.restore(self.backup, self.root)
        for name in restore.FILES:
            self.assertEqual((self.root/name).read_text(), '# current code\n')
        self.assertEqual(self.database.read_text(), 'live business data')

    def test_success_preserves_current_code_and_never_restores_database(self):
        with patch.object(restore, 'service'), patch.object(restore, 'healthy', return_value=True):
            saved = restore.restore(self.backup, self.root)
        for name in restore.FILES:
            self.assertEqual((self.root/name).read_text(), '# baseline code\n')
            self.assertEqual((saved/name).read_text(), '# current code\n')
        self.assertEqual(self.database.read_text(), 'live business data')


if __name__ == '__main__':
    unittest.main()
