// Phase 6 — Firebase Cloud Messaging (HTTP v1) sender for the native app.
//
// * No npm dependency: the service-account key signs an RS256 JWT with node:crypto,
//   the OAuth token is cached, messages go to `projects/<id>/messages:send` with fetch.
// * Config = ONE file, the Firebase service-account key, outside git and outside the
//   image: `/app/data/fcm-service-account.json` (docker volume `hrmate_data`), or the
//   env `FCM_SERVICE_ACCOUNT_FILE` / `FCM_SERVICE_ACCOUNT_JSON`. The file is re-checked
//   every 30 s, so copying it into the container is enough — no restart needed.
// * Never throws into a caller: without a key every send is a silent no-op, so the
//   webapp keeps working exactly as before Phase 6.
// * Called by `src/lib/push.ts` (`sendPushToUser` → web-push subscriptions THEN
//   `sendFcmToUser`), i.e. every existing `notify()` — punch reminders, leave
//   decisions, announcements — reaches the phone with no change to business logic.
//   `push.ts` already returns early when the user turned notifications off
//   (`isNotifyEnabled`), so the preference covers web and app alike.
//
// Lives at `src/lib/fcm.ts` in the webapp (next to push.ts / prefs.ts / notify.ts).
import fs from 'fs';
import { createSign } from 'crypto';
import db from './db';

// Table is created on first use (not at import) so `next build` never touches the DB.
let schemaReady = false;
function ensureSchema(): void {
  if (schemaReady) return;
  db.exec(`
    CREATE TABLE IF NOT EXISTS mobile_push_tokens (
      token      TEXT PRIMARY KEY,
      user_id    TEXT NOT NULL,
      device_id  TEXT NOT NULL DEFAULT '',
      platform   TEXT NOT NULL DEFAULT 'android',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_error TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_mobile_push_tokens_user ON mobile_push_tokens(user_id);
  `);
  schemaReady = true;
}

export type PushPayload = { title: string; body: string; link?: string };

/** Must match `PushController.channelId` + the manifest meta-data in the app. */
export const FCM_CHANNEL_ID = 'hrmate_default';
const FCM_ICON = 'ic_notification';
const FCM_COLOR = '#1E6FE0';

type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri: string };

const SA_FILE = process.env.FCM_SERVICE_ACCOUNT_FILE || '/app/data/fcm-service-account.json';
let sa: ServiceAccount | null = null;
let saCheckedAt = 0;
let saError = 'not checked yet';

function loadServiceAccount(): ServiceAccount | null {
  if (sa) return sa;
  const now = Date.now();
  if (now - saCheckedAt < 30_000) return null;
  saCheckedAt = now;
  try {
    const raw =
      process.env.FCM_SERVICE_ACCOUNT_JSON ||
      (fs.existsSync(SA_FILE) ? fs.readFileSync(SA_FILE, 'utf8') : '');
    if (!raw) {
      saError = `no service-account key at ${SA_FILE}`;
      return null;
    }
    const j = JSON.parse(raw);
    if (!j.project_id || !j.client_email || !j.private_key) {
      saError = 'file is not a Firebase service-account key (project_id / client_email / private_key missing)';
      return null;
    }
    sa = {
      project_id: String(j.project_id),
      client_email: String(j.client_email),
      private_key: String(j.private_key),
      token_uri: String(j.token_uri || 'https://oauth2.googleapis.com/token'),
    };
    saError = '';
    console.log(`[fcm] configured: project ${sa.project_id} (${sa.client_email})`);
    return sa;
  } catch (e) {
    saError = `cannot read ${SA_FILE}: ${(e as Error).message || e}`;
    return null;
  }
}

/** For `POST devices/push-test` and logs — never exposes the key. */
export function fcmStatus(): { configured: boolean; project: string | null; error: string | null; file: string } {
  const s = loadServiceAccount();
  return { configured: !!s, project: s?.project_id || null, error: s ? null : saError, file: SA_FILE };
}

// ---- OAuth2 (service account → access token, cached until ~1 min before expiry) ----
let accessToken = '';
let accessExp = 0;
let accessInflight: Promise<string> | null = null;

function getAccessToken(s: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (accessToken && accessExp - 60 > now) return Promise.resolve(accessToken);
  // parallel sends share ONE token request (a fan-out must not hit OAuth N times)
  accessInflight ??= fetchAccessToken(s).finally(() => {
    accessInflight = null;
  });
  return accessInflight;
}

async function fetchAccessToken(s: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const b64u = (x: string) => Buffer.from(x).toString('base64url');
  const header = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64u(
    JSON.stringify({
      iss: s.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: s.token_uri,
      iat: now,
      exp: now + 3600,
    })
  );
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claims}`);
  signer.end();
  const signature = signer.sign(s.private_key, 'base64url');
  const res = await fetch(s.token_uri, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${signature}`,
    }),
  });
  const j = (await res.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error?: string; error_description?: string };
  if (!res.ok || !j.access_token) {
    throw new Error(`oauth ${res.status}: ${j.error_description || j.error || 'no access_token'}`);
  }
  accessToken = j.access_token;
  accessExp = now + Number(j.expires_in || 3600);
  return accessToken;
}

let lastWarnAt = 0;
function warn(msg: string) {
  const now = Date.now();
  if (now - lastWarnAt < 60_000) return;
  lastWarnAt = now;
  console.warn(`[fcm] ${msg}`);
}

type SendResult = 'ok' | 'gone' | 'error';

