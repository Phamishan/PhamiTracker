// Live Activities (lock screen + Dynamic Island). The app starts an activity for a session and
// registers its ActivityKit push token here; each game the poller records is then pushed straight
// to the phone through APNs, so it updates with the app closed.
//
// Secrets: APNS_KEY (the .p8 file's contents), APNS_KEY_ID, APNS_TEAM_ID.
// Var:     APNS_TOPIC (the app's bundle id, default phamishan.phamitracker).

import { rankLabel } from "./poller.js";

const HOURS = 60 * 60_000;
// iOS ends a Live Activity after 8 hours (12 on the lock screen); stop pushing after that.
export const LIVE_ACTIVITY_MAX_MS = 12 * HOURS;

export const liveActivitiesEnabled = (env) => Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID);

export async function registerLiveActivity(env, player, body, now = Date.now()) {
  const token = String(body?.token ?? "").toLowerCase();
  if (!/^[0-9a-f]{32,256}$/.test(token)) return { error: "token must be the hex push token" };
  await env.DB.prepare(
    `INSERT OR REPLACE INTO live_activities (token, player_id, sandbox, start_score, started_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(token, player.id, body.sandbox ? 1 : 0, Number.isFinite(body.startScore) ? body.startScore : player.score, now)
    .run();
  return { ok: true, pushEnabled: liveActivitiesEnabled(env) };
}

export async function endLiveActivity(env, player, token) {
  await env.DB.prepare("DELETE FROM live_activities WHERE token = ? AND player_id = ?")
    .bind(String(token).toLowerCase(), player.id)
    .run();
}

/** What the activity shows. Field names must match ContentState in the Swift code. */
export function sessionState(player, startScore, games, now) {
  const state = player.state ? JSON.parse(player.state) : null;
  const played = games.filter((m) => m.kind === "match");
  const won = (m) => {
    const detail = typeof m.detail === "string" ? JSON.parse(m.detail || "{}") : m.detail ?? {};
    return detail.won ?? (m.delta > 0);
  };
  return {
    score: player.score ?? 0,
    rank: rankLabel(player.game, state) ?? "",
    sessionDelta: (player.score ?? 0) - (startScore ?? player.score ?? 0),
    games: played.length,
    wins: played.filter(won).length,
    losses: played.filter((m) => !won(m)).length,
    lastDelta: played.at(-1)?.delta ?? 0,
    updatedAt: Math.floor(now / 1000),
  };
}

export async function pushLiveActivities(env, player, now = Date.now()) {
  if (!liveActivitiesEnabled(env)) return 0;
  const activities = (
    await env.DB.prepare("SELECT * FROM live_activities WHERE player_id = ? AND started_at > ?")
      .bind(player.id, now - LIVE_ACTIVITY_MAX_MS)
      .all()
  ).results;
  let sent = 0;
  for (const activity of activities) {
    const games = (
      await env.DB.prepare("SELECT ts, delta, kind, detail FROM matches WHERE player_id = ? AND ts >= ? ORDER BY ts")
        .bind(player.id, activity.started_at)
        .all()
    ).results;
    const payload = {
      aps: {
        timestamp: Math.floor(now / 1000),
        event: "update",
        "content-state": sessionState(player, activity.start_score, games, now),
        // Grey it out if nothing new arrives for two hours.
        "stale-date": Math.floor((now + 2 * HOURS) / 1000),
      },
    };
    const res = await sendApns(env, activity, payload, now);
    if (res.ok) sent++;
    else if (res.status === 410 || /BadDeviceToken|ExpiredToken|Unregistered/.test(res.reason ?? "")) {
      await endLiveActivity(env, player, activity.token);
    } else {
      console.error("APNs rejected live activity push", res.status, res.reason);
    }
  }
  return sent;
}

let cachedJwt = null;

/** The ES256 provider token APNs wants. Apple allows reusing one for up to an hour. */
export async function apnsJwt(env, now = Date.now()) {
  if (cachedJwt && cachedJwt.keyId === env.APNS_KEY_ID && cachedJwt.expires > now) return cachedJwt.token;
  const pem = String(env.APNS_KEY).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const b64url = (bytes) =>
    btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const part = (obj) => b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const input = `${part({ alg: "ES256", kid: env.APNS_KEY_ID })}.${part({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })}`;
  // Web Crypto returns the raw r||s signature, which is the JWS format.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  const token = `${input}.${b64url(signature)}`;
  cachedJwt = { token, keyId: env.APNS_KEY_ID, expires: now + 50 * 60_000 };
  return token;
}

async function sendApns(env, activity, payload, now) {
  const host = activity.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${activity.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt(env, now)}`,
      "apns-topic": `${env.APNS_TOPIC || "phamishan.phamitracker"}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10_000),
  });
  const reason = res.ok ? null : (await res.json().catch(() => null))?.reason ?? null;
  return { ok: res.ok, status: res.status, reason };
}
