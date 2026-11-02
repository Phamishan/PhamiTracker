// PhamiTracker API + poller.
//
//   POST   /v1/players                 link an account  {game, name, tag?, platform, region?}
//   GET    /v1/players/:id             dashboard summary  ?tzOffset=<min east of UTC>&days=&refresh=1
//   GET    /v1/players/:id/widget      compact payload for the iOS widgets  ?tzOffset=
//   DELETE /v1/players/:id             stop tracking
//   GET    /v1/apex/maps               Apex map rotation
//
// Every request needs `X-App-Key: <APP_KEY>`.

import { ApiError, APEX_PLATFORMS, fetchApexPlayer } from "./apex.js";
import { VALORANT_PLATFORMS, VALORANT_REGIONS, fetchValorantPlayer } from "./valorant.js";
import { getApexMaps, pollDue, pollPlayer, rankLabel } from "./poller.js";
import { summarize } from "./stats.js";

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
  },
};

async function route(request, env, ctx) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (url.pathname === "/v1/health") return json({ ok: true });
  if (env.APP_KEY && request.headers.get("x-app-key") !== env.APP_KEY) return fail(401, "Bad app key");

  if (parts[0] !== "v1") return fail(404, "Not found");
  if (parts[1] === "apex" && parts[2] === "maps" && request.method === "GET") {
    return json(await getApexMaps(env));
  }
  if (parts[1] !== "players") return fail(404, "Not found");

  if (parts.length === 2 && request.method === "POST") return createPlayer(request, env);

  const player = parts[2]
    ? await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(parts[2]).first()
    : null;
  if (!player) return fail(404, "Unknown player");

  if (parts.length === 3 && request.method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM matches WHERE player_id = ?").bind(player.id),
      env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player.id),
    ]);
    return json({ ok: true });
  }
  if (request.method !== "GET" || parts.length > 4 || (parts[3] && parts[3] !== "widget")) {
    return fail(404, "Not found");
  }

  const now = Date.now();
  const widget = parts[3] === "widget";
  const tzOffset = clamp(Number(url.searchParams.get("tzOffset")) || 0, -14 * 60, 14 * 60);
  const days = widget ? 1 : clamp(Number(url.searchParams.get("days")) || 14, 1, 60);

  // Opening the app or a widget refreshing keeps the player "active" for the poller, and gets
  // a live poll if the cron hasn't looked at them in the last few seconds.
  let fresh = player;
  const wantsRefresh = url.searchParams.get("refresh") === "1" || widget;
  if (wantsRefresh && now - (player.last_polled_at ?? 0) > REFRESH_AFTER_MS) {
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
  const stats = summarize(rows, fresh.score, { tzOffset, days, now });
  const base = {
    player: publicPlayer(fresh, state),
    score: fresh.score,
    rank: state?.rank ?? null,
    rankLabel: rankLabel(fresh.game, state),
    status: state?.status ?? null,
    today: stats.today,
    polledAt: fresh.last_polled_at,
    lastChangeAt: fresh.last_change_at,
    error: fresh.error,
    serverTime: now,
  };
  if (widget) return json(base);
  return json({
    ...base,
    level: state?.level ?? null,
    banner: state?.banner ?? null,
    history: stats.history,
    maps: stats.maps,
    matches: rows.slice(0, 30).map((row) => ({
      ts: row.ts,
      delta: row.delta,
      scoreAfter: row.score_after,
      kind: row.kind,
      ...row.detail,
    })),
    nextPollAt: fresh.next_poll_at,
  });
}

async function createPlayer(request, env) {
  const body = await request.json().catch(() => null);
  if (!body) return fail(400, "Expected JSON body");
  const game = body.game;
  const name = String(body.name ?? "").trim();
  if (!name) return fail(400, "name is required");

  let key;
  let snapshot;
  if (game === "apex") {
    const platform = String(body.platform ?? "PC").toUpperCase();
    if (!APEX_PLATFORMS.includes(platform)) return fail(400, `platform must be one of ${APEX_PLATFORMS}`);
    snapshot = await fetchApexPlayer(env, { name, platform });
    key = { game, platform, region: "", name, tag: "" };
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
  let player = await env.DB.prepare(
    "SELECT * FROM players WHERE game = ? AND platform = ? AND region = ? AND name = ? AND tag = ?",
  )
    .bind(lower.game, lower.platform, lower.region, lower.name, lower.tag)
    .first();

  if (!player) {
    const id = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO players (id, game, name, tag, platform, region, external_id, last_opened_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(id, lower.game, lower.name, lower.tag, lower.platform, lower.region, snapshot.externalId, now, now)
      .run();
    player = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first();
  }
  // First poll stores the snapshot (and for VALORANT backfills recent ranked games).
  player = await pollPlayer(env, player).catch(() => player);
  const state = player.state ? JSON.parse(player.state) : null;
  return json({ player: publicPlayer(player, state), rankLabel: rankLabel(player.game, state), score: player.score }, 201);
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
