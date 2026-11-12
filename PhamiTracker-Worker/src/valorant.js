// HenrikDev VALORANT API client + normalizers. https://docs.henrikdev.xyz

import { ApiError } from "./apex.js";

const BASE = "https://api.henrikdev.xyz/valorant";

export const VALORANT_REGIONS = ["eu", "na", "ap", "kr", "latam", "br"];
export const VALORANT_PLATFORMS = ["pc", "console"];

// HenrikDev doesn't return rank art, so use valorant-api.com's icons for the current tier set.
const TIER_ICONS =
  "https://media.valorant-api.com/competitivetiers/03621f52-342b-cf4e-4f86-9350a49c6d04";
export const valorantTierIcon = (tier) =>
  tier > 0 ? `${TIER_ICONS}/${tier}/largeicon.png` : null;

async function call(env, path, query = {}) {
  if (!env.HENRIK_API_KEY)
    throw new ApiError("HENRIK_API_KEY is not set", { retryable: false });
  const url = new URL(BASE + path);
  for (const [key, value] of Object.entries(query))
    url.searchParams.set(key, value);
  const res = await fetch(url, {
    headers: { Authorization: env.HENRIK_API_KEY },
    signal: AbortSignal.timeout(10_000),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const message =
      body?.errors?.[0]?.message ?? `HenrikDev API returned ${res.status}`;
    throw new ApiError(message, {
      status: res.status === 404 ? 404 : res.status === 429 ? 429 : 502,
      retryable: res.status !== 404,
    });
  }
  return body?.data;
}

const seg = (value) => encodeURIComponent(value);

/**
 * The player's rank. HenrikDev answers "Not able to fetch needed resource to build response" when
 * it can't build a rank for the account in that region: it plays in another region, or has no
 * ranked data (unrated, or not played for a long time). Then look the account itself up, which
 * says where it plays and whether it exists, and retry there. With `allowUnrated` (search), an
 * account that exists but has no rank comes back as an unrated profile instead of an error.
 */
export async function fetchValorantPlayer(
  env,
  { name, tag, region, platform },
  { allowUnrated = false } = {},
) {
  const mmr = async (r) => ({
    ...normalizeValorantMmr(
      await call(env, `/v3/mmr/${seg(r)}/${seg(platform)}/${seg(name)}/${seg(tag)}`),
    ),
    region: r,
  });
  try {
    return await mmr(region);
  } catch (err) {
    if (err.status === 429) throw err;
    const account = await call(env, `/v2/account/${seg(name)}/${seg(tag)}`).catch((e) => {
      if (e.status === 429 || e.status === 404) throw e; // 404: no such Riot ID
      return null;
    });
    if (!account) throw err;
    const home = String(account.region ?? "").toLowerCase();
    if (VALORANT_REGIONS.includes(home) && home !== region) {
      try {
        return await mmr(home);
      } catch (e) {
        if (e.status === 429) throw e;
      }
    }
    if (allowUnrated) return unratedValorantPlayer(account, VALORANT_REGIONS.includes(home) ? home : region);
    throw err;
  }
}

/** An account HenrikDev knows but has no rank for: shown as Unrated, without a score. */
export function unratedValorantPlayer(account, region) {
  return {
    externalId: account?.puuid ?? null,
    name: account?.name ?? null,
    tag: account?.tag ?? null,
    region,
    score: null,
    rank: {
      name: "Unrated",
      tier: 0,
      image: null,
      rr: 0,
      lastChange: 0,
      gamesNeeded: 0,
      shields: 0,
      ladderPos: null,
      peak: null,
    },
    status: { online: false, inGame: false, text: null, legend: null },
  };
}

export function normalizeValorantMmr(data) {
  const current = data?.current ?? {};
  const tier = current.tier ?? {};
  const elo = Number(current.elo);
  if (!Number.isFinite(elo))
    throw new ApiError("HenrikDev API response had no elo");
  return {
    externalId: data.account?.puuid ?? null,
    name: data.account?.name ?? null,
    tag: data.account?.tag ?? null,
    score: elo,
    rank: {
      name: tier.name ?? "Unrated",
      tier: Number(tier.id) || 0,
      image: valorantTierIcon(Number(tier.id) || 0),
      rr: Number(current.rr) || 0,
      lastChange: Number(current.last_change) || 0,
      gamesNeeded: Number(current.games_needed_for_rating) || 0,
      shields: Number(current.rank_protection_shields) || 0,
      ladderPos: current.leaderboard_placement?.rank ?? null,
      peak: data.peak?.tier?.name ?? null,
    },
    status: { online: false, inGame: false, text: null, legend: null },
  };
}

/** Recent ranked games with their RR change, newest first. Tries v2 and falls back to v1. */
export async function fetchValorantHistory(
  env,
  { name, tag, region, platform },
) {
  try {
    const data = await call(
      env,
      `/v2/mmr-history/${seg(region)}/${seg(platform)}/${seg(name)}/${seg(tag)}`,
    );
    return normalizeValorantHistoryV2(data);
  } catch (err) {
    if (err.status === 429) throw err;
    const data = await call(
      env,
      `/v1/mmr-history/${seg(region)}/${seg(name)}/${seg(tag)}`,
    );
    return normalizeValorantHistoryV1(data);
  }
}

export function normalizeValorantHistoryV2(data) {
  return (data?.history ?? []).map((entry) => ({
    matchId: entry.match_id,
    ts: Date.parse(entry.date),
    map: entry.map?.name ?? null,
    delta: Number(entry.last_change) || 0,
    eloAfter: Number(entry.elo),
    tier: entry.tier?.name ?? null,
  }));
}

export function normalizeValorantHistoryV1(data) {
  return (data ?? []).map((entry) => ({
    matchId: entry.match_id,
    ts: entry.date_raw ? entry.date_raw * 1000 : Date.parse(entry.date),
    map: entry.map?.name ?? null,
    delta: Number(entry.mmr_change_to_last_game) || 0,
    eloAfter: Number(entry.elo),
    tier: entry.currenttierpatched ?? entry.currenttier_patched ?? null,
  }));
}

/** Agent, KDA and result for the player's latest competitive games, keyed by match id. */
export async function fetchValorantMatchDetails(
  env,
  { name, tag, region, platform, puuid },
) {
  const data = await call(
    env,
    `/v4/matches/${seg(region)}/${seg(platform)}/${seg(name)}/${seg(tag)}`,
    { mode: "competitive", size: "5" },
  );
  return normalizeValorantMatches(data, { puuid, name, tag });
}

export function normalizeValorantMatches(data, { puuid, name, tag }) {
  const details = {};
  for (const match of data ?? []) {
    const me = (match.players ?? []).find((p) =>
      puuid
        ? p.puuid === puuid
        : p.name?.toLowerCase() === name.toLowerCase() &&
          p.tag?.toLowerCase() === tag.toLowerCase(),
    );
    if (!me || !match.metadata?.match_id) continue;
    const team = (match.teams ?? []).find((t) => t.team_id === me.team_id);
    details[match.metadata.match_id] = {
      agent: me.agent?.name ?? null,
      kills: me.stats?.kills ?? null,
      deaths: me.stats?.deaths ?? null,
      assists: me.stats?.assists ?? null,
      headshots: me.stats?.headshots ?? null,
      bodyshots: me.stats?.bodyshots ?? null,
      legshots: me.stats?.legshots ?? null,
      score: me.stats?.score ?? null,
      damage: me.stats?.damage?.dealt ?? null,
      won: team?.won ?? null,
      roundsWon: team?.rounds?.won ?? null,
      roundsLost: team?.rounds?.lost ?? null,
    };
  }
  return details;
}

/** One match's full scoreboard. */
export async function fetchValorantMatch(env, { region, matchId }) {
  return normalizeValorantMatch(await call(env, `/v4/match/${seg(region)}/${seg(matchId)}`));
}

const MEDIA = "https://media.valorant-api.com";

export function normalizeValorantMatch(data) {
  const meta = data?.metadata ?? {};
  const teams = (data?.teams ?? []).map((t) => ({
    id: t.team_id,
    won: t.won ?? null,
    roundsWon: t.rounds?.won ?? null,
    roundsLost: t.rounds?.lost ?? null,
  }));
  const rounds = teams.length ? (teams[0].roundsWon ?? 0) + (teams[0].roundsLost ?? 0) : 0;
  const players = (data?.players ?? []).map((p) => {
    const s = p.stats ?? {};
    const shots = (s.headshots ?? 0) + (s.bodyshots ?? 0) + (s.legshots ?? 0);
    const tier = Number(p.tier?.id) || 0;
    return {
      puuid: p.puuid ?? null,
      name: p.name ?? null,
      tag: p.tag ?? null,
      team: p.team_id ?? null,
      agent: p.agent?.name ?? null,
      agentIcon: p.agent?.id ? `${MEDIA}/agents/${p.agent.id}/displayicon.png` : null,
      rank: p.tier?.name ?? null,
      rankIcon: valorantTierIcon(tier),
      level: p.account_level ?? null,
      kills: s.kills ?? 0,
      deaths: s.deaths ?? 0,
      assists: s.assists ?? 0,
      acs: rounds ? Math.round((s.score ?? 0) / rounds) : null,
      adr: rounds && s.damage?.dealt != null ? Math.round(s.damage.dealt / rounds) : null,
      headshotPct: shots ? Math.round((100 * (s.headshots ?? 0)) / shots) : null,
    };
  });
  players.sort((a, b) => (b.acs ?? 0) - (a.acs ?? 0));
  return {
    matchId: meta.match_id ?? null,
    map: meta.map?.name ?? null,
    mapImage: meta.map?.id ? `${MEDIA}/maps/${meta.map.id}/listviewicon.png` : null,
    mode: meta.queue?.name ?? null,
    startedAt: meta.started_at ? Date.parse(meta.started_at) : null,
    durationMs: meta.game_length_in_ms ?? null,
    rounds,
    teams,
    players,
  };
}
