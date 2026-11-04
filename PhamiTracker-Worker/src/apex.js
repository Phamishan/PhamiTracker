// apexlegendsapi.com (api.apexlegendsstatus.com) client + normalizers.

const BASE = "https://api.apexlegendsstatus.com";

export const APEX_PLATFORMS = ["PC", "PS4", "X1", "SWITCH"];

export class ApiError extends Error {
  constructor(message, { status = 502, retryable = true } = {}) {
    super(message);
    this.status = status;
    this.retryable = retryable;
  }
}

async function call(env, path, params) {
  if (!env.APEX_API_KEY) throw new ApiError("APEX_API_KEY is not set", { retryable: false });
  const url = new URL(path, BASE);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  const res = await fetch(url, {
    headers: { Authorization: env.APEX_API_KEY },
    signal: AbortSignal.timeout(10_000),
  });
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new ApiError(`Apex API returned ${res.status}: ${text.slice(0, 120)}`);
  }
  // The API reports most failures as {"Error": "..."}, sometimes with a 200.
  if (body?.Error || !res.ok) {
    const message = body?.Error ?? `Apex API returned ${res.status}`;
    const notFound = res.status === 404 || /not found|never played/i.test(message);
    throw new ApiError(message, {
      status: notFound ? 404 : res.status === 429 ? 429 : 502,
      retryable: !notFound,
    });
  }
  return body;
}

/** Fetches a player by uid (once known) or by name. */
export async function fetchApexPlayer(env, { name, platform, uid }) {
  const params = uid ? { uid, platform } : { player: name, platform };
  return normalizeApexPlayer(await call(env, "/bridge", params));
}

export function normalizeApexPlayer(body) {
  const global = body.global ?? {};
  const rank = global.rank ?? {};
  const realtime = body.realtime ?? {};
  const score = Number(rank.rankScore);
  if (!Number.isFinite(score)) throw new ApiError("Apex API response had no rankScore");
  return {
    externalId: global.uid != null ? String(global.uid) : null,
    name: global.name ?? null,
    score,
    rank: {
      name: rank.rankName ?? "Unranked",
      div: Number(rank.rankDiv) || 0,
      image: rank.rankImg ?? null,
      ladderPos: Number(rank.ALStopIntGlobal ?? rank.ladderPosPlatform) > 0
        ? Number(rank.ALStopIntGlobal ?? rank.ladderPosPlatform)
        : null,
      season: rank.rankedSeason ?? null,
    },
    level: Number(global.level) || null,
    status: {
      online: realtime.isOnline === 1,
      inGame: realtime.isInGame === 1,
      text: realtime.currentStateAsText ?? (realtime.isOnline === 1 ? "Online" : "Offline"),
      legend: realtime.selectedLegend || body.legends?.selected?.LegendName || null,
    },
    banner: body.legends?.selected?.ImgAssets?.banner ?? null,
  };
}

/** Map rotation (battle royale + ranked + LTM), normalized. */
export async function fetchApexMaps(env) {
  return normalizeApexMaps(await call(env, "/maprotation", { version: "2" }));
}

export function normalizeApexMaps(body) {
  const slot = (entry) =>
    entry && {
      map: entry.map ?? null,
      code: entry.code ?? null,
      mode: entry.eventName ?? null,
      image: entry.asset ?? null,
      start: entry.start ? entry.start * 1000 : null,
      end: entry.end ? entry.end * 1000 : null,
    };
  const mode = (block) => block && { current: slot(block.current), next: slot(block.next) };
  return {
    battleRoyale: mode(body.battle_royale),
    ranked: mode(body.ranked),
    ltm: mode(body.ltm),
  };
}

/**
 * Picks the ranked map a match detected at `ts` was most likely played on. RP shows up a minute
 * or two after a match ends, so right after a rotation the previous map is the better guess.
 */
export function rankedMapAt(maps, ts, matchMinutes = 20) {
  const current = maps?.ranked?.current;
  if (!current?.map) return null;
  if (current.start && ts - current.start < matchMinutes * 60_000 && maps.previousRanked) {
    return maps.previousRanked;
  }
  return current.map;
}
