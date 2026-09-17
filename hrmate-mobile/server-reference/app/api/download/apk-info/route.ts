import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

// GET /api/download/apk-info — what the download page shows (public).
// → { ok:true, package:"in.flavorflow.hrmate", minAndroid:"8.0", version:"3.0.0", build:30,
//     file:"HRMate-3.0.0.apk", sizeBytes, sha256, publishedAt, available:true, url:"/api/download/apk" }
// Nothing published yet → 404 { ok:false, code:"NOT_FOUND" }.
const RELEASES_DIR =
  process.env.HRMATE_RELEASES_DIR ||
  path.join(path.dirname(process.env.HRMATE_DB || '/app/data/hrmate.db'), 'releases');

export async function GET() {
  let info: Record<string, unknown> | null = null;
  try {
    info = JSON.parse(fs.readFileSync(path.join(RELEASES_DIR, 'apk-info.json'), 'utf8'));
  } catch {
    info = null;
  }
  if (!info || typeof info.file !== 'string') {
    return NextResponse.json({ ok: false, error: 'No APK has been published yet.', code: 'NOT_FOUND' }, { status: 404 });
  }
  const available = fs.existsSync(path.join(RELEASES_DIR, path.basename(info.file)));
  return NextResponse.json(
    { ok: true, package: 'in.flavorflow.hrmate', minAndroid: '8.0', ...info, available, url: '/api/download/apk' },
    { headers: { 'Cache-Control': 'no-cache' } },
  );
}
