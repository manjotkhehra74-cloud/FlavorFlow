"""Static email activation tests; no VM, network or mailbox access."""
import importlib.util
from pathlib import Path
import re
import tarfile
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('email_enable', REPO / 'tools/ff-support-email-enable.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EmailActivation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.web = Path(self.temp.name) / 'web'
        with tarfile.open(REPO / 'website-release/flavorflow-support-release.tar.gz') as archive:
            for name in ('assets/support-contact-config.js', 'support/index.html'):
                target = self.web / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile('flavorflow-support-release/web-landing/' + name).read())
        self.config = self.web / 'assets/support-contact-config.js'
        self.html = self.web / 'support/index.html'
        self.before = {path: path.read_bytes() for path in (self.config, self.html)}

    def tearDown(self):
        self.temp.cleanup()

    def test_enable_email_only_and_backup(self):
        before_config = self.config.read_text()
        backup = module.activate(self.web)
        self.assertEqual(self.config.read_text(), before_config.replace('emailEnabled: false', 'emailEnabled: true'))
        page = self.html.read_text()
        self.assertIn('href="mailto:support%40flavorflow.co.in?', page)
        self.assertIn('id="email-status">EMAIL SUPPORT', page)
        self.assertIn('Live chat — coming soon', page)
        self.assertIn('email-active-20261015', page)
        self.assertNotIn('not yet enabled for support', page)
        self.assertNotIn('Email support — pending', page)
        self.assertIn('tel:+919501606877', page)
        for path, data in self.before.items():
            self.assertEqual((backup / path.relative_to(self.web)).read_bytes(), data)

    def test_idempotent(self):
        module.activate(self.web)
        self.assertIsNone(module.activate(self.web))

    def test_other_mailbox_refused(self):
        self.config.write_text(self.config.read_text().replace('support@flavorflow.co.in', 'other@example.com'))
        with self.assertRaises(ValueError):
            module.activate(self.web)
        self.assertEqual(self.html.read_bytes(), self.before[self.html])

    def test_unknown_html_refused_before_config_write(self):
        self.html.write_text('<html>different support page</html>')
        with self.assertRaises(ValueError):
            module.activate(self.web)
        self.assertEqual(self.config.read_bytes(), self.before[self.config])

    def test_duplicate_flag_refused(self):
        self.config.write_text(self.config.read_text() + '\n// emailEnabled: false\n')
        with self.assertRaises(ValueError):
            module.activate(self.web)

    def test_failure_rolls_back_changed_file(self):
        real_write = module.atomic_write
        def fail_html(path, data):
            if path == self.html:
                raise OSError('simulated write failure')
            return real_write(path, data)
        with patch.object(module, 'atomic_write', side_effect=fail_html):
            with self.assertRaises(RuntimeError):
                module.activate(self.web)
        for path, data in self.before.items():
            self.assertEqual(path.read_bytes(), data)

    def test_symlink_refused(self):
        self.html.unlink()
        self.html.symlink_to(self.config)
        with self.assertRaises(ValueError):
            module.activate(self.web)


if __name__ == '__main__':
    unittest.main()
