#!/usr/bin/env python3
"""Enable the verified support mailbox in static contact config and HTML only.
No mail credentials, DNS, Caddy, APIs, backend or company-data changes.
"""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile

EMAIL = 'support@flavorflow.co.in'


def prepare(web):
    config = web / 'assets/support-contact-config.js'
    html = web / 'support/index.html'
    if any(path.is_symlink() or not path.is_file() for path in (config, html)):
        raise ValueError('Expected regular support config/HTML files; no changes made.')
    original = {path: path.read_bytes() for path in (config, html)}
    settings = original[config].decode('utf-8')
    if not re.search(r"\bemailAddress:\s*(['\"])support@flavorflow\.co\.in\1", settings):
        raise ValueError('Unexpected support address; refusing to change another mailbox.')
    settings, count = re.subn(r'\bemailEnabled:\s*(?:false|true)\b', 'emailEnabled: true', settings)
    if count != 1:
        raise ValueError('Expected exactly one emailEnabled flag.')
    page = original[html].decode('utf-8')
    replacements = [
        (r'<span class="channel-status(?: pending-status)?" id="email-status">[^<]*</span>', '<span class="channel-status" id="email-status">EMAIL SUPPORT</span>'),
        (r'<p id="email-description">[^<]*</p>', '<p id="email-description">Send your company code, issue summary and relevant references. Avoid confidential credentials.</p>'),
        (r'<a id="support-email-link"[^>]*>', '<a id="support-email-link" class="channel-action" href="mailto:support%40flavorflow.co.in?subject=FlavorFlow%20ERP%20support%20request">'),
        (r'<span id="email-label">[^<]*</span>', '<span id="email-label">Email our team</span>'),
        (r'(<p class="contact-availability-note" id="contact-availability-note">)[^<]*(</p>)', r'\g<1>Call support · Email support · Chat setup pending. Call/email open your device’s apps; configured chat opens a third-party service. Never share passwords, OTPs or banking credentials.\g<2>'),
        (r'(<span id="support-footer-status">)[^<]*(</span>)', r'\g<1>Call support · Email support · Chat setup pending\g<2>'),
        (r'/assets/support-contact-config\.js(?:\?[^"\s]*)?', '/assets/support-contact-config.js?v=email-active-20261015'),
    ]
    for pattern, replacement in replacements:
        page, count = re.subn(pattern, replacement, page)
        if count != 1:
            raise ValueError('Unexpected support markup; no changes made. Pattern: ' + pattern)
    return original, {config: settings.encode('utf-8'), html: page.encode('utf-8')}


def atomic_write(path, data):
    fd, temp = tempfile.mkstemp(prefix='.ff-email-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, stat.S_IMODE(path.stat().st_mode))
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def activate(web):
    original, updated = prepare(web)
    if original == updated:
        return None
    backup = web.parent / 'backups' / ('support-email-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + str(os.getpid()))
    backup.mkdir(parents=True, exist_ok=False)
    for path in original:
        target = backup / path.relative_to(web)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    changed = []
    try:
        for path, data in updated.items():
            if data != original[path]:
                atomic_write(path, data)
                changed.append(path)
    except Exception:
        for path in reversed(changed):
            atomic_write(path, original[path])
        raise RuntimeError('Activation failed; restored changed files. Backup: ' + str(backup))
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web', default='/opt/flavorflow-saas/web', help='Existing static website directory')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo on the existing hosting VM.')
    try:
        backup = activate(Path(args.web).resolve())
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, str(error) + '\n')
    print('Email support enabled: ' + EMAIL)
    print('Backup: ' + str(backup) if backup else 'Already enabled; no files changed.')
    print('Live chat remains unchanged. No Caddy reload or email credentials required.')
    print('Refresh https://support.flavorflow.co.in/#contact-support to verify the email button.')


if __name__ == '__main__':
    main()
