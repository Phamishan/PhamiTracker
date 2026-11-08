// Polls players' ranks and records every change as a match.

import { fetchApexMaps, fetchApexPlayer, fetchApexPredator, rankedMapAt } from "./apex.js";
import { pushLiveActivities, trackLiveSession } from "./live.js";
import { notifyFollowers, notifyGoals } from "./notify.js";
import { fetchValorantHistory, fetchValorantMatchDetails, fetchValorantPlayer } from "./valorant.js";
import { isApexAdjustment, nextPollDelay } from "./stats.js";

const DAY = 86_400_000;
export const FAVOURITE_POLL_MS = 5 * 60_000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Cron entry point: poll every player that is due, per game, within the rate budgets. */
export async function pollDue(env, now = Date.now()) {
  const activeSince = now - Number(env.INACTIVE_AFTER_DAYS ?? 21) * DAY;
  const due = async (game, limit) =>
    (
      await env.DB.prepare(
        `SELECT * FROM players WHERE game = ? AND next_poll_at <= ?
           AND (last_opened_at >= ? OR EXISTS (SELECT 1 FROM follows f WHERE f.player_id = players.id))
         ORDER BY next_poll_at LIMIT ?`,
      )
        .bind(game, now, activeSince, limit)
        .all()
    ).results;

  const [apex, valorant] = await Promise.all([
    due("apex", Number(env.APEX_POLLS_PER_RUN ?? 40)),
    due("valorant", Number(env.VALORANT_POLLS_PER_RUN ?? 8)),
  ]);

  // apexlegendsapi.com allows 2 requests/second; HenrikDev's limit is per minute and the cap
  // above already keeps us under it. Each game runs sequentially, both games in parallel.
  const run = async (players, gap) => {
    for (const player of players) {
      // The app or a widget may have polled them since this list was loaded.
      if (!(await claimPoll(env, player))) continue;
      await pollPlayer(env, player).catch((err) => console.error("poll failed", player.id, err));
      await sleep(gap);
    }
  };
  await Promise.all([run(apex, 550), run(valorant, 250)]);
  return { apex: apex.length, valorant: valorant.length };
}

/** Rows changed by a D1 run() (or node:sqlite's, in tests). */
export const changes = (result) => result?.meta?.changes ?? result?.changes ?? 0;

/**
 * Claims the player's next poll for this caller. The cron, the open app and every widget can ask
 * for the same player at the same moment; only the caller whose compare-and-set on last_polled_at
 * wins polls, the others use what's stored. Saves API calls and duplicate Live Activity pushes.
 */
export async function claimPoll(env, player, now = Date.now()) {
  const result = await env.DB.prepare("UPDATE players SET last_polled_at = ? WHERE id = ? AND last_polled_at IS ?")
    .bind(now, player.id, player.last_polled_at ?? null)
    .run();
  return changes(result) === 1;
}

