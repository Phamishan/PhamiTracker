// Live Activities (lock screen + Dynamic Island), started and run from here so the player never
// has to open the app:
//
//  1. With the setting on, the app registers its push-to-start token for its linked players
//     (POST /v1/live/subscribe).
//  2. When the poller sees one of them start playing (Apex: in a match; VALORANT: a new ranked
//     game after a break) it opens a session and push-starts the activity on those phones.
//  3. The phone hands back the activity's own push token (POST /v1/players/:id/live-activity);
//     every game the poller records is pushed to it.
//  4. 45 minutes after the last game the session ends and the activity is closed.
//
// Secrets: APNS_KEY (the .p8 file's contents), APNS_KEY_ID, APNS_TEAM_ID.
// Var:     APNS_TOPIC (the app's bundle id, default phamishan.phamitracker).

import { rankLabel } from "./poller.js";

const MINUTES = 60_000;
const HOURS = 60 * MINUTES;
// iOS ends a Live Activity after 8 hours (12 on the lock screen); stop pushing after that.
export const LIVE_ACTIVITY_MAX_MS = 12 * HOURS;
// A session ends this long after the last game (or the last time Apex showed them in a match).
export const SESSION_IDLE_MS = 45 * MINUTES;
// VALORANT only shows up once a game is recorded; ignore backfilled games older than this.
const VALORANT_FRESH_MS = 30 * MINUTES;

const HEX_TOKEN = /^[0-9a-f]{32,256}$/;

export const liveActivitiesEnabled = (env) => Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID);

/** The app's push-to-start token, for these players. Replaces whatever the token had before. */
export async function subscribeLiveStart(env, body, now = Date.now()) {
  const token = String(body?.token ?? "").toLowerCase();
  if (!HEX_TOKEN.test(token)) return { error: "token must be the hex push token" };
  const ids = [...new Set((Array.isArray(body.players) ? body.players : []).map(String))].slice(0, 4);
  const known = ids.length
    ? (
        await env.DB.prepare(`SELECT id FROM players WHERE id IN (${ids.map(() => "?").join(",")})`)
          .bind(...ids)
          .all()
      ).results.map((row) => row.id)
    : [];
  await env.DB.batch([
    env.DB.prepare("DELETE FROM live_subscriptions WHERE start_token = ?").bind(token),
    ...known.map((id) =>
      env.DB.prepare("INSERT INTO live_subscriptions (start_token, player_id, sandbox, created_at) VALUES (?, ?, ?, ?)")
        .bind(token, id, body.sandbox ? 1 : 0, now),
    ),
  ]);
  return { ok: true, players: known, pushEnabled: liveActivitiesEnabled(env) };
}

export async function unsubscribeLiveStart(env, token) {
  await env.DB.prepare("DELETE FROM live_subscriptions WHERE start_token = ?").bind(String(token).toLowerCase()).run();
}

/** A running activity's own push token. Session start comes from the worker's session if there is one. */
export async function registerLiveActivity(env, player, body, now = Date.now()) {
  const token = String(body?.token ?? "").toLowerCase();
  if (!HEX_TOKEN.test(token)) return { error: "token must be the hex push token" };
  const session = await env.DB.prepare("SELECT * FROM live_sessions WHERE player_id = ?").bind(player.id).first();
  const startScore = session?.start_score ?? (Number.isFinite(body.startScore) ? body.startScore : player.score);
  await env.DB.prepare(
    `INSERT OR REPLACE INTO live_activities (token, player_id, sandbox, start_score, started_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(token, player.id, body.sandbox ? 1 : 0, startScore, session?.started_at ?? now)
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
  const state = typeof player.state === "string" ? JSON.parse(player.state) : player.state;
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

/** The activity's fixed details. Keys must match PhamiSessionAttributes in the Swift code. */
export function sessionAttributes(player, state) {
  const saved = typeof player.state === "string" ? JSON.parse(player.state) : player.state;
  const name = state?.name ?? saved?.name ?? player.name;
  const tag = player.game === "valorant" ? state?.tag ?? saved?.tag ?? player.tag : null;
  return {
    game: player.game,
    player: tag ? `${name}#${tag}` : name,
    unit: player.game === "apex" ? "RP" : "RR",
    playerId: player.id,
  };
}

