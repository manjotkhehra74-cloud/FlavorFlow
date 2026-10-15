"""Chatwoot migration safety tests. No VM, provider requests or real conversations."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('chatwoot_enable', ROOT / 'tools/ff-support-chatwoot-enable.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
BASES = ['56da7a3375b9af6d7f8bf21686fa1a75504d6c0e', '478acf4a1ae536da232b8ca9e4e4dd3b93852b58', '3aa440115a44d215f316c9c65040cedc939a356d']

class ChatwootMigration(unittest.TestCase):
    def fixture(self, base=BASES[1]):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        web = Path(temp.name) / 'web'
        original = {}
        for relative in mod.MANIFEST:
            path = web / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            data = subprocess.check_output(['git', 'show', base + ':web-landing/' + relative], cwd=ROOT)
            path.write_bytes(data)
            original[path] = data
        return web, original

    def test_all_previous_releases_exact_source_backup_idempotent(self):
        for base in BASES:
            with self.subTest(base=base):
                web, original = self.fixture(base)
                unrelated = web / 'company-data.txt'
                unrelated.write_text('must not change')
                backup = mod.activate(web)
                for relative in mod.MANIFEST:
                    path = web / relative
                    target = (ROOT / 'web-landing' / relative).read_bytes()
                    self.assertEqual(path.read_bytes(), target)
                    self.assertNotIn(b'tawk', target.lower())
                    if original[path] != target:
                        self.assertEqual((backup / relative).read_bytes(), original[path])
                self.assertIsNone(mod.activate(web))
                self.assertEqual(unrelated.read_text(), 'must not change')
                config = (web / 'assets/support-contact-config.js').read_text()
                self.assertIn("phoneNumber: '+919501606877'", config)
                self.assertIn("emailAddress: 'support@flavorflow.co.in'", config)
                self.assertIn('emailEnabled: true', config)
                self.assertIn("chatwootWebsiteToken: 'gSkACYN5CHoy4WnpSdPjgfvT'", config)

    def test_unknown_custom_config_refused_before_writes(self):
        web, original = self.fixture()
        path = web / 'assets/support-contact-config.js'
        path.write_text('custom owner settings')
        with self.assertRaises(ValueError):
            mod.activate(web)
        self.assertEqual((web / 'assets/support-chat.js').read_bytes(), original[web / 'assets/support-chat.js'])
        self.assertFalse((web.parent / 'backups').exists())

    def test_missing_required_file_refused(self):
        web, _ = self.fixture()
        (web / 'support/index.html').unlink()
        with self.assertRaises(ValueError):
            mod.activate(web)

    def test_symlink_file_and_directory_refused(self):
        for directory in [False, True]:
            web, _ = self.fixture()
            if directory:
                (web / 'support').rename(web / 'support-real')
                (web / 'support').symlink_to(web / 'support-real', target_is_directory=True)
            else:
                path = web / 'assets/support-chat.js'
                path.unlink()
                path.symlink_to(web / 'support/index.html')
            with self.assertRaises(ValueError):
                mod.activate(web)

    def test_write_failure_rolls_back_all_changes(self):
        web, original = self.fixture()
        write = mod.atomic_write
        calls = 0
        def fail_once(path, data):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise OSError('injected failure')
            write(path, data)
        with patch.object(mod, 'atomic_write', side_effect=fail_once):
            with self.assertRaises(RuntimeError):
                mod.activate(web)
        for path, data in original.items():
            self.assertEqual(path.read_bytes(), data)

    def test_corrupt_embedded_release_is_refused(self):
        web, _ = self.fixture()
        entry = mod.MANIFEST['assets/support-chat.js']
        with patch.dict(entry, {'sha256': 'corrupt'}):
            with self.assertRaises(ValueError):
                mod.activate(web)
        self.assertFalse((web.parent / 'backups').exists())

if __name__ == '__main__':
    unittest.main()
