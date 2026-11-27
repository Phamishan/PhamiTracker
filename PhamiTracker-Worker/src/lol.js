// League of Legends ("LOL" in the app), from Riot's official API. https://developer.riotgames.com
//
// Ranked Solo/Duo (queue 420) and Flex (440), each its own ladder: a tracked account's
// `platform` is its queue, "solo" or "flex". Endpoints:
//   account-v1    Riot ID <-> PUUID                     regional host (europe/americas/asia)
//   league-v4     tier, division, LP, wins, losses      server host (euw1, na1, ...)
//   spectator-v5  is the player in a game right now     server host
//   match-v5      match ids and details                 regional host (europe/americas/asia/sea)
//
// Secret: RIOT_API_KEY (sent as X-Riot-Token).

import { ApiError } from "./apex.js";

export const SOLO_QUEUE = 420;

/** A tracked account's queue (its `platform`): queue id, league-v4's name for it, label. */
export const LOL_QUEUES = {
  solo: { id: 420, type: "RANKED_SOLO_5x5", label: "Ranked Solo/Duo" },
  flex: { id: 440, type: "RANKED_FLEX_SR", label: "Ranked Flex" },
};
const queueOf = (queue) => LOL_QUEUES[queue] ?? LOL_QUEUES.solo;

/** Server -> the regional cluster its matches (and accounts) live on. */
const SERVERS = {
  euw1: "europe",
  eun1: "europe",
  tr1: "europe",
  ru: "europe",
  na1: "americas",
  br1: "americas",
  la1: "americas",
  la2: "americas",
  kr: "asia",
  jp1: "asia",
  oc1: "sea",
  sg2: "sea",
  tw2: "sea",
  vn2: "sea",
};
export const LOL_SERVERS = Object.keys(SERVERS);

/** account-v1 has no "sea" cluster; any cluster can look up any account. */
const accountCluster = (server) => (SERVERS[server] === "sea" ? "asia" : SERVERS[server] ?? "europe");
const matchCluster = (server) => SERVERS[server] ?? "europe";

const TIERS = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND"];
const APEX_TIERS = ["MASTER", "GRANDMASTER", "CHALLENGER"];
const DIVISIONS = { IV: 0, III: 1, II: 2, I: 3 };
/** Master and above have no divisions: their LP continues from here. */
export const LOL_MASTER_SCORE = TIERS.length * 4 * 100;

/**
 * One number for the climb chart, goals and rank up/down: 100 per division from Iron IV 0 LP
 * (Gold II 50 LP = 1,250), and Master+ continuing on LP from 2,800.
 */
export function lolScore(tier, division, lp) {
  const t = String(tier ?? "").toUpperCase();
  const points = Number(lp) || 0;
  if (APEX_TIERS.includes(t)) return LOL_MASTER_SCORE + points;
  const i = TIERS.indexOf(t);
  if (i < 0) return null;
  return (i * 4 + (DIVISIONS[String(division ?? "").toUpperCase()] ?? 0)) * 100 + Math.min(points, 100);
}

const title = (s) => (s ? s[0] + s.slice(1).toLowerCase() : s);

/** "Gold II", "Master", "Grandmaster". */
export function lolRankName(tier, division) {
  const t = String(tier ?? "").toUpperCase();
  if (!t) return "Unranked";
  return APEX_TIERS.includes(t) ? title(t) : `${title(t)} ${division ?? ""}`.trim();
}

/** Ranked emblem art from CommunityDragon. */
export const lolRankIcon = (tier) =>
  tier
    ? `https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-${String(tier).toLowerCase()}.png`
    : null;

/** A champion's square icon from CommunityDragon. */
export const lolChampionIcon = (championId) =>
  championId ? `https://cdn.communitydragon.org/latest/champion/${championId}/square` : null;

/** "UTILITY" -> "Support", the role names players use. */
const ROLES = { TOP: "Top", JUNGLE: "Jungle", MIDDLE: "Mid", BOTTOM: "Bot", UTILITY: "Support" };
export const lolRole = (position) => ROLES[String(position ?? "").toUpperCase()] ?? null;

async function call(env, host, path, { notFoundOk = false } = {}) {
  if (!env.RIOT_API_KEY) throw new ApiError("RIOT_API_KEY is not set", { retryable: false });
  const res = await fetch(`https://${host}.api.riotgames.com${path}`, {
    headers: { "X-Riot-Token": env.RIOT_API_KEY },
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status === 404 && notFoundOk) return null;
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new ApiError(body?.status?.message ?? `Riot API returned ${res.status}`, {
      status: res.status === 404 ? 404 : res.status === 429 ? 429 : 502,
      retryable: res.status !== 404,
    });
  }
  return body;
}

const seg = (value) => encodeURIComponent(value);

/** Riot ID -> account {puuid, gameName, tagLine}. */
export async function fetchLolAccount(env, { name, tag, server }) {
  return call(env, accountCluster(server), `/riot/account/v1/accounts/by-riot-id/${seg(name)}/${seg(tag)}`);
}

/**
 * The player's Solo/Duo rank and whether they're in a ranked game right now, as a player state
 * (shaped like the other games'). Unranked players have a null score.
 */
