import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { endIdleSessions, registerLiveActivity, sessionState, subscribeLiveStart, trackLiveSession } from "../src/live.js";
import { characterStats, mapStats } from "../src/stats.js";

const MIN = 60_000;
const t0 = Date.UTC(2026, 10, 5, 18);

/** A D1-shaped wrapper around an in-memory SQLite with the real migrations applied. */
function d1() {
  const db = new DatabaseSync(":memory:");
  for (const file of readdirSync(new URL("../migrations/", import.meta.url)).sort()) {
    db.exec(readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8"));
  }
  const prepare = (sql) => {
    let args = [];
    const stmt = {
      bind: (...a) => ((args = a), stmt),
      first: async () => db.prepare(sql).get(...args) ?? null,
      all: async () => ({ results: db.prepare(sql).all(...args) }),
      run: async () => db.prepare(sql).run(...args),
    };
    return stmt;
  };
  return { prepare, batch: async (stmts) => Promise.all(stmts.map((s) => s.run())), raw: db };
}

function setup({ game = "apex", score = 10_000 } = {}) {
  const DB = d1();
  DB.raw
    .prepare(`INSERT INTO players (id, game, name, tag, platform, region, score, state, last_opened_at, created_at)
              VALUES ('p1', ?, 'phami', ?, 'PC', '', ?, ?, ?, ?)`)
    .run(game, game === "valorant" ? "euw" : "", score, JSON.stringify({ name: "Phami", tag: "EUW", rank: { name: "Platinum", div: 1 } }), t0, t0);
  const pushes = [];
  const env = { DB, APNS_KEY: "AAAA", APNS_KEY_ID: "live-test", APNS_TEAM_ID: "t" };
  return { env, DB, pushes };
}

function mockApns(t, pushes) {
  t.mock.method(globalThis, "fetch", async (url, init) => {
    pushes.push({ token: String(url).split("/").pop(), body: JSON.parse(init.body) });
    return new Response(null, { status: 200 });
  });
  // Signing needs a real key; the payloads are what's under test here.
  t.mock.method(crypto.subtle, "importKey", async () => ({}));
  t.mock.method(crypto.subtle, "sign", async () => new Uint8Array(64).buffer);
}

const token = (c) => c.repeat(64);
const player = (DB) => DB.raw.prepare("SELECT * FROM players WHERE id = 'p1'").get();

test("subscribing keeps only known players and replaces the token's old list", async () => {
  const { env, DB } = setup();
  assert.ok((await subscribeLiveStart(env, { token: "nope", players: ["p1"] })).error);
  const res = await subscribeLiveStart(env, { token: token("a"), players: ["p1", "ghost"], sandbox: true }, t0);
  assert.deepEqual(res.players, ["p1"]);
  await subscribeLiveStart(env, { token: token("a"), players: [] }, t0);
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM live_subscriptions").get().n, 0);
});

test("Apex: loading into a match push-starts the activity once; idle ends it", async (t) => {
  const { env, DB, pushes } = setup();
  mockApns(t, pushes);
  await subscribeLiveStart(env, { token: token("a"), players: ["p1"] }, t0);

  // Not playing: nothing happens.
  assert.equal(await trackLiveSession(env, player(DB), { status: { inGame: false } }, [], t0), null);
  // In a match: session opens and the phone gets a push-to-start.
  assert.equal(await trackLiveSession(env, player(DB), { status: { inGame: true } }, [], t0), "started");
  assert.equal(pushes.length, 1);
  const start = pushes[0].body.aps;
  assert.equal(start.event, "start");
  assert.equal(start["attributes-type"], "PhamiSessionAttributes");
  assert.deepEqual(start.attributes, { game: "apex", player: "Phami", unit: "RP", playerId: "p1" });
  assert.equal(start["content-state"].sessionDelta, 0);
  assert.ok(start.alert.title);

  // Still playing: no second start.
  assert.equal(await trackLiveSession(env, player(DB), { status: { inGame: true } }, [], t0 + 5 * MIN), "continued");
  assert.equal(pushes.length, 1);

  // The phone registers the activity's own token; it inherits the session start.
  await registerLiveActivity(env, player(DB), { token: token("b") }, t0 + 6 * MIN);
  const activity = DB.raw.prepare("SELECT * FROM live_activities").get();
  assert.deepEqual([activity.start_score, activity.started_at], [10_000, t0]);

  // 45 minutes after the last sign of play the session ends and the activity is closed.
  assert.equal(await endIdleSessions(env, t0 + 30 * MIN), 0);
  assert.equal(await endIdleSessions(env, t0 + 51 * MIN), 1);
  assert.equal(pushes.at(-1).token, token("b"));
  assert.equal(pushes.at(-1).body.aps.event, "end");
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM live_sessions").get().n, 0);
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM live_activities").get().n, 0);

  // Next time they play, it starts again.
  assert.equal(await trackLiveSession(env, player(DB), { status: { inGame: true } }, [], t0 + 3 * 60 * MIN), "started");
  assert.equal(pushes.filter((p) => p.body.aps.event === "start").length, 2);
});

test("VALORANT: a fresh ranked game starts it; backfilled old games don't", async (t) => {
  const { env, DB, pushes } = setup({ game: "valorant", score: 1542 });
  mockApns(t, pushes);
  await subscribeLiveStart(env, { token: token("c"), players: ["p1"] }, t0);
  const old = { ts: t0 - 5 * 60 * MIN, delta: 18, kind: "match", detail: {} };
  assert.equal(await trackLiveSession(env, player(DB), {}, [old], t0), null);
  const fresh = { ts: t0 - 2 * MIN, delta: 21, kind: "match", detail: { won: true } };
  assert.equal(await trackLiveSession(env, player(DB), {}, [fresh], t0), "started");
  const aps = pushes[0].body.aps;
  assert.equal(aps.attributes.player, "Phami#EUW");
  assert.deepEqual([aps["content-state"].sessionDelta, aps["content-state"].games, aps["content-state"].wins], [21, 1, 1]);
  assert.equal(DB.raw.prepare("SELECT start_score FROM live_sessions").get().start_score, 1521);
});

test("no subscribers, no session", async () => {
  const { env, DB } = setup();
  assert.equal(await trackLiveSession(env, player(DB), { status: { inGame: true } }, [], t0), null);
});

test("session numbers", () => {
  const p = { game: "apex", score: 10_150, state: JSON.stringify({ rank: { name: "Platinum", div: 1 } }) };
  const g = (delta) => ({ ts: t0, delta, kind: "match", detail: {} });
  assert.deepEqual(sessionState(p, 10_000, [g(90), g(-20), g(80)], t0), {
    score: 10_150, rank: "Platinum I", sessionDelta: 150, games: 3, wins: 2, losses: 1, lastDelta: 80, updatedAt: t0 / 1000,
  });
});

test("K/D per map and agent when kills are recorded", () => {
  const g = (map, agent, kills, deaths, delta) => ({ kind: "match", delta, detail: { map, agent, kills, deaths } });
  const rows = [g("Ascent", "Jett", 20, 10, 20), g("Ascent", "Sova", 10, 15, -15), g("Bind", "Jett", 25, 12, 22)];
  assert.deepEqual(mapStats(rows)[0], { map: "Ascent", matches: 2, delta: 5, wins: 1, kills: 30, deaths: 25 });
  assert.deepEqual(characterStats(rows)[0], { name: "Jett", matches: 2, delta: 42, wins: 2, kills: 45, deaths: 22 });
  // Apex has no kills: no K/D fields.
  assert.deepEqual(mapStats([{ kind: "match", delta: 50, detail: { map: "Olympus" } }])[0], { map: "Olympus", matches: 1, delta: 50, wins: 1 });
});
