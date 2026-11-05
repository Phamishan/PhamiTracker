// The ranked "period" a player is in: an Apex split (apexseasons.online) or a VALORANT act
// (valorant-api.com, free, no key). Used for the split/act recap and records.

import { getApexSeason } from "./seasons.js";

const DAY = 86_400_000;
const ACTS_URL = "https://valorant-api.com/v1/seasons";
const ACTS_KEY = "valorant:acts";
const ACTS_FRESH_MS = 12 * 60 * 60_000;

/** "EPISODE 9" + "ACT III" → "Episode 9 · Act III" (roman numerals stay upper case). */
const pretty = (s) =>
  String(s ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => (/^[IVX]+$/.test(w) ? w : w[0].toUpperCase() + w.slice(1).toLowerCase()))
    .join(" ");

/** Acts with their episode's name, oldest first. */
export function parseActs(body) {
  const seasons = body?.data ?? [];
  const byId = new Map(seasons.map((s) => [s.uuid, s]));
  return seasons
    .filter((s) => /act/i.test(s.type ?? "") && s.startTime && s.endTime)
    .map((s) => {
      const episode = byId.get(s.parentUuid)?.displayName;
      return {
        name: [episode && pretty(episode), pretty(s.displayName)].filter(Boolean).join(" · "),
        start: Date.parse(s.startTime),
        end: Date.parse(s.endTime),
      };
    })
    .filter((a) => Number.isFinite(a.start) && Number.isFinite(a.end))
    .sort((a, b) => a.start - b.start);
}

async function getValorantActs(env, now) {
  const cached = await env.DB.prepare("SELECT value, expires_at FROM cache WHERE key = ?").bind(ACTS_KEY).first();
  if (cached && cached.expires_at > now) return JSON.parse(cached.value);
  try {
    const res = await fetch(ACTS_URL, { signal: AbortSignal.timeout(10_000) });
    if (!res.ok) throw new Error(`valorant-api.com returned ${res.status}`);
    const acts = parseActs(await res.json());
    await env.DB.prepare("INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?, ?, ?)")
      .bind(ACTS_KEY, JSON.stringify(acts), now + ACTS_FRESH_MS)
      .run();
    return acts;
  } catch (err) {
    console.error("act lookup failed", err);
    return cached ? JSON.parse(cached.value) : [];
  }
}

/** The act running at `now` and the one before it. */
export function actAt(acts, now) {
  const i = acts.findIndex((a) => a.start <= now && now < a.end);
  const current = i >= 0 ? acts[i] : null;
  const previous = [...acts].reverse().find((a) => a.end <= (current?.start ?? now)) ?? null;
  return { current, previous };
}

/**
 * {name, start, end, previous: {name, start, end} | null}. Falls back to the last 90 days when the
 * dates aren't known, so records still work.
 */
export async function currentPeriod(env, game, now, season) {
  if (game === "apex") {
    const s = season ?? (await getApexSeason(env, now));
    const name = (split) => [s?.season, split ? `Split ${split}` : null].filter(Boolean).join(" · ") || "This split";
    if (s?.splitStart) {
      const prev = s.previous;
      return {
        kind: "split",
        name: name(s.split),
        start: s.splitStart,
        end: s.splitEnd ?? null,
        previous: prev?.start
          ? { name: [prev.season, prev.split ? `Split ${prev.split}` : null].filter(Boolean).join(" · "), start: prev.start, end: prev.end }
          : null,
      };
    }
  } else {
    const { current, previous } = actAt(await getValorantActs(env, now), now);
    if (current) return { kind: "act", ...current, previous };
  }
  return { kind: "recent", name: "Last 90 days", start: now - 90 * DAY, end: null, previous: null };
}
