// VALORANT Premier teams, from HenrikDev (the same endpoints as PhamiBot's /premierteam).

import { ApiError } from "./apex.js";

const BASE = "https://api.henrikdev.xyz/valorant";

// HenrikDev numbers divisions 1-21: Open 1 ... Elite 5, then Contender.
const DIVISIONS = [
  ...["Open", "Intermediate", "Advanced", "Elite"].flatMap((tier) => [1, 2, 3, 4, 5].map((n) => `${tier} ${n}`)),
  "Contender",
];

/** A league match worth this many points or more is a win (PhamiBot's rule); 0 = no result. */
const WIN_POINTS = 50;

async function call(env, path) {
  if (!env.HENRIK_API_KEY) throw new ApiError("HENRIK_API_KEY is not set", { retryable: false });
  const res = await fetch(BASE + path, {
    headers: { Authorization: env.HENRIK_API_KEY },
    signal: AbortSignal.timeout(10_000),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new ApiError(body?.errors?.[0]?.message ?? `HenrikDev API returned ${res.status}`, {
      status: res.status === 404 ? 404 : res.status === 429 ? 429 : 502,
      retryable: res.status !== 404,
    });
  }
  return body?.data;
}

/** The team and its league matches. The history is optional: a new team has none. */
export async function fetchPremierTeam(env, { name, tag }) {
  const path = `/v1/premier/${encodeURIComponent(name)}/${encodeURIComponent(tag)}`;
  const [team, history] = await Promise.all([
    call(env, path),
    call(env, `${path}/history`).catch((err) => {
      if (err.status === 429) throw err;
      return null;
    }),
  ]);
  return normalizePremierTeam(team, history);
}

/** "EU_CENTRAL_EAST" -> "EU Central East". */
export function conferenceName(id) {
  if (!id) return null;
  return String(id)
    .split("_")
    .map((w) => (w.length <= 5 && /^(EU|NA|AP|KR|BR|LATAM|SEA|ANZ)$/.test(w) ? w : w[0] + w.slice(1).toLowerCase()))
    .join(" ");
}

/** The region a conference plays in, for match scoreboards ("EU_CENTRAL_EAST" -> "eu"). */
export function conferenceRegion(id) {
  const prefix = String(id ?? "").split("_")[0].toLowerCase();
  return { eu: "eu", na: "na", ap: "ap", kr: "kr", br: "br", latam: "latam" }[prefix] ?? "eu";
}

export function normalizePremierTeam(team, history) {
  if (!team?.name) throw new ApiError("HenrikDev API response had no team");
  const placement = team.placement ?? {};
  const divisionNumber = Number(placement.division) || 0;
  const matches = [...(history?.league_matches ?? [])]
    .map((m) => {
      const before = Number(m.points_before) || 0;
      const after = Number(m.points_after) || 0;
      const delta = after - before;
      return {
        id: m.id ?? null,
        startedAt: Date.parse(m.started_at) || null,
        pointsBefore: before,
        pointsAfter: after,
        delta,
        result: delta >= WIN_POINTS ? "win" : delta !== 0 ? "loss" : null,
      };
    })
    .sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0));

  // The history is more up to date than the team's own stats (PhamiBot does the same).
  const decided = matches.filter((m) => m.result);
  const wins = decided.length ? decided.filter((m) => m.result === "win").length : Number(team.stats?.wins) || 0;
  const losses = decided.length ? decided.length - wins : Number(team.stats?.losses) || 0;
  const members = team.member ?? team.members ?? [];

  return {
    id: team.id ?? null,
    name: team.name,
    tag: team.tag ?? "",
    enrolled: team.enrolled ?? null,
    colors: {
      primary: team.customization?.primary ?? null,
      secondary: team.customization?.secondary ?? null,
    },
    image: team.customization?.image ?? null,
    icon: team.customization?.icon ?? null,
    division: divisionNumber > 0 ? DIVISIONS[divisionNumber - 1] ?? `Division ${divisionNumber}` : null,
    divisionNumber,
    points: matches.length ? matches[0].pointsAfter : Number(placement.points) || 0,
    // Points needed for the playoffs each stage (PhamiBot's bar).
    pointsGoal: 600,
    place: Number(placement.place) || null,
    conference: conferenceName(placement.conference),
    region: conferenceRegion(placement.conference),
    wins,
    losses,
    members: members
      .filter((m) => m?.name)
      .map((m) => ({ puuid: m.puuid ?? null, name: m.name, tag: m.tag ?? "" })),
    matches,
  };
}
