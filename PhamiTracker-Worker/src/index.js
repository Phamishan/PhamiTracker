// PhamiTracker API + poller.
//
//   POST   /v1/players                 link an account  {game, name, tag?, platform, region?, uid?}
//                                      (Apex: `uid` instead of `name` links that exact account)
//   GET    /v1/players/:id             dashboard summary  ?tzOffset=<min east of UTC>&days=&refresh=1
//   GET    /v1/players/:id/widget      compact payload for the iOS widgets  ?tzOffset=
//   GET    /v1/players/:id/history     daily scores for the climb chart  ?days=<n, 0 = all time>&tzOffset=
//   DELETE /v1/players/:id             stop tracking
//   POST   /v1/live/subscribe          auto Live Activities: push-to-start token  {token, sandbox?, players: [ids]}
//   DELETE /v1/live/subscribe/:token   setting turned off
//   POST   /v1/players/:id/live-activity          register a Live Activity push token  {token, sandbox?, startScore?}
//   DELETE /v1/players/:id/live-activity/:token   the activity ended
//   GET    /v1/apex/maps               Apex map rotation
//   GET    /v1/apex/season             Current season + ranked split dates
//   GET    /v1/valorant/matches/:id    full scoreboard for one VALORANT match  ?region=
//   GET    /v1/search                  look anyone up without tracking them
//                                      ?game=&name=&tag=&platform=&region=&tzOffset=
//
// Every request needs `X-App-Key: <APP_KEY>`.

import { ApiError, APEX_PLATFORMS, fetchApexPlayer } from "./apex.js";
import {
  VALORANT_PLATFORMS,
  VALORANT_REGIONS,
  fetchValorantHistory,
  fetchValorantMatch,
  fetchValorantMatchDetails,
  fetchValorantPlayer,
  valorantTierIcon,
} from "./valorant.js";
import {
  LIVE_ACTIVITY_MAX_MS,
  endIdleSessions,
  endLiveActivity,
  registerLiveActivity,
  subscribeLiveStart,
  unsubscribeLiveStart,
} from "./live.js";
import { currentPeriod } from "./periods.js";
import { claimPoll, getApexMaps, getApexPredator, pollDue, pollPlayer, rankLabel } from "./poller.js";
import { getApexSeason } from "./seasons.js";
import { characterStats, periodStats, summarize } from "./stats.js";

const DAY = 86_400_000;
// An app/widget asking for data more than this long after the last poll triggers a live poll.
const REFRESH_AFTER_MS = 20_000;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

const fail = (status, message) => json({ error: message }, status);

export default {
  async fetch(request, env, ctx) {
    try {
      return await route(request, env, ctx);
    } catch (err) {
      if (err instanceof ApiError) return fail(err.status, err.message);
      console.error(err);
      return fail(500, "Internal error");
    }
  },

  async scheduled(controller, env, ctx) {
    ctx.waitUntil(pollDue(env, controller.scheduledTime).then((counts) => console.log("polled", counts)));
    // Every minute: Live Activity sessions should end on time (it's only a read when none are idle).
    ctx.waitUntil(endIdleSessions(env, controller.scheduledTime).catch((err) => console.error("ending sessions failed", err)));
    // Every 15 minutes: housekeeping nobody sees. Expired searches are never served (reads check
    // the expiry) and activities older than 12 hours are never pushed to.
    if (isTidyMinute(controller.scheduledTime)) {
      ctx.waitUntil(
        env.DB.prepare("DELETE FROM cache WHERE (key LIKE 'search:%' OR key LIKE 'match:%') AND expires_at < ?")
          .bind(controller.scheduledTime)
          .run(),
      );
      ctx.waitUntil(
        env.DB.prepare("DELETE FROM live_activities WHERE started_at < ?")
          .bind(controller.scheduledTime - LIVE_ACTIVITY_MAX_MS)
          .run(),
      );
    }
  },
};

