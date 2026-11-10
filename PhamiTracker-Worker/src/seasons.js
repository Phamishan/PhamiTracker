// Current Apex season + ranked split dates, scraped from apexseasons.online (a fan site that
// tracks EA's announcements; its robots.txt allows crawlers and its terms allow personal,
// non-abusive use). Fetched at most every 12 hours and cached in D1.

const SITE = "https://apexseasons.online";
const CACHE_KEY = "apex:season";
const FRESH_MS = 12 * 60 * 60_000;

async function page(path) {
  const res = await fetch(SITE + path, {
    headers: { "user-agent": "PhamiTracker/1.0 (+https://github.com/Phamishan/PhamiTracker)" },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`apexseasons.online returned ${res.status}`);
  return res.text();
}

const unescape = (s) =>
  s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");

/** Visible text of a page, one chunk per line. */
const text = (html) =>
  unescape(html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, "").replace(/<[^>]+>/g, "\n"))
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

/** "September 15, 2026" → epoch ms at 00:00 UTC. */
const parseDay = (s) => {
  const ms = Date.parse(`${s} 00:00:00 UTC`);
  return Number.isFinite(ms) ? ms : null;
};

/** Reads the countdown island on the home page: {targetDate, eventName, estimated}. */
export function parseHome(html) {
  const props = html.match(/component-url="[^"]*Countdown[^"]*"[^>]*props="([^"]*)"/)?.[1];
  if (!props) return null;
  // Astro serialises props as {"name": [type, value]}.
  const data = JSON.parse(unescape(props));
  const value = (key) => (Array.isArray(data[key]) ? data[key][1] : data[key]);
  const end = Date.parse(value("targetDate"));
  return {
    season: value("eventName") ?? null,
    end: Number.isFinite(end) ? end : null,
    estimated: value("estimated") !== false,
  };
}

/** Reads "Current split / 2", "Started / <date>", "Estimated end / <date>" from the split page. */
export function parseSplit(html) {
  const lines = text(html);
  const after = (label) => {
    const i = lines.findIndex((line) => line.toLowerCase() === label);
    return i >= 0 ? lines[i + 1] : undefined;
  };
  const split = Number(after("current split"));
  return {
    split: Number.isFinite(split) && split > 0 ? split : null,
    start: after("started") ? parseDay(after("started")) : null,
    end: after("estimated end") ? parseDay(after("estimated end")) : null,
  };
}

export async function fetchApexSeason() {
  const [home, split] = await Promise.all([page("/").then(parseHome), page("/tools/ranked-split/").then(parseSplit)]);
  if (!home?.end && !split?.end) throw new Error("apexseasons.online layout changed: no dates found");
  // The home countdown has the exact time; the split page only the day. Same day → use the countdown.
  const sameDay = home?.end && split?.end && Math.abs(home.end - split.end) < 86_400_000;
  return {
    season: home?.season ?? null,
    split: split?.split ?? null,
    splitStart: split?.start ?? null,
    splitEnd: sameDay ? home.end : split?.end ?? home?.end ?? null,
    estimated: home?.estimated ?? true,
    source: `${SITE}/tools/ranked-split/`,
  };
}

/**
 * Dates read off the game, set in wrangler.toml ([vars] APEX_SEASON / APEX_SPLIT /
 * APEX_SPLIT_START / APEX_SPLIT_END). They win over the scraped ones until the split ends, then
 * scraping takes over again. For when apexseasons.online is behind or wrong.
 */
export function applySeasonOverride(season, env, now = Date.now()) {
  const end = Date.parse(env.APEX_SPLIT_END ?? "");
  if (!Number.isFinite(end) || end <= now) return season;
  const start = Date.parse(env.APEX_SPLIT_START ?? "");
  const split = Number(env.APEX_SPLIT);
  return {
    ...(season ?? {}),
    season: env.APEX_SEASON || season?.season || null,
    split: Number.isFinite(split) && split > 0 ? split : season?.split ?? null,
    splitStart: Number.isFinite(start) ? start : season?.splitStart ?? null,
    splitEnd: end,
    estimated: false,
    source: "wrangler.toml",
  };
}

/** Cached season info. Keeps serving the last good copy if the site is down or changes. */
export async function getApexSeason(env, now = Date.now()) {
  return applySeasonOverride(await scrapedApexSeason(env, now), env, now);
}

async function scrapedApexSeason(env, now) {
  const cached = await env.DB.prepare(`SELECT value, expires_at FROM cache WHERE key = '${CACHE_KEY}'`).first();
  const previous = cached ? JSON.parse(cached.value) : null;
  if (previous && cached.expires_at > now) return previous;
  try {
    const season = { ...(await fetchApexSeason()), checkedAt: now };
    // Remember the split that just ended, for the "last split" recap.
    const changed = previous && (previous.split !== season.split || previous.season !== season.season);
    season.previous = changed
      ? { season: previous.season, split: previous.split, start: previous.splitStart, end: season.splitStart ?? previous.splitEnd }
      : previous?.previous ?? null;
    await env.DB.prepare(`INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES ('${CACHE_KEY}', ?, ?)`)
      .bind(JSON.stringify(season), now + FRESH_MS)
      .run();
    return season;
  } catch (err) {
    console.error("season scrape failed", err);
    if (previous) {
      // Try again in an hour rather than on every request.
      await env.DB.prepare(`UPDATE cache SET expires_at = ? WHERE key = '${CACHE_KEY}'`).bind(now + 60 * 60_000).run();
    }
    return previous;
  }
}
