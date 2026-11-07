import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";
import { followEvents, isStreakMilestone, message, notifyFollowers, RECAP_AFTER_MS } from "../src/notify.js";
import { FAVOURITE_POLL_MS, pollPlayer } from "../src/poller.js";

const MIN = 60_000;
const t0 = Date.UTC(2026, 10, 7, 18);

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
  return { prepare, batch: async (stmts) => { for (const s of stmts) await s.run(); }, raw: db };
}

const apexState = (score, name = "Gold", div = 2, extra = {}) => ({ name: "PH4M1", score, rank: { name, div }, status: {}, ...extra });
const game = (i, delta, after, detail = {}) => ({ ts: t0 + i * 10 * MIN, delta, scoreAfter: after, kind: "match", detail });

test("rank up/down, but not on resets or from the first poll's baseline", () => {
  const up = followEvents("apex", apexState(6990, "Gold", 3), apexState(7010, "Gold", 2), [game(0, 20, 7010)], null, t0);
  assert.deepEqual(up.events.filter((e) => e.type.startsWith("rank")), [{ type: "rankUp", rank: "Gold II" }]);
  const down = followEvents("apex", apexState(7010, "Gold", 2), apexState(6990, "Gold", 3), [game(0, -20, 6990)], null, t0);
  assert.deepEqual(down.events.at(-1), { type: "rankDown", rank: "Gold III" });
  const reset = followEvents("apex", apexState(15000, "Diamond", 1), apexState(9000, "Platinum", 3), [{ ...game(0, -6000, 9000), kind: "adjust" }], null, t0);
  assert.deepEqual(reset.events, []);
});

test("streaks fire at 3, 5, 8 ... and reset when the run breaks", () => {
  assert.deepEqual([1, 2, 3, 4, 5, 8, 9, 10, 20, 25, 26].map(isStreakMilestone), [false, false, true, false, true, true, false, true, true, true, false]);
  const s = apexState(7000);
  let notify = null;
  const fired = [];
  const deltas = [10, 12, 9, 15, 20, -30, -20, -10];
  deltas.forEach((d, i) => {
    const r = followEvents("apex", s, s, [game(i, d, 7000)], notify, t0 + i * 10 * MIN);
    notify = r.notify;
    fired.push(...r.events.filter((e) => e.type.endsWith("Streak")));
  });
  assert.deepEqual(fired, [
    { type: "winStreak", count: 3 },
    { type: "winStreak", count: 5 },
    { type: "lossStreak", count: 3 },
  ]);
});

test("a session recap goes out once it has been quiet for 45 minutes", () => {
  const s = apexState(7000);
  let r = followEvents("apex", s, s, [game(0, 50, 7050), game(1, -20, 7030), game(2, 80, 7110)], null, t0);
  assert.deepEqual(r.notify.session, { games: 3, net: 110, lastAt: t0 + 20 * MIN });
  // Still within 45 minutes: nothing yet.
  r = followEvents("apex", s, s, [], r.notify, t0 + 50 * MIN);
  assert.equal(r.events.length, 0);
  r = followEvents("apex", s, s, [], r.notify, t0 + 20 * MIN + RECAP_AFTER_MS);
  assert.deepEqual(r.events, [{ type: "recap", games: 3, net: 110 }]);
  assert.equal(r.notify.session, null);
  // A game after a long break recaps the old session first, then starts a new one.
  const old = { streak: null, session: { games: 2, net: -40, lastAt: t0 } };
  r = followEvents("apex", s, s, [game(9, 30, 7030)], old, t0 + 90 * MIN);
  assert.deepEqual(r.events[0], { type: "recap", games: 2, net: -40 });
  assert.deepEqual(r.notify.session, { games: 1, net: 30, lastAt: t0 + 90 * MIN });
});

test("messages are a bit silly and name the player", () => {
  const who = { name: "PH4M1", game: "apex", unit: "RP" };
  const first = () => 0;
  assert.deepEqual(message({ type: "rankUp", rank: "Gold I" }, who, first), { title: "📈 PH4M1 ranked up to Gold I", body: "They're officially a nerd. 🤓" });
  assert.equal(message({ type: "lossStreak", count: 3 }, who, first).title, "🧊 PH4M1 lost RP 3 games in a row");
  assert.equal(message({ type: "winStreak", count: 5 }, { ...who, game: "valorant" }, first).title, "🔥 PH4M1 is on a 5-game win streak");
  assert.equal(message({ type: "recap", games: 6, net: 240 }, who, first).title, "🎮 PH4M1 wrapped up: +240 RP over 6 games");
  assert.equal(message({ type: "recap", games: 1, net: -15 }, { ...who, unit: "RR" }, first).title, "🎮 PH4M1 wrapped up: -15 RR over 1 game");
  for (const type of ["rankUp", "rankDown", "winStreak", "lossStreak"]) {
    assert.match(message({ type, rank: "Gold I", count: 3 }, who, () => 0.999).body, /^They/);
  }
});