export async function fetchLolPlayer(env, { puuid, name, tag, server, queue = "solo" }) {
  let account = null;
  if (!puuid) {
    account = await fetchLolAccount(env, { name, tag, server });
    puuid = account.puuid;
  }
  const [entries, live, named] = await Promise.all([
    call(env, server, `/lol/league/v4/entries/by-puuid/${seg(puuid)}`),
    call(env, server, `/lol/spectator/v5/active-games/by-summoner/${seg(puuid)}`, { notFoundOk: true }).catch((err) => {
      if (err.status === 429) throw err;
      return null; // live status is a nice-to-have
    }),
    // Keep the shown Riot ID current (it can change); a looked-up account already has it.
    account ? null : call(env, accountCluster(server), `/riot/account/v1/accounts/by-puuid/${seg(puuid)}`).catch(() => null),
  ]);
  return normalizeLolPlayer({ puuid, account: account ?? named, entries, live, name, tag, queue });
}

export function normalizeLolPlayer({ puuid, account, entries, live, name, tag, queue = "solo" }) {
  const q = queueOf(queue);
  const solo = (entries ?? []).find((e) => e.queueType === q.type) ?? null;
  // In a game of this queue: that's what this ladder's session and Live Activity follow.
  const inRanked = live?.gameQueueConfigId === q.id;
  return {
    externalId: puuid,
    name: account?.gameName ?? name ?? null,
    tag: account?.tagLine ?? tag ?? null,
    score: solo ? lolScore(solo.tier, solo.rank, solo.leaguePoints) : null,
    rank: {
      name: solo ? lolRankName(solo.tier, solo.rank) : "Unranked",
      tier: solo?.tier ?? null,
      division: solo?.rank ?? null,
      lp: solo?.leaguePoints ?? 0,
      wins: solo?.wins ?? 0,
      losses: solo?.losses ?? 0,
      image: lolRankIcon(solo?.tier),
      gamesNeeded: 0,
      peak: null,
    },
    status: {
      online: Boolean(live),
      inGame: inRanked,
      text: live ? (inRanked ? `In ${q.label}` : "In game") : null,
      legend: null,
    },
  };
}

/** The queue's match ids, newest first, optionally only those that started after `since` (ms). */
export async function fetchLolMatchIds(env, { puuid, server, since, count = 5, queue = "solo" }) {
  const query = new URLSearchParams({ queue: String(queueOf(queue).id), start: "0", count: String(count) });
  if (since) query.set("startTime", String(Math.floor(since / 1000)));
  return call(env, matchCluster(server), `/lol/match/v5/matches/by-puuid/${seg(puuid)}/ids?${query}`);
}

export async function fetchLolMatchRaw(env, { server, matchId }) {
  return call(env, matchCluster(server), `/lol/match/v5/matches/${seg(matchId)}`);
}

/** One player's line from a match: what's stored with each recorded game. */
export function lolGameDetail(match, puuid) {
  const p = match?.info?.participants?.find((x) => x.puuid === puuid);
  if (!p) return null;
  return {
    matchId: match.metadata?.matchId ?? null,
    endedAt: match.info.gameEndTimestamp ?? (match.info.gameStartTimestamp ?? 0) + (match.info.gameDuration ?? 0) * 1000,
    champion: p.championName ?? null,
    // Summoner's Rift is the only ranked map, so a game's "map" is its role (By Role).
    map: lolRole(p.teamPosition || p.individualPosition),
    kills: p.kills ?? 0,
    deaths: p.deaths ?? 0,
    assists: p.assists ?? 0,
    cs: (p.totalMinionsKilled ?? 0) + (p.neutralMinionsKilled ?? 0),
    damage: p.totalDamageDealtToChampions ?? null,
    won: p.win === true,
    // A remake (under ~3.5 minutes) gives no LP.
    remake: (match.info.gameDuration ?? 0) < 210 || p.gameEndedInEarlySurrender === true,
  };
}

/** A whole match as a scoreboard, shaped like VALORANT's (match_detail.dart). */
export function normalizeLolMatch(match) {
  const info = match?.info ?? {};
  const teamName = (id) => (id === 100 ? "Blue" : id === 200 ? "Red" : String(id));
  const kills = (id) => (info.participants ?? []).filter((p) => p.teamId === id).reduce((s, p) => s + (p.kills ?? 0), 0);
  return {
    map: "Summoner's Rift",
    mode: info.queueId === LOL_QUEUES.flex.id ? LOL_QUEUES.flex.label : LOL_QUEUES.solo.label,
    startedAt: info.gameStartTimestamp ?? info.gameCreation ?? null,
    durationMs: info.gameDuration == null ? null : info.gameDuration * 1000,
    teams: (info.teams ?? []).map((t) => ({
      id: teamName(t.teamId),
      won: t.win ?? null,
      // Team kills in place of rounds.
      roundsWon: kills(t.teamId),
      roundsLost: kills(t.teamId === 100 ? 200 : 100),
    })),
    players: (info.participants ?? []).map((p) => ({
      name: p.riotIdGameName ?? p.summonerName ?? "Player",
      tag: p.riotIdTagline ?? null,
      team: teamName(p.teamId),
      agent: p.championName ?? null,
      agentIcon: lolChampionIcon(p.championId),
      role: lolRole(p.teamPosition || p.individualPosition),
      rank: null,
      kills: p.kills ?? 0,
      deaths: p.deaths ?? 0,
      assists: p.assists ?? 0,
      cs: (p.totalMinionsKilled ?? 0) + (p.neutralMinionsKilled ?? 0),
      damage: p.totalDamageDealtToChampions ?? null,
      gold: p.goldEarned ?? null,
    })),
  };
}