async function sendOne(s: ServiceAccount, token: string, p: PushPayload, retry = true): Promise<{ r: SendResult; err?: string }> {
  const at = await getAccessToken(s);
  const message = {
    token,
    notification: { title: p.title, body: p.body },
    // data values must be strings; the app routes a tap by `link` (webapp path)
    data: { link: p.link || '/dashboard', title: p.title, body: p.body },
    android: {
      priority: 'HIGH',
      notification: { channel_id: FCM_CHANNEL_ID, icon: FCM_ICON, color: FCM_COLOR, default_sound: true },
    },
  };
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${s.project_id}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${at}`, 'content-type': 'application/json' },
    body: JSON.stringify({ message }),
  });
  if (res.ok) return { r: 'ok' };
  const text = (await res.text().catch(() => '')).slice(0, 400);
  if (res.status === 401 && retry) {
    accessToken = ''; // token revoked/expired early — refresh once
    return sendOne(s, token, p, false);
  }
  // Token no longer valid on this phone (app uninstalled / data cleared / rotated) → forget it.
  const gone = res.status === 404 || /UNREGISTERED|not a valid FCM registration token/i.test(text);
  return { r: gone ? 'gone' : 'error', err: `${res.status} ${text}` };
}

/** Send one notification to every registered phone of a user. Never throws. */
export async function sendFcmToUser(userId: string, p: PushPayload): Promise<{ sent: number; failed: number; removed: number }> {
  const out = { sent: 0, failed: 0, removed: 0 };
  const s = loadServiceAccount();
  if (!s) return out;
  ensureSchema();
  let rows: { token: string }[] = [];
  try {
    rows = db.prepare('SELECT token FROM mobile_push_tokens WHERE user_id = ?').all(userId) as { token: string }[];
  } catch (e) {
    warn(`token lookup failed: ${(e as Error).message || e}`);
    return out;
  }
  if (!rows.length) return out;
  await Promise.all(
    rows.map(async ({ token }) => {
      try {
        const { r, err } = await sendOne(s, token, p);
        if (r === 'ok') {
          out.sent++;
        } else if (r === 'gone') {
          db.prepare('DELETE FROM mobile_push_tokens WHERE token = ?').run(token);
          out.removed++;
        } else {
          out.failed++;
          db.prepare('UPDATE mobile_push_tokens SET last_error = ? WHERE token = ?').run((err || 'error').slice(0, 300), token);
          warn(`send failed for user ${userId}: ${err}`);
        }
      } catch (e) {
        out.failed++;
        warn(`send threw for user ${userId}: ${(e as Error).message || e}`);
      }
    })
  );
  return out;
}

/** Fan-out helper — 10 users at a time. Never throws. */
export async function sendFcmToMany(userIds: string[], p: PushPayload): Promise<void> {
  for (let i = 0; i < userIds.length; i += 10) {
    await Promise.all(userIds.slice(i, i + 10).map((id) => sendFcmToUser(id, p)));
  }
}

/**
 * Announcement (new wall post) → every active user's PHONE, except the author and
 * users who turned notifications off. Deliberately push-only: the webapp's
 * notifications inbox / web-push behaviour is unchanged (additive, no new rule).
 * Fire-and-forget from the wall POST handler; never throws.
 */
export function sendFcmAnnouncement(p: PushPayload, excludeUserId = ''): void {
  if (!loadServiceAccount()) return;
  ensureSchema();
  let ids: string[] = [];
  try {
    ids = (
      db
        .prepare(
          `SELECT DISTINCT t.user_id AS id
             FROM mobile_push_tokens t
             JOIN users u ON u.id = t.user_id AND u.active = 1
             LEFT JOIN user_prefs pr ON pr.user_id = t.user_id
            WHERE t.user_id != ? AND COALESCE(pr.notify_enabled, 1) != 0`
        )
        .all(excludeUserId) as { id: string }[]
    ).map((r) => r.id);
  } catch (e) {
    warn(`announcement lookup failed: ${(e as Error).message || e}`);
    return;
  }
  if (!ids.length) return;
  sendFcmToMany(ids, p).catch(() => {});
}

// ---- token registry (used by devices/* routes and auth/logout) ----------------------

export function registerPushToken(userId: string, token: string, platform: string, deviceId: string): void {
  ensureSchema();
  const now = new Date().toISOString();
  db.prepare(
    `INSERT INTO mobile_push_tokens (token, user_id, device_id, platform, created_at, updated_at, last_error)
     VALUES (?, ?, ?, ?, ?, ?, NULL)
     ON CONFLICT(token) DO UPDATE SET
       user_id = excluded.user_id,
       device_id = excluded.device_id,
       platform = excluded.platform,
       updated_at = excluded.updated_at,
       last_error = NULL`
  ).run(token, userId, deviceId, platform, now, now);
  // one token per phone: a rotated token replaces the previous one of the same device
  if (deviceId) db.prepare('DELETE FROM mobile_push_tokens WHERE device_id = ? AND token != ?').run(deviceId, token);
}

export function removePushToken(userId: string, token: string): void {
  ensureSchema();
  db.prepare('DELETE FROM mobile_push_tokens WHERE user_id = ? AND token = ?').run(userId, token);
}

/** Logout: the signed-out phone must not receive this user's notifications any more. */
export function removeDevicePushTokens(deviceId: string): void {
  if (!deviceId) return;
  ensureSchema();
  db.prepare('DELETE FROM mobile_push_tokens WHERE device_id = ?').run(deviceId);
}

export function countPushTokens(userId: string): number {
  ensureSchema();
  const row = db.prepare('SELECT COUNT(*) AS n FROM mobile_push_tokens WHERE user_id = ?').get(userId) as { n: number } | undefined;
  return row?.n || 0;
}