/** Polls one player and stores the result. Returns the updated row. */
export async function pollPlayer(env, player) {
  const now = Date.now();
  const prevState = player.state ? JSON.parse(player.state) : null;
  try {
    const result = player.game === "apex"
      ? await pollApex(env, player, prevState, now)
      : await pollValorant(env, player, prevState, now);

    const changed = result.matches.length > 0;
    const lastChangeAt = changed ? now : player.last_change_at;
    // Players only tracked because someone favourited them: every 5 minutes is plenty.
    const favouriteOnly = (player.last_opened_at ?? 0) < now - Number(env.INACTIVE_AFTER_DAYS ?? 21) * DAY;
    const nextPollAt = now + Math.max(
      favouriteOnly ? FAVOURITE_POLL_MS : 0,
      nextPollDelay(player.game, { now, state: result.state, lastChangeAt, lastOpenedAt: player.last_opened_at }),
    );

    const statements = result.matches.map((m) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO matches (player_id, ts, delta, score_after, kind, detail, external_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(player.id, m.ts, m.delta, m.scoreAfter, m.kind, JSON.stringify(m.detail ?? {}), m.externalId ?? null),
    );
    statements.push(
      env.DB.prepare(
        `UPDATE players SET score = ?, state = ?, external_id = COALESCE(?, external_id),
           last_polled_at = ?, last_change_at = ?, next_poll_at = ?, error = NULL, error_count = 0
         WHERE id = ?`,
      ).bind(result.state.score, JSON.stringify(result.state), result.state.externalId, now, lastChangeAt, nextPollAt, player.id),
    );
    await env.DB.batch(statements);
    const updated = {
      ...player,
      score: result.state.score,
      state: JSON.stringify(result.state),
      last_polled_at: now,
      last_change_at: lastChangeAt,
      next_poll_at: nextPollAt,
      error: null,
      error_count: 0,
    };
    // Live Activity: start one when they start playing, push every new game to it.
    await trackLiveSession(env, updated, result.state, result.matches, now, { baseline: !prevState })
      .catch((err) => console.error("live session failed", err));
    if (changed) await pushLiveActivities(env, updated, now).catch((err) => console.error("live activity push failed", err));
    // Favourites: rank changes, streaks and session recaps for the people following them.
    await notifyFollowers(env, updated, prevState, result.state, result.matches, now)
      .catch((err) => console.error("follow notifications failed", err));
    // Their own rank goal, on the phone that set it.
    await notifyGoals(env, updated, player.score, now).catch((err) => console.error("goal notification failed", err));
    return updated;
  } catch (err) {
    const errorCount = (player.error_count ?? 0) + 1;
    const nextPollAt = now + nextPollDelay(player.game, { now, errorCount, rateLimited: err.status === 429 });
    await env.DB.prepare("UPDATE players SET error = ?, error_count = ?, next_poll_at = ?, last_polled_at = ? WHERE id = ?")
      .bind(String(err.message ?? err), errorCount, nextPollAt, now, player.id)
      .run();
    throw err;
  }
}

async function pollApex(env, player, prevState, now) {
  const state = await fetchApexPlayer(env, {
    name: prevState?.name ?? player.name,
    platform: player.platform,
    uid: player.external_id,
  });
  const matches = [];
  if (player.score != null && state.score !== player.score) {
    const delta = state.score - player.score;
    const kind = isApexAdjustment(delta, prevState, state) ? "adjust" : "match";
    const maps = kind === "match" ? await getApexMaps(env, now).catch(() => null) : null;
    matches.push({
      ts: now,
      delta,
      scoreAfter: state.score,
      kind,
      // The cron, the app and a widget can poll at the same moment and all see this change.
      // They share this key (same starting row), so INSERT OR IGNORE keeps exactly one.
      externalId: `apex:${player.last_change_at ?? 0}:${player.score}>${state.score}`,
      detail: {
        // The legend they were last seen in a match with is the one this RP came from.
        legend: (prevState?.status?.inGame && prevState.status.legend) || state.status.legend,
        map: rankedMapAt(maps, now),
        rank: rankLabel("apex", state),
      },
    });
  }
  return { state, matches };
}

async function pollValorant(env, player, prevState, now) {
  const account = {
    name: prevState?.name ?? player.name,
    tag: prevState?.tag ?? player.tag,
    region: player.region,
    platform: player.platform,
    puuid: player.external_id,
  };
  const state = await fetchValorantPlayer(env, account);
  state.historyCursor = prevState?.historyCursor ?? 0;
  // The score our recorded matches add up to. It only moves once mmr-history has the game.
  state.syncedScore = prevState ? prevState.syncedScore ?? null : null;
  state.pendingSince = prevState?.pendingSince ?? null;

  const changed = state.syncedScore == null
    || state.score !== state.syncedScore
    || state.rank.gamesNeeded !== prevState?.rank?.gamesNeeded;
  if (!changed) return { state, matches: [] };

  // The current-rank endpoint only knows the total; mmr-history has the game-by-game split.
  // If it fails we throw before saving anything, so the change is picked up next poll.
  const history = (await fetchValorantHistory(env, account))
    .filter((entry) => entry.matchId && Number.isFinite(entry.ts) && entry.ts > state.historyCursor);
  if (history.length === 0) {
    // History can trail the rank endpoint by a minute or two; keep retrying for a while.
    state.pendingSince ??= now;
    if (state.syncedScore == null || now - state.pendingSince > 15 * 60_000) {
      state.syncedScore = state.score;
      state.pendingSince = null;
    }
    return { state, matches: [] };
  }

  const details = await fetchValorantMatchDetails(env, { ...account, puuid: state.externalId })
    .catch(() => ({}));
  state.historyCursor = Math.max(...history.map((entry) => entry.ts));
  state.syncedScore = state.score;
  state.pendingSince = null;
  return {
    state,
    matches: history.map((entry) => ({
      ts: entry.ts,
      delta: entry.delta,
      scoreAfter: Number.isFinite(entry.eloAfter) ? entry.eloAfter : state.score,
      kind: "match",
      externalId: entry.matchId,
      detail: { map: entry.map, rank: entry.tier, ...(details[entry.matchId] ?? {}) },
    })),
  };
}

export function rankLabel(game, state) {
  if (!state) return null;
  if (game === "apex") {
    const { name, div } = state.rank;
    return div > 0 && !/master|predator/i.test(name) ? `${name} ${toRoman(div)}` : name;
  }
  return state.rank.name;
}

const toRoman = (n) => ["", "I", "II", "III", "IV"][n] ?? String(n);

/** Predator cutoffs per platform, cached for 15 minutes (they move slowly). */
export async function getApexPredator(env, now = Date.now()) {
  const cached = await env.DB.prepare("SELECT value, expires_at FROM cache WHERE key = 'apex:predator'").first();
  if (cached && cached.expires_at > now) return JSON.parse(cached.value);
  try {
    const cutoffs = await fetchApexPredator(env);
    await env.DB.prepare("INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES ('apex:predator', ?, ?)")
      .bind(JSON.stringify(cutoffs), now + 15 * 60_000)
      .run();
    return cutoffs;
  } catch (err) {
    console.error("predator lookup failed", err);
    return cached ? JSON.parse(cached.value) : null;
  }
}

/** Map rotation, cached in D1 until the next rotation (at most 5 minutes). */
export async function getApexMaps(env, now = Date.now()) {
  const cached = await env.DB.prepare("SELECT value, expires_at FROM cache WHERE key = 'apex:maps'").first();
  const previous = cached ? JSON.parse(cached.value) : null;
  if (previous && cached.expires_at > now) return previous;

  const maps = await fetchApexMaps(env);
  const previousRanked = previous?.ranked?.current?.map;
  maps.previousRanked = previousRanked && previousRanked !== maps.ranked?.current?.map
    ? previousRanked
    : previous?.previousRanked ?? null;

  const ends = [maps.battleRoyale?.current?.end, maps.ranked?.current?.end].filter((t) => t > now);
  const expiresAt = Math.max(now + 30_000, Math.min(now + 5 * 60_000, ...ends));
  await env.DB.prepare("INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES ('apex:maps', ?, ?)")
    .bind(JSON.stringify(maps), expiresAt)
    .run();
  return maps;
}
