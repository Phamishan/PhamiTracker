// Pure helpers: turning recorded matches into "today", daily history and per-map stats,
// and deciding how soon each player should be polled again.

const DAY = 86_400_000;
const MINUTE = 60_000;

/** Local calendar day (YYYY-MM-DD) of `ts` for a client `tzOffset` minutes east of UTC. */
export function dayKey(ts, tzOffset) {
  return new Date(ts + tzOffset * MINUTE).toISOString().slice(0, 10);
}

/**
 * @param matches rows {ts, delta, score_after, kind, detail} in any order, covering at least `days`
 * @param currentScore the player's score right now (history is rebuilt backwards from it)
 */
export function summarize(matches, currentScore, { tzOffset = 0, days = 14, now = Date.now() } = {}) {
  const sorted = [...matches].sort((a, b) => b.ts - a.ts);
  const today = dayKey(now, tzOffset);

  const byDay = new Map();
  for (const m of sorted) {
    const key = dayKey(m.ts, tzOffset);
    const bucket = byDay.get(key) ?? { delta: 0, total: 0, matches: 0, wins: 0, losses: 0 };
    bucket.total += m.delta;
    if (m.kind === "match") {
      bucket.delta += m.delta;
      bucket.matches += 1;
      const won = m.detail?.won ?? (m.delta > 0);
      if (won) bucket.wins += 1;
      else bucket.losses += 1;
    }
    byDay.set(key, bucket);
  }

  // Walk back from today: the score at the end of day d-1 is the end of day d minus d's changes.
  const history = [];
  let endScore = currentScore;
  for (let i = 0; i < days; i++) {
    const key = dayKey(now - i * DAY, tzOffset);
    const bucket = byDay.get(key);
    history.push({ day: key, score: endScore, delta: bucket?.delta ?? 0, matches: bucket?.matches ?? 0 });
    if (endScore != null && bucket) endScore -= bucket.total;
  }
  history.reverse();

  const todayBucket = byDay.get(today) ?? { delta: 0, matches: 0, wins: 0, losses: 0 };
  const todayMatches = sorted.filter((m) => m.kind === "match" && dayKey(m.ts, tzOffset) === today);
  return {
    today: {
      delta: todayBucket.delta,
      matches: todayBucket.matches,
      wins: todayBucket.wins,
      losses: todayBucket.losses,
      best: todayMatches.length ? Math.max(...todayMatches.map((m) => m.delta)) : null,
      worst: todayMatches.length ? Math.min(...todayMatches.map((m) => m.delta)) : null,
      startScore: currentScore == null ? null : currentScore - (byDay.get(today)?.total ?? 0),
      // Running total after each of today's games, oldest first (the Today sparkline).
      series: todayMatches
        .slice()
        .reverse()
        .reduce((acc, m) => [...acc, (acc.at(-1) ?? 0) + m.delta], []),
    },
    history,
    maps: mapStats(sorted),
  };
}

export function mapStats(matches) {
  const maps = new Map();
  for (const m of matches) {
    const name = m.detail?.map;
    if (m.kind !== "match" || !name) continue;
    const entry = maps.get(name) ?? { map: name, matches: 0, delta: 0, wins: 0 };
    entry.matches += 1;
    entry.delta += m.delta;
    if (m.detail?.won ?? (m.delta > 0)) entry.wins += 1;
    maps.set(name, entry);
  }
  return [...maps.values()].sort((a, b) => b.matches - a.matches || b.delta - a.delta);
}

/** Apex RP swings bigger than this are season resets / corrections, not a single game. */
export const APEX_ADJUSTMENT_THRESHOLD = 1000;

export function isApexAdjustment(delta, prevState, nextState) {
  if (Math.abs(delta) >= APEX_ADJUSTMENT_THRESHOLD) return true;
  const before = prevState?.rank?.season;
  const after = nextState?.rank?.season;
  return before != null && after != null && before !== after;
}

/**
 * How long to wait before polling a player again. Close to real time while they're playing,
 * slower when they're clearly idle so the API budget goes to people mid-session.
 */
export function nextPollDelay(game, { now, state, lastChangeAt, lastOpenedAt, errorCount = 0, rateLimited = false }) {
  if (rateLimited) return 2 * MINUTE;
  if (errorCount > 0) return Math.min(30 * MINUTE, MINUTE * 2 ** Math.min(errorCount, 5));
  const sinceChange = lastChangeAt ? now - lastChangeAt : Infinity;
  const sinceOpened = lastOpenedAt ? now - lastOpenedAt : Infinity;
  if (game === "apex") {
    if (state?.status?.online || state?.status?.inGame) return MINUTE;
    if (sinceChange < 20 * MINUTE) return MINUTE;
    return sinceOpened < DAY ? 3 * MINUTE : 10 * MINUTE;
  }
  // VALORANT has no online flag, so recent activity is the signal.
  if (state?.pendingSince || sinceChange < 60 * MINUTE) return MINUTE;
  if (sinceChange < 6 * 60 * MINUTE || sinceOpened < 30 * MINUTE) return 2 * MINUTE;
  return 5 * MINUTE;
}
