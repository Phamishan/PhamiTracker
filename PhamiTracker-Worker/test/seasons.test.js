import test from "node:test";
import assert from "node:assert/strict";
import { parseHome, parseSplit } from "../src/seasons.js";

// Trimmed from apexseasons.online's markup (Astro island props + the split page's stat blocks).
const HOME = `<astro-island uid="ZtoOtX" component-url="/_astro/Countdown.DsDklbkz.js" component-export="default"
  props="{&quot;targetDate&quot;:[0,&quot;2026-11-03T18:00:00Z&quot;],&quot;eventName&quot;:[0,&quot;Season 30 · Marked&quot;],&quot;estimated&quot;:[0,true]}" ssr></astro-island>`;

const SPLIT = `<div><p>Current split</p><p class="x">2</p></div>
  <div><p>Started</p><p>September 15, 2026</p></div>
  <div><p>Estimated end</p><p>November 3, 2026</p></div>`;

test("home countdown", () => {
  assert.deepEqual(parseHome(HOME), {
    season: "Season 30 · Marked",
    end: Date.parse("2026-11-03T18:00:00Z"),
    estimated: true,
  });
  assert.equal(parseHome("<html></html>"), null);
});

test("split page", () => {
  assert.deepEqual(parseSplit(SPLIT), {
    split: 2,
    start: Date.parse("2026-09-15T00:00:00Z"),
    end: Date.parse("2026-11-03T00:00:00Z"),
  });
  assert.deepEqual(parseSplit("<p>nothing here</p>"), {
    split: null,
    start: null,
    end: null,
  });
});

test("split dates from wrangler.toml win until they pass", async () => {
  const { applySeasonOverride } = await import("../src/seasons.js");
  const scraped = { season: "Season 30 · Marked", split: null, splitStart: 1, splitEnd: Date.UTC(2026, 10, 3, 18), estimated: true };
  const env = { APEX_SEASON: "Season 31", APEX_SPLIT: "1", APEX_SPLIT_START: "2026-11-03T18:00:00Z", APEX_SPLIT_END: "2026-12-15T18:00:00Z" };
  const now = Date.UTC(2026, 10, 9, 18, 4);
  const s = applySeasonOverride(scraped, env, now);
  assert.deepEqual([s.season, s.split, s.splitEnd, s.estimated], ["Season 31", 1, Date.UTC(2026, 11, 15, 18), false]);
  // 35 days 23 hours after 9 Nov 18:04 UTC is within the hour before the reset.
  const left = s.splitEnd - now;
  assert.ok(left >= (35 * 24 + 23) * 3_600_000 && left < (35 * 24 + 24) * 3_600_000);
  // After the end date, or with nothing set, the scraped dates are used.
  assert.equal(applySeasonOverride(scraped, env, Date.UTC(2026, 11, 16)), scraped);
  assert.equal(applySeasonOverride(scraped, {}, now), scraped);
});
