"""Run: python3 tools/tests/support-chat-enable.test.py (no VM needed)."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('chat_enable', ROOT / 'tools/ff-support-chat-enable.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
BASE = '3b8943c97c280dd08c5d051865792275c52ddbd5'


class ChatActivation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.web = Path(self.temp.name) / 'web'
        for relative, item in mod.MANIFEST.items():
            path = self.web / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if item['previous']:
                data = subprocess.check_output(['git', 'show', BASE + ':web-landing/' + relative], cwd=ROOT)
                self.assertEqual(hashlib.sha256(data).hexdigest(), item['previous'])
                path.write_bytes(data)
        self.original = {p: p.read_bytes() for p in self.web.rglob('*') if p.is_file()}

    def test_enable_backup_idempotent_and_release_matches_source(self):
        sentinel = self.web / 'company-data.txt'
        sentinel.write_text('untouched')
        backup = mod.activate(self.web)
        for relative in mod.MANIFEST:
            self.assertEqual((self.web / relative).read_bytes(), (ROOT / 'web-landing' / relative).read_bytes())
        for path, data in self.original.items():
            self.assertEqual((backup / path.relative_to(self.web)).read_bytes(), data)
        self.assertIsNone(mod.activate(self.web))
        self.assertEqual(sentinel.read_text(), 'untouched')
        config = (self.web / 'assets/support-contact-config.js').read_text()
        self.assertIn('emailEnabled: true', config)
        self.assertIn("phoneNumber: '+919501606877'", config)

    def test_modified_files_refused_before_writes(self):
        path = self.web / 'assets/support-contact-config.js'
        path.write_text('unexpected config')
        with self.assertRaises(ValueError):
            mod.activate(self.web)
        self.assertFalse((self.web / 'assets/support-chat.js').exists())

    def test_missing_required_file_refused(self):
        (self.web / 'support/index.html').unlink()
        with self.assertRaises(ValueError):
            mod.activate(self.web)

    def test_symlink_file_refused(self):
        path = self.web / 'assets/support-chat.js'
        path.symlink_to(self.web / 'support/index.html')
        with self.assertRaises(ValueError):
            mod.activate(self.web)

    def test_symlink_directory_refused(self):
        path = self.web / 'support'
        path.rename(self.web / 'support-real')
        path.symlink_to(self.web / 'support-real', target_is_directory=True)
        with self.assertRaises(ValueError):
            mod.activate(self.web)

    def test_rollback_removes_new_asset_and_restores_previous(self):
        write = mod.atomic_write
        count = 0
        def fail_once(path, data):
            nonlocal count
            count += 1
            if count == 3:
                raise OSError('injected failure')
            write(path, data)
        with patch.object(mod, 'atomic_write', side_effect=fail_once):
            with self.assertRaises(RuntimeError):
                mod.activate(self.web)
        self.assertFalse((self.web / 'assets/support-chat.js').exists())
        for path, data in self.original.items():
            self.assertEqual(path.read_bytes(), data)


if __name__ == '__main__':
    unittest.main()