/**
 * Called after every poll. Opens a session (and push-starts the activity on subscribed phones)
 * when the player starts playing, and keeps an open session alive while they play.
 */
export async function trackLiveSession(env, player, state, recorded, now = Date.now()) {
  const games = recorded.filter((m) => m.kind === "match");
  const inGame = player.game === "apex" && state?.status?.inGame === true;
  const fresh = player.game === "valorant" ? games.filter((m) => now - m.ts < VALORANT_FRESH_MS) : games;
  if (!inGame && fresh.length === 0) return null;

  const session = await env.DB.prepare("SELECT * FROM live_sessions WHERE player_id = ?").bind(player.id).first();
  if (session) {
    await env.DB.prepare("UPDATE live_sessions SET last_activity_at = ? WHERE player_id = ?").bind(now, player.id).run();
    return "continued";
  }

  const subscriptions = (
    await env.DB.prepare("SELECT * FROM live_subscriptions WHERE player_id = ?").bind(player.id).all()
  ).results;
  if (subscriptions.length === 0) return null;

  const startScore = (player.score ?? 0) - fresh.reduce((sum, m) => sum + m.delta, 0);
  const startedAt = fresh.length ? Math.min(...fresh.map((m) => m.ts)) : now;
  await env.DB.prepare(
    "INSERT OR REPLACE INTO live_sessions (player_id, started_at, start_score, last_activity_at) VALUES (?, ?, ?, ?)",
  )
    .bind(player.id, startedAt, startScore, now)
    .run();
  if (!liveActivitiesEnabled(env)) return "started";

  const payload = {
    aps: {
      timestamp: Math.floor(now / 1000),
      event: "start",
      "content-state": sessionState(player, startScore, fresh, now),
      "attributes-type": "PhamiSessionAttributes",
      attributes: sessionAttributes(player, state),
      "stale-date": Math.floor((now + 2 * HOURS) / 1000),
      alert: {
        title: player.game === "apex" ? "Apex session started" : "VALORANT session started",
        body: "Tracking your ranked games on the lock screen.",
      },
    },
  };
  for (const sub of subscriptions) {
    const res = await sendApns(env, { token: sub.start_token, sandbox: sub.sandbox }, payload, now);
    if (!res.ok && (res.status === 410 || /BadDeviceToken|ExpiredToken|Unregistered/.test(res.reason ?? ""))) {
      await unsubscribeLiveStart(env, sub.start_token);
    } else if (!res.ok) {
      console.error("APNs rejected live activity start", res.status, res.reason);
    }
  }
  return "started";
}

/** Cron: close sessions that have gone quiet, and the activities showing them. */
export async function endIdleSessions(env, now = Date.now()) {
  const idle = (
    await env.DB.prepare("SELECT * FROM live_sessions WHERE last_activity_at < ?").bind(now - SESSION_IDLE_MS).all()
  ).results;
  for (const session of idle) {
    const player = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(session.player_id).first();
    const activities = (
      await env.DB.prepare("SELECT * FROM live_activities WHERE player_id = ?").bind(session.player_id).all()
    ).results;
    if (player && activities.length && liveActivitiesEnabled(env)) {
      const games = (
        await env.DB.prepare("SELECT ts, delta, kind, detail FROM matches WHERE player_id = ? AND ts >= ? ORDER BY ts")
          .bind(player.id, session.started_at)
          .all()
      ).results;
      const payload = {
        aps: {
          timestamp: Math.floor(now / 1000),
          event: "end",
          "content-state": sessionState(player, session.start_score, games, now),
          // Leave the final numbers up for a bit, then clear it.
          "dismissal-date": Math.floor((now + 15 * MINUTES) / 1000),
        },
      };
      for (const activity of activities) await sendApns(env, activity, payload, now).catch(() => null);
    }
    await env.DB.batch([
      env.DB.prepare("DELETE FROM live_activities WHERE player_id = ?").bind(session.player_id),
      env.DB.prepare("DELETE FROM live_sessions WHERE player_id = ?").bind(session.player_id),
    ]);
  }
  return idle.length;
}

/** New games: push the numbers to every activity showing this player. */
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

export async function sendApns(env, target, payload, now) {
  const host = target.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${target.token}`, {
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