async function route(request, env, ctx) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (url.pathname === "/v1/health") return json({ ok: true });
  if (env.APP_KEY && request.headers.get("x-app-key") !== env.APP_KEY) return fail(401, "Bad app key");

  if (parts[0] !== "v1") return fail(404, "Not found");
  if (parts[1] === "apex" && parts[2] === "season" && request.method === "GET") {
    return json(await getApexSeason(env));
  }
  if (parts[1] === "apex" && parts[2] === "maps" && request.method === "GET") {
    return json(await getApexMaps(env));
  }
  if (parts[1] === "valorant" && parts[2] === "matches" && parts[3] && parts.length === 4 && request.method === "GET") {
    return valorantMatch(env, parts[3], url);
  }
  if (parts[1] === "live" && parts[2] === "subscribe") {
    if (parts.length === 3 && request.method === "POST") {
      const result = await subscribeLiveStart(env, await request.json().catch(() => null));
      return result.error ? fail(400, result.error) : json(result);
    }
    if (parts.length === 4 && request.method === "DELETE") {
      await unsubscribeLiveStart(env, parts[3]);
      return json({ ok: true });
    }
    return fail(404, "Not found");
  }
  if (parts[1] === "search" && parts.length === 2 && request.method === "GET") return search(env, url);
  if (parts[1] !== "players") return fail(404, "Not found");

  if (parts.length === 2 && request.method === "POST") return createPlayer(request, env);

  const player = parts[2]
    ? await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(parts[2]).first()
    : null;
  if (!player) return fail(404, "Unknown player");

  if (parts.length === 3 && request.method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM live_activities WHERE player_id = ?").bind(player.id),
      env.DB.prepare("DELETE FROM live_subscriptions WHERE player_id = ?").bind(player.id),
      env.DB.prepare("DELETE FROM live_sessions WHERE player_id = ?").bind(player.id),
      env.DB.prepare("DELETE FROM matches WHERE player_id = ?").bind(player.id),
      env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player.id),
    ]);
    return json({ ok: true });
  }
  if (parts[3] === "live-activity") {
    if (parts.length === 4 && request.method === "POST") {
      const result = await registerLiveActivity(env, player, await request.json().catch(() => null));
      return result.error ? fail(400, result.error) : json(result, 201);
    }
    if (parts.length === 5 && request.method === "DELETE") {
      await endLiveActivity(env, player, parts[4]);
      return json({ ok: true });
    }
    return fail(404, "Not found");
  }
  if (request.method !== "GET" || parts.length > 4 || (parts[3] && !["widget", "history"].includes(parts[3]))) {
    return fail(404, "Not found");
  }

  const now = Date.now();
  const widget = parts[3] === "widget";
  const tzOffset = clamp(Number(url.searchParams.get("tzOffset")) || 0, -14 * 60, 14 * 60);
  if (parts[3] === "history") return history(env, player, url, { now, tzOffset });
  const days = widget ? 7 : clamp(Number(url.searchParams.get("days")) || 14, 1, 60);

  // Opening the app or a widget refreshing keeps the player "active" for the poller, and gets
  // a live poll if the cron hasn't looked at them in the last few seconds.
  let fresh = player;
  const wantsRefresh = url.searchParams.get("refresh") === "1" || widget;
  // If another request (or the cron) is already polling them, use what's stored.
  if (wantsRefresh && now - (player.last_polled_at ?? 0) > REFRESH_AFTER_MS && (await claimPoll(env, player, now))) {
    fresh = await pollPlayer(env, player).catch(() => player);
  }
  ctx.waitUntil(
    env.DB.prepare("UPDATE players SET last_opened_at = ?, next_poll_at = MIN(next_poll_at, ?) WHERE id = ?")
      .bind(now, now + 60_000, player.id)
      .run(),
  );

  const rows = (
    await env.DB.prepare(
      "SELECT ts, delta, score_after, kind, detail FROM matches WHERE player_id = ? AND ts >= ? ORDER BY ts DESC",
    )
      .bind(player.id, now - (days + 1) * DAY)
      .all()
  ).results.map((row) => ({ ...row, detail: row.detail ? JSON.parse(row.detail) : {} }));

  const state = fresh.state ? JSON.parse(fresh.state) : null;
  const season = fresh.game === "apex" ? await getApexSeason(env, now) : null;
  const stats = summarize(rows, fresh.score, { tzOffset, days, now });
  const base = {
    player: publicPlayer(fresh, state),
    score: fresh.score,
    rank: state?.rank
      ? { ...state.rank, image: state.rank.image ?? (fresh.game === "valorant" ? valorantTierIcon(state.rank.tier) : null) }
      : null,
    rankLabel: rankLabel(fresh.game, state),
    status: state?.status ?? null,
    today: stats.today,
    history: stats.history,
    polledAt: fresh.last_polled_at,
    lastChangeAt: fresh.last_change_at,
    error: fresh.error,
    season,
    serverTime: now,
  };
  // The match list isn't tied to the stats window: the app scrolls back through the last 100.
  const recent = (
    await env.DB.prepare(
      "SELECT ts, delta, score_after, kind, detail, external_id FROM matches WHERE player_id = ? ORDER BY ts DESC LIMIT ?",
    )
      .bind(player.id, widget ? 5 : 100)
      .all()
  ).results.map((row) => ({ ...row, detail: row.detail ? JSON.parse(row.detail) : {} }));
  const matches = (limit) =>
    recent.slice(0, limit).map((row) => ({
      matchId: row.external_id ?? null,
      ts: row.ts,
      delta: row.delta,
      scoreAfter: row.score_after,
      kind: row.kind,
      ...row.detail,
    }));
  if (widget) return json({ ...base, matches: matches(5) });

  // Split/act recap and records, plus the one before it for a couple of weeks after a reset.
  const period = await currentPeriod(env, fresh.game, now, season).catch(() => null);
  const since = Math.min(period?.start ?? now, period?.previous?.start ?? Infinity);
  const periodRows = period
    ? (
        await env.DB.prepare(
          "SELECT ts, delta, score_after, kind, detail FROM matches WHERE player_id = ? AND ts >= ? ORDER BY ts",
        )
          .bind(player.id, since)
          .all()
      ).results.map((row) => ({ ...row, detail: row.detail ? JSON.parse(row.detail) : {} }))
    : [];
  const inCurrent = periodRows.filter((m) => m.ts >= period?.start);
  const prev = period?.previous;
  const inPrevious = prev ? periodRows.filter((m) => m.ts >= prev.start && m.ts < (prev.end ?? period.start)) : [];
  const split = period ? { kind: period.kind, name: period.name, start: period.start, end: period.end, ...periodStats(inCurrent, { tzOffset }) } : null;
  const previousSplit =
    prev && now - period.start < 14 * DAY && inPrevious.some((m) => m.kind === "match")
      ? { kind: period.kind, name: prev.name, start: prev.start, end: prev.end, ...periodStats(inPrevious, { tzOffset }) }
      : null;
  const predator = fresh.game === "apex" ? (await getApexPredator(env, now))?.[fresh.platform] ?? null : null;

  return json({
    ...base,
    level: state?.level ?? null,
    banner: state?.banner ?? null,
    maps: stats.maps,
    characters: characterStats(inCurrent.length ? inCurrent : rows),
    split,
    previousSplit,
    predator,
    matches: matches(100),
    nextPollAt: fresh.next_poll_at,
  });
}

