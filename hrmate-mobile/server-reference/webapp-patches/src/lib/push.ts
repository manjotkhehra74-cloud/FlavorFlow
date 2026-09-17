import webpush from "web-push";
import db from "./db";
import { isNotifyEnabled } from "./prefs";
import { sendFcmToUser } from "./fcm";

const VAPID_PUBLIC =
  process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ||
  "BHUrFAr3YbwEoBtkBLgsHS4UTPk0ABs8U47F90ZbVgezp_cvL50t7pD8BSW2Gjd1cLdXdQtm4fbD7oZqu1s9Iz8";
const VAPID_PRIVATE =
  process.env.VAPID_PRIVATE_KEY || "j5FLZFuvPjmYrkWy77Vuqvf4SKJLaJl7AZQPKOH2fRc";

webpush.setVapidDetails(
  "mailto:admin@hrmate.com",
  VAPID_PUBLIC,
  VAPID_PRIVATE
);

export function getVapidPublicKey(): string {
  return VAPID_PUBLIC;
}

interface PushSubscriptionRow {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export function saveSubscription(userId: string, sub: {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}) {
  db.prepare(
    `INSERT OR REPLACE INTO push_subscriptions (id, user_id, endpoint, p256dh, auth, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(
    sub.endpoint,
    userId,
    sub.endpoint,
    sub.keys.p256dh,
    sub.keys.auth,
    Date.now()
  );
}

export function removeSubscription(userId: string, endpoint: string) {
  db.prepare("DELETE FROM push_subscriptions WHERE user_id = ? AND endpoint = ?").run(
    userId,
    endpoint
  );
}

export async function sendPushToUser(
  userId: string,
  payload: { title: string; body: string; link?: string }
) {
  if (!isNotifyEnabled(userId)) return;

  // Phase 6 (native app): the same notification also goes to the user's phones via
  // FCM. Runs alongside web push, is a no-op until the server has its FCM key, and
  // never throws — nothing else in this function changed.
  const fcm = sendFcmToUser(userId, payload).catch(() => undefined);

  const subs = db
    .prepare("SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE user_id = ?")
    .all(userId) as PushSubscriptionRow[];

  const results = await Promise.allSettled(
    subs.map((s) =>
      webpush.sendNotification(
        {
          endpoint: s.endpoint,
          keys: { p256dh: s.p256dh, auth: s.auth },
        },
        JSON.stringify({
          title: payload.title,
          body: payload.body,
          icon: "/icon.png",
          badge: "/icon.png",
          data: { url: payload.link || "/dashboard" },
        })
      )
    )
  );

  // Clean up expired subscriptions
  results.forEach((r, i) => {
    if (r.status === "rejected") {
      const code = (r.reason as any)?.statusCode;
      if (code === 404 || code === 410) {
        db.prepare("DELETE FROM push_subscriptions WHERE endpoint = ?").run(subs[i].endpoint);
      }
    }
  });

  await fcm;
}

export async function sendPushToMany(
  userIds: string[],
  payload: { title: string; body: string; link?: string }
) {
  await Promise.all(userIds.map((id) => sendPushToUser(id, payload)));
}
