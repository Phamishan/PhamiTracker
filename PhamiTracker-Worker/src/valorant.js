// HenrikDev VALORANT API client + normalizers. https://docs.henrikdev.xyz

import { ApiError } from "./apex.js";

const BASE = "https://api.henrikdev.xyz/valorant";

export const VALORANT_REGIONS = ["eu", "na", "ap", "kr", "latam", "br"];
export const VALORANT_PLATFORMS = ["pc", "console"];

// HenrikDev doesn't return rank art, so use valorant-api.com's icons for the current tier set.
const TIER_ICONS = "https://media.valorant-api.com/competitivetiers/03621f52-342b-cf4e-4f86-9350a49c6d04";
export const valorantTierIcon = (tier) => (tier > 0 ? `${TIER_ICONS}/${tier}/largeicon.png` : null);

async function call(env, path, query = {}) {
  if (!env.HENRIK_API_KEY) throw new ApiError("HENRIK_API_KEY is not set", { retryable: false });
  const url = new URL(BASE + path);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  const res = await fetch(url, {
    headers: { Authorization: env.HENRIK_API_KEY },
    signal: AbortSignal.timeout(10_000),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const message = body?.errors?.[0]?.message ?? `HenrikDev API returned ${res.status}`;
    throw new ApiError(message, {
      status: res.status === 404 ? 404 : res.status === 429 ? 429 : 502,
      retryable: res.status !== 404,
    });
  }
  return body?.data;
}

const seg = (value) => encodeURIComponent(value);

export async function fetchValorantPlayer(env, { name, tag, region, platform }) {
  const data = await call(env, `/v3/mmr/${seg(region)}/${seg(platform)}/${seg(name)}/${seg(tag)}`);
  return normalizeValorantMmr(data);
}

export function normalizeValorantMmr(data) {
  const current = data?.current ?? {};
  const tier = current.tier ?? {};
  const elo = Number(current.elo);
  if (!Number.isFinite(elo)) throw new ApiError("HenrikDev API response had no elo");
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
export async function fetchValorantHistory(env, { name, tag, region, platform }) {
  try {
    const data = await call(env, `/v2/mmr-history/${seg(region)}/${seg(platform)}/${seg(name)}/${seg(tag)}`);
    return normalizeValorantHistoryV2(data);
  } catch (err) {
    if (err.status === 429) throw err;
    const data = await call(env, `/v1/mmr-history/${seg(region)}/${seg(name)}/${seg(tag)}`);
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
export async function fetchValorantMatchDetails(env, { name, tag, region, platform, puuid }) {
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
      puuid ? p.puuid === puuid : p.name?.toLowerCase() === name.toLowerCase() && p.tag?.toLowerCase() === tag.toLowerCase(),
    );
    if (!me || !match.metadata?.match_id) continue;
    const team = (match.teams ?? []).find((t) => t.team_id === me.team_id);
    details[match.metadata.match_id] = {
      agent: me.agent?.name ?? null,
      kills: me.stats?.kills ?? null,
      deaths: me.stats?.deaths ?? null,
      assists: me.stats?.assists ?? null,
      won: team?.won ?? null,
      roundsWon: team?.rounds?.won ?? null,
      roundsLost: team?.rounds?.lost ?? null,
    };
  }
  return details;
}