function setup() {
  const DB = d1();
  DB.raw
    .prepare(`INSERT INTO players (id, game, name, tag, platform, region, external_id, score, state, last_opened_at, created_at, last_change_at)
              VALUES ('p1', 'apex', 'ph4m1', '', 'PC', '', '7', 6990, ?, 0, ?, ?)`)
    .run(JSON.stringify(apexState(6990, "Gold", 3)), t0, t0 - 60 * MIN);
  DB.raw.prepare("INSERT INTO cache (key, value, expires_at) VALUES ('apex:maps', '{}', ?)").run(Date.now() + 60 * MIN);
  return { DB, env: { DB, APEX_API_KEY: "k", APNS_KEY: "AAAA", APNS_KEY_ID: "notify-test", APNS_TEAM_ID: "t" } };
}

function mockApis(t, pushes, rankScore = 7010) {
  t.mock.method(globalThis, "fetch", async (url, init) => {
    if (String(url).includes("push.apple.com")) {
      pushes.push({ url: String(url), headers: init.headers, body: JSON.parse(init.body) });
      return new Response(null, { status: 200 });
    }
    return Response.json({ global: { uid: 7, name: "PH4M1", rank: { rankScore, rankName: "Gold", rankDiv: 2 } } });
  });
  t.mock.method(crypto.subtle, "importKey", async () => ({}));
  t.mock.method(crypto.subtle, "sign", async () => new Uint8Array(64).buffer);
}

test("following a player: register, then their rank up is pushed as a normal notification", async (t) => {
  const { DB, env } = setup();
  const pushes = [];
  mockApis(t, pushes);
  const res = await worker.fetch(
    new Request("https://tracker.test/v1/notifications", {
      method: "POST",
      body: JSON.stringify({ token: "ab".repeat(32), follows: [{ game: "apex", name: "PH4M1", platform: "PC" }] }),
    }),
    env,
    { waitUntil: () => {} },
  );
  const body = await res.json();
  assert.deepEqual(body.players, ["p1"]);
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM follows").get().n, 1);

  const player = DB.raw.prepare("SELECT * FROM players WHERE id = 'p1'").get();
  await pollPlayer(env, player);
  const rankUp = pushes.find((p) => p.body.aps.alert.title.includes("ranked up"));
  assert.ok(rankUp, "rank up pushed");
  assert.equal(rankUp.body.aps.alert.title, "📈 PH4M1 ranked up to Gold II");
  assert.equal(rankUp.headers["apns-push-type"], "alert");
  assert.equal(rankUp.headers["apns-topic"], "phamishan.phamitracker");
  assert.ok(rankUp.url.endsWith("ab".repeat(32)));

  // Favourite-only players are checked every 5 minutes at most.
  const after = DB.raw.prepare("SELECT next_poll_at, last_polled_at FROM players WHERE id = 'p1'").get();
  assert.ok(after.next_poll_at - after.last_polled_at >= FAVOURITE_POLL_MS);
});

test("no followers: no lookups, no pushes", async (t) => {
  const { DB, env } = setup();
  const pushes = [];
  mockApis(t, pushes);
  const player = DB.raw.prepare("SELECT * FROM players WHERE id = 'p1'").get();
  assert.equal(await notifyFollowers(env, player, apexState(6990, "Gold", 3), apexState(7010), [game(0, 20, 7010)], t0), 0);
  assert.equal(pushes.length, 0);
});

test("turning notifications off forgets the phone and its follows", async (t) => {
  const { DB, env } = setup();
  mockApis(t, []);
  const call = (method, path, body) =>
    worker.fetch(new Request(`https://tracker.test${path}`, { method, body: body && JSON.stringify(body) }), env, { waitUntil: () => {} });
  await call("POST", "/v1/notifications", { token: "cd".repeat(32), follows: [{ game: "apex", name: "PH4M1", platform: "PC" }] });
  await call("DELETE", `/v1/notifications/${"cd".repeat(32)}`);
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM devices").get().n, 0);
  assert.equal(DB.raw.prepare("SELECT COUNT(*) AS n FROM follows").get().n, 0);
});
