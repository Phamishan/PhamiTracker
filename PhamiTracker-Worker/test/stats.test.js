import test from "node:test";
import assert from "node:assert/strict";
import { dayKey, isApexAdjustment, nextPollDelay, summarize } from "../src/stats.js";

const HOUR = 3_600_000;
const now = Date.parse("2026-11-02T20:00:00Z");

test("dayKey uses the client's offset", () => {
  assert.equal(dayKey(Date.parse("2026-11-02T23:30:00Z"), 60), "2026-11-03");
  assert.equal(dayKey(Date.parse("2026-11-02T23:30:00Z"), 0), "2026-11-02");
});

test("summarize totals today and rebuilds daily history from the current score", () => {
  const matches = [
    { ts: now - 1 * HOUR, delta: 120, score_after: 10_120, kind: "match", detail: { map: "Olympus" } },
    { ts: now - 2 * HOUR, delta: -40, score_after: 10_000, kind: "match", detail: { map: "Olympus" } },
    { ts: now - 26 * HOUR, delta: 200, score_after: 10_040, kind: "match", detail: { map: "Storm Point" } },
    { ts: now - 27 * HOUR, delta: -5000, score_after: 9_840, kind: "adjust", detail: {} },
  ];
  const { today, history, maps } = summarize(matches, 10_120, { now, days: 3 });

  const { delta, matches: count, wins, losses, best, worst, startScore } = today;
  assert.deepEqual(
    { delta, count, wins, losses, best, worst, startScore },
    { delta: 80, count: 2, wins: 1, losses: 1, best: 120, worst: -40, startScore: 10_040 },
  );
  assert.deepEqual(today.series, [-40, 80]);
  assert.deepEqual(history.map((d) => d.day), ["2026-10-31", "2026-11-01", "2026-11-02"]);
  assert.deepEqual(history.map((d) => d.score), [14_840, 10_040, 10_120]);
  // Adjustments move the score line but don't count as RP earned.
  assert.equal(history[1].delta, 200);
  assert.deepEqual(maps[0], { map: "Olympus", matches: 2, delta: 80, wins: 1 });
});

test("summarize with no matches", () => {
  const { today, history } = summarize([], 500, { now, days: 2 });
  assert.equal(today.delta, 0);
  assert.equal(today.best, null);
  assert.deepEqual(history.map((d) => d.score), [500, 500]);
});

test("summarize prefers the recorded result over the sign of the delta", () => {
  const matches = [{ ts: now - HOUR, delta: -3, score_after: 1, kind: "match", detail: { won: true } }];
  assert.equal(summarize(matches, 1, { now }).today.wins, 1);
});

test("apex adjustments", () => {
  assert.equal(isApexAdjustment(150, null, null), false);
  assert.equal(isApexAdjustment(-6000, null, null), true);
  assert.equal(isApexAdjustment(10, { rank: { season: "s25" } }, { rank: { season: "s26" } }), true);
});

test("poll pacing", () => {
  const MIN = 60_000;
  assert.equal(nextPollDelay("apex", { now, state: { status: { inGame: true } } }), MIN);
  assert.equal(nextPollDelay("apex", { now, state: {}, lastOpenedAt: now - 2 * 86_400_000 }), 10 * MIN);
  assert.equal(nextPollDelay("valorant", { now, lastChangeAt: now - 10 * MIN }), MIN);
  assert.equal(nextPollDelay("valorant", { now, state: { pendingSince: now } }), MIN);
  assert.equal(nextPollDelay("valorant", { now, lastChangeAt: now - 10 * HOUR }), 5 * MIN);
  assert.equal(nextPollDelay("valorant", { now, rateLimited: true }), 2 * MIN);
  assert.equal(nextPollDelay("apex", { now, errorCount: 10 }), 30 * MIN);
});

test("latest session for the widget", async () => {
  const { latestSession } = await import("../src/stats.js");
  const MIN = 60_000;
  const t = Date.UTC(2026, 10, 9, 20);
  const row = (min, delta, after, kind = "match") => ({ ts: t + min * MIN, delta, score_after: after, kind, detail: "{}" });
  const rows = [row(50, 30, 7130), row(20, -20, 7100), row(0, 120, 7120), row(-300, 40, 7000)].reverse();
  const s = latestSession(rows, "apex", t + 60 * MIN);
  assert.deepEqual(
    { games: s.games, wins: s.wins, net: s.net, best: s.best, worst: s.worst, startScore: s.startScore, endScore: s.endScore, series: s.series, over: s.over },
    { games: 3, wins: 2, net: 130, best: 120, worst: -20, startScore: 7000, endScore: 7130, series: [120, 100, 130], over: false },
  );
  assert.equal(latestSession(rows, "apex", t + 100 * MIN).over, true);
  // VALORANT games 50 minutes apart by start time are one session.
  const val = [row(0, 20, 1520), row(50, 18, 1538)];
  assert.equal(latestSession(val, "valorant", t + 60 * MIN).games, 2);
  assert.equal(latestSession(val, "apex", t + 60 * MIN).games, 1);
  assert.equal(latestSession([], "apex"), null);
});