/** Daily scores for the climb chart. `days=0` means everything since the account was linked. */
async function history(env, player, url, { now, tzOffset }) {
  const requested = Number(url.searchParams.get("days"));
  const sinceLinked = Math.floor((now - player.created_at) / DAY) + 1; // + today
  const days = clamp(requested > 0 ? requested : Math.max(sinceLinked, 7), 1, 3650);
  const rows = (
    await env.DB.prepare("SELECT ts, delta, score_after, kind FROM matches WHERE player_id = ? AND ts >= ?")
      .bind(player.id, now - (days + 1) * DAY)
      .all()
  ).results;
  return json({ days, history: summarize(rows, player.score, { tzOffset, days, now }).history });
}

async function createPlayer(request, env) {
  const body = await request.json().catch(() => null);
  if (!body) return fail(400, "Expected JSON body");
  const game = body.game;
  const name = String(body.name ?? "").trim();
  // Apex names aren't unique, so a uid is the only way to be sure which account gets linked.
  const uid = game === "apex" ? String(body.uid ?? "").trim() : "";
  if (!name && !uid) return fail(400, "name is required");

  let key;
  let snapshot;
  if (game === "apex") {
    const platform = String(body.platform ?? "PC").toUpperCase();
    if (!APEX_PLATFORMS.includes(platform)) return fail(400, `platform must be one of ${APEX_PLATFORMS}`);
    snapshot = await fetchApexPlayer(env, { name, platform, uid: uid || undefined });
    key = { game, platform, region: "", name: uid ? snapshot.name ?? uid : name, tag: "" };
  } else if (game === "valorant") {
    const tag = String(body.tag ?? "").trim().replace(/^#/, "");
    const region = String(body.region ?? "eu").toLowerCase();
    const platform = String(body.platform ?? "pc").toLowerCase();
    if (!tag) return fail(400, "tag is required");
    if (!VALORANT_REGIONS.includes(region)) return fail(400, `region must be one of ${VALORANT_REGIONS}`);
    if (!VALORANT_PLATFORMS.includes(platform)) return fail(400, `platform must be one of ${VALORANT_PLATFORMS}`);
    snapshot = await fetchValorantPlayer(env, { name, tag, region, platform });
    key = { game, platform, region, name, tag };
  } else {
    return fail(400, "game must be apex or valorant");
  }

  const now = Date.now();
  const lower = { ...key, name: key.name.toLowerCase(), tag: key.tag.toLowerCase() };
  let player = uid
    ? await env.DB.prepare("SELECT * FROM players WHERE game = ? AND platform = ? AND external_id = ?")
        .bind(lower.game, lower.platform, snapshot.externalId)
        .first()
    : null;
  if (!player) {
    player = await env.DB.prepare(
      "SELECT * FROM players WHERE game = ? AND platform = ? AND region = ? AND name = ? AND tag = ?",
    )
      .bind(lower.game, lower.platform, lower.region, lower.name, lower.tag)
      .first();
    // Same name, different account: don't hand back someone else's history.
    if (player && uid && player.external_id && player.external_id !== snapshot.externalId) {
      return fail(409, `"${key.name}" is already linked to a different account`);
    }
  }

  if (!player) {
    const id = crypto.randomUUID();
    // OR IGNORE: a second link request for the same new account (a double tap) lands here too.
    await env.DB.prepare(
      `INSERT OR IGNORE INTO players (id, game, name, tag, platform, region, external_id, last_opened_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(id, lower.game, lower.name, lower.tag, lower.platform, lower.region, snapshot.externalId, now, now)
      .run();
    player =
      (await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first()) ??
      (await env.DB.prepare(
        "SELECT * FROM players WHERE game = ? AND platform = ? AND region = ? AND name = ? AND tag = ?",
      )
        .bind(lower.game, lower.platform, lower.region, lower.name, lower.tag)
        .first());
  }
  // First poll stores the snapshot (and for VALORANT backfills recent ranked games).
  player = await pollPlayer(env, player).catch(() => player);
  const state = player.state ? JSON.parse(player.state) : null;
  return json({ player: publicPlayer(player, state), rankLabel: rankLabel(player.game, state), score: player.score }, 201);
}

// A finished match never changes, so its scoreboard is kept for a week.
const MATCH_CACHE_MS = 7 * DAY;

/** Scoreboard for one VALORANT match: every player's agent, rank and stats. */
async function valorantMatch(env, matchId, url) {
  if (!/^[0-9a-f-]{36}$/i.test(matchId)) return fail(400, "Bad match id");
  const region = String(url.searchParams.get("region") ?? "eu").toLowerCase();
  if (!VALORANT_REGIONS.includes(region)) return fail(400, `region must be one of ${VALORANT_REGIONS}`);
  const key = `match:valorant:${matchId.toLowerCase()}`;
  const now = Date.now();
  const cached = await env.DB.prepare("SELECT value, expires_at FROM cache WHERE key = ?").bind(key).first();
  if (cached && cached.expires_at > now) return json(JSON.parse(cached.value));

  const match = await fetchValorantMatch(env, { region, matchId });
  await env.DB.prepare("INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?, ?, ?)")
    .bind(key, JSON.stringify(match), now + MATCH_CACHE_MS)
    .run();
  return json(match);
}

// Searches hit the game APIs directly, so repeat lookups of the same player are cached briefly.
const SEARCH_CACHE_MS = 60_000;

/**
 * A player page for anyone, without linking them. Shaped like the summary so the app can reuse
 * its dashboard. If someone already tracks this account, their recorded matches fill it in;
 * otherwise Apex shows the live rank only, and VALORANT builds it from HenrikDev's recent games.
 */
async function search(env, url) {
  const q = (key) => String(url.searchParams.get(key) ?? "").trim();
  const game = q("game");
  const name = q("name");
  const tzOffset = clamp(Number(url.searchParams.get("tzOffset")) || 0, -14 * 60, 14 * 60);
  if (!name) return fail(400, "name is required");

  let account;
  if (game === "apex") {
    const platform = (q("platform") || "PC").toUpperCase();
    if (!APEX_PLATFORMS.includes(platform)) return fail(400, `platform must be one of ${APEX_PLATFORMS}`);
    account = { game, platform, region: "", name, tag: "" };
  } else if (game === "valorant") {
    const tag = q("tag").replace(/^#/, "");
    const region = (q("region") || "eu").toLowerCase();
    const platform = (q("platform") || "pc").toLowerCase();
    if (!tag) return fail(400, "tag is required");
    if (!VALORANT_REGIONS.includes(region)) return fail(400, `region must be one of ${VALORANT_REGIONS}`);
    if (!VALORANT_PLATFORMS.includes(platform)) return fail(400, `platform must be one of ${VALORANT_PLATFORMS}`);
    account = { game, platform, region, name, tag };
  } else {
    return fail(400, "game must be apex or valorant");
  }

  const now = Date.now();
  const cacheKey = `search:${[game, account.platform, account.region, name, account.tag].join(":").toLowerCase()}:${tzOffset}`;
  const cached = await env.DB.prepare("SELECT value, expires_at FROM cache WHERE key = ?").bind(cacheKey).first();
  if (cached && cached.expires_at > now) return json({ ...JSON.parse(cached.value), serverTime: now });

  const state = game === "apex"
    ? await fetchApexPlayer(env, account)
    : await fetchValorantPlayer(env, account);

  // Someone tracks this account already: use what the poller has recorded.
  const tracked = state.externalId
    ? await env.DB.prepare("SELECT id FROM players WHERE game = ? AND external_id = ? ORDER BY created_at LIMIT 1")
        .bind(game, state.externalId)
        .first()
    : null;
  let rows = tracked
    ? (
        await env.DB.prepare(
          "SELECT ts, delta, score_after, kind, detail, external_id FROM matches WHERE player_id = ? ORDER BY ts DESC LIMIT 100",
        )
          .bind(tracked.id)
          .all()
      ).results.map((row) => ({ ...row, detail: row.detail ? JSON.parse(row.detail) : {} }))
    : [];

  if (!tracked && game === "valorant") {
    const full = { ...account, name: state.name ?? name, tag: state.tag ?? account.tag };
    const [history, details] = await Promise.all([
      fetchValorantHistory(env, full).catch(() => []),
      fetchValorantMatchDetails(env, { ...full, puuid: state.externalId }).catch(() => ({})),
    ]);
    rows = history
      .filter((entry) => Number.isFinite(entry.ts))
      .map((entry) => ({
        ts: entry.ts,
        delta: entry.delta,
        score_after: Number.isFinite(entry.eloAfter) ? entry.eloAfter : state.score,
        kind: "match",
        external_id: entry.matchId,
        detail: { map: entry.map, rank: entry.tier, ...(details[entry.matchId] ?? {}) },
      }));
  }

  const stats = summarize(rows, state.score, { tzOffset, days: 14, now });
  const body = {
    player: {
      id: null,
      game,
      name: state.name ?? name,
      tag: game === "valorant" ? state.tag ?? account.tag : null,
      platform: account.platform,
      region: account.region || null,
    },
    score: state.score,
    rank: state.rank,
    rankLabel: rankLabel(game, state),
    status: state.status ?? null,
    today: stats.today,
    // Without any recorded games the "climb" is just a flat line, so leave it out.
    history: rows.length ? stats.history : [],
    maps: stats.maps,
    matches: rows.map((row) => ({
      matchId: row.external_id ?? null,
      ts: row.ts,
      delta: row.delta,
      scoreAfter: row.score_after,
      kind: row.kind,
      ...row.detail,
    })),
    characters: characterStats(rows),
    predator: game === "apex" ? (await getApexPredator(env, now).catch(() => null))?.[account.platform] ?? null : null,
    level: state.level ?? null,
    banner: state.banner ?? null,
    season: game === "apex" ? await getApexSeason(env, now).catch(() => null) : null,
    tracked: Boolean(tracked),
    polledAt: now,
  };
  await env.DB.prepare("INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?, ?, ?)")
    .bind(cacheKey, JSON.stringify(body), now + SEARCH_CACHE_MS)
    .run();
  return json({ ...body, serverTime: now });
}

function publicPlayer(row, state) {
  return {
    id: row.id,
    game: row.game,
    name: state?.name ?? row.name,
    tag: row.game === "valorant" ? state?.tag ?? row.tag : null,
    platform: row.platform,
    region: row.region || null,
  };
}

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

/** The cron runs every minute; housekeeping only on :00, :15, :30 and :45. */
export const isTidyMinute = (time) => new Date(time).getUTCMinutes() % 15 === 0;
