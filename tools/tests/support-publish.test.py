"""Local release safety tests. No live VM, Caddy service or network is accessed."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
HELPER = (REPO / 'tools/ff-support-publish.sh').read_text()
FILES = shlex.split(HELPER.split('FILES=(', 1)[1].split('\n)', 1)[0])
VALIDATOR = HELPER.split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
OTHER = 'flavorflow.co.in {\n    reverse_proxy /api/* 127.0.0.1:4100\n}\nhr.flavorflow.co.in {\n    respond "Keep this route"\n}\n'
PLACEHOLDER = 'support.flavorflow.co.in {\n    header X-Robots-Tag "noindex, nofollow"\n    respond "FlavorFlow ERP support centre — coming soon." 200\n}\n'

class ReleaseSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ff-support-test-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'release'
        manifest = {}
        for name in FILES:
            source = REPO / 'web-landing' / name
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            manifest[name] = hashlib.sha256(target.read_bytes()).hexdigest()
        (self.source / 'release-manifest.json').write_text(json.dumps(manifest))
        self.cfg = self.root / 'Caddyfile'
        self.cfg.write_text(OTHER + PLACEHOLDER)

    def tearDown(self):
        self.temp.cleanup()

    def validate(self):
        return subprocess.run(['python3', '-c', VALIDATOR, str(self.source), str(self.cfg), *FILES], capture_output=True, text=True)

    def test_known_placeholder_preserves_other_routes(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.cfg.read_text().startswith(OTHER))
        self.assertIn('# FlavorFlow managed support web', self.cfg.read_text())
        self.assertIn('@supportFiles path /support/* /assets/*', self.cfg.read_text())

    def test_managed_block_is_idempotent(self):
        self.assertEqual(self.validate().returncode, 0)
        first = self.cfg.read_text()
        self.assertEqual(self.validate().returncode, 0)
        self.assertEqual(self.cfg.read_text(), first)

    def test_unknown_routing_is_refused(self):
        self.cfg.write_text(OTHER + 'support.flavorflow.co.in {\n    reverse_proxy 127.0.0.1:9000\n}\n')
        original = self.cfg.read_text()
        self.assertNotEqual(self.validate().returncode, 0)
        self.assertEqual(self.cfg.read_text(), original)

    def test_duplicate_hostname_is_refused(self):
        self.cfg.write_text(OTHER + PLACEHOLDER + PLACEHOLDER)
        original = self.cfg.read_text()
        self.assertNotEqual(self.validate().returncode, 0)
        self.assertEqual(self.cfg.read_text(), original)

    def test_tampered_release_is_refused(self):
        (self.source / 'assets/support.css').write_text('tampered')
        self.assertIn('checksum mismatch', self.validate().stderr)
        self.assertEqual(self.cfg.read_text(), OTHER + PLACEHOLDER)

    def mock_publish(self, fail_install=False):
        # Patch paths into the disposable fixture, and mock root/service/HTTPS tools.
        # This tests shell control flow; it does NOT validate real Caddy syntax/ACME.
        web = self.root / 'web'
        web.mkdir()
        (web / 'index.html').write_text('ORIGINAL WEBSITE')
        mocks = self.root / 'bin'
        mocks.mkdir()
        commands = {
            'id': '#!/bin/sh\necho 0\n',
            'caddy': '#!/bin/sh\nexit 0\n',
            'systemctl': '#!/bin/sh\nexit 0\n',
            'install': '#!/bin/sh\nif [ "$MOCK_FAIL_INSTALL" = 1 ]; then\n case "$*" in *assets/support.css*) exit 1;; esac\nfi\nexec /usr/bin/install "$@"\n',
            'curl': '''#!/usr/bin/env python3
import os, shutil, sys
from urllib.parse import urlsplit
url = urlsplit(next(a for a in sys.argv if a.startswith('https://')))
name = ('support/index.html' if url.hostname == 'support.flavorflow.co.in' else 'index.html') if url.path == '/' else url.path.lstrip('/')
shutil.copyfile(os.path.join(os.environ['MOCK_WEB'], name), sys.argv[sys.argv.index('-o')+1])
''',
        }
        for name, content in commands.items():
            file = mocks / name
            file.write_text(content)
            file.chmod(0o755)
        text = HELPER.replace('WEB=/opt/flavorflow-saas/web', 'WEB=' + shlex.quote(str(web)))
        text = text.replace('CFG=/etc/caddy/Caddyfile', 'CFG=' + shlex.quote(str(self.cfg)))
        text = text.replace('/opt/flavorflow-saas/backups/', str(self.root / 'backups') + '/')
        script = self.root / 'publish.sh'
        script.write_text(text)
        env = dict(os.environ, PATH=str(mocks) + ':' + os.environ['PATH'], MOCK_WEB=str(web), MOCK_FAIL_INSTALL='1' if fail_install else '0')
        result = subprocess.run(['bash', str(script), str(self.source)], env=env, capture_output=True, text=True)
        return result, web

    def test_mock_publish_success(self):
        result, web = self.mock_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((web / 'index.html').read_bytes(), (self.source / 'index.html').read_bytes())
        self.assertTrue(self.cfg.read_text().startswith(OTHER))
        self.assertIn('Local HTTPS checks passed', result.stdout)

    def test_mock_install_failure_restores_files_config(self):
        result, web = self.mock_publish(fail_install=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((web / 'index.html').read_text(), 'ORIGINAL WEBSITE')
        self.assertEqual(self.cfg.read_text(), OTHER + PLACEHOLDER)
        self.assertFalse((web / 'support/index.html').exists())
        self.assertFalse((web / 'assets/flavorflow-logo-v2.png').exists())
        self.assertIn('Restored backup', result.stderr)

if __name__ == '__main__':
    unittest.main()
