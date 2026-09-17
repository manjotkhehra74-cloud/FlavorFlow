import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

// GET /api/download/apk — the latest PUBLISHED native APK (public, no auth).
//
// Files live in the persistent data volume next to the DB:  <dirname(HRMATE_DB)>/releases/
//   HRMate-<version>.apk  +  apk-info.json   ← written ONLY by scripts/publish-apk.sh on the VPS
// (never committed to git, never baked into the Docker image; survives `docker compose up --build`).
// Nothing published yet → 404 JSON. Never redirect to the old WebView-shell GitHub release.
const RELEASES_DIR =
  process.env.HRMATE_RELEASES_DIR ||
  path.join(path.dirname(process.env.HRMATE_DB || '/app/data/hrmate.db'), 'releases');

type ApkInfo = { version: string; build: number; file: string; sizeBytes: number; sha256: string; publishedAt: string };

function readInfo(): ApkInfo | null {
  try {
    const raw = JSON.parse(fs.readFileSync(path.join(RELEASES_DIR, 'apk-info.json'), 'utf8'));
    return raw && typeof raw.file === 'string' ? (raw as ApkInfo) : null;
  } catch {
    return null;
  }
}

export async function GET() {
  const info = readInfo();
  const file = info ? path.join(RELEASES_DIR, path.basename(info.file)) : '';
  if (!info || !fs.existsSync(file)) {
    return NextResponse.json({ ok: false, error: 'No APK has been published yet.', code: 'NOT_FOUND' }, { status: 404 });
  }
  const stat = fs.statSync(file);
  const body = fs.readFileSync(file);
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': `attachment; filename="${path.basename(info.file)}"`,
      'Content-Length': String(stat.size),
      'Cache-Control': 'no-cache',
      'X-HRMate-Version': `${info.version} (${info.build})`,
    },
  });
}
