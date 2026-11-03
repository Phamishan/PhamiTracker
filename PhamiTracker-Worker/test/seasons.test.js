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
