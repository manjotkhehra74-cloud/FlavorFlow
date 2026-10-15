"""Isolated auto-open update tests; no live VM or provider traffic."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('autostart', ROOT / 'tools/ff-support-chat-autostart.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
BASE = '56da7a3375b9af6d7f8bf21686fa1a75504d6c0e'

class AutoOpenUpdate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.web = Path(self.temp.name) / 'web'
        self.original = {}
        for relative in [*mod.MANIFEST, 'assets/support-contact-config.js', 'assets/support-contacts.js']:
            path = self.web / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            data = subprocess.check_output(['git', 'show', BASE + ':web-landing/' + relative], cwd=ROOT)
            path.write_bytes(data)
            self.original[path] = data

    def test_exact_source_backup_idempotent_preserves_contacts(self):
        backup = mod.activate(self.web)
        for relative in mod.MANIFEST:
            path = self.web / relative
            self.assertEqual(path.read_bytes(), subprocess.check_output(['git', 'show', '478acf4a1ae536da232b8ca9e4e4dd3b93852b58:web-landing/' + relative], cwd=ROOT))
            self.assertEqual((backup / relative).read_bytes(), self.original[path])
        for relative in ['assets/support-contact-config.js', 'assets/support-contacts.js']:
            path = self.web / relative
            self.assertEqual(path.read_bytes(), self.original[path])
        self.assertIsNone(mod.activate(self.web))

    def test_unknown_file_refused_before_any_write(self):
        (self.web / 'support/index.html').write_text('custom page')
        with self.assertRaises(ValueError):
            mod.activate(self.web)
        path = self.web / 'assets/support-chat.js'
        self.assertEqual(path.read_bytes(), self.original[path])

    def test_missing_file_refused(self):
        (self.web / 'assets/support-chat.js').unlink()
        with self.assertRaises(ValueError):
            mod.activate(self.web)

    def test_symlink_refused(self):
        path = self.web / 'assets/support-chat.js'
        path.unlink()
        path.symlink_to(self.web / 'support/index.html')
        with self.assertRaises(ValueError):
            mod.activate(self.web)

    def test_failed_html_write_restores_loader(self):
        write = mod.atomic_write
        calls = 0
        def fail_once(path, data):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('injected failure')
            write(path, data)
        with patch.object(mod, 'atomic_write', side_effect=fail_once):
            with self.assertRaises(RuntimeError):
                mod.activate(self.web)
        for path, data in self.original.items():
            self.assertEqual(path.read_bytes(), data)

if __name__ == '__main__':
    unittest.main()
