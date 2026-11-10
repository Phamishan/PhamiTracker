import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const DAY = 86_400_000;
const now = Date.now();

// Answers the player row and their matches (from args[1] on, when the query has a start).
function fakeDb({ player, matches }) {
  const prepare = (sql) => {
    let args = [];
    const stmt = {
      bind: (...a) => ((args = a), stmt),
      first: async () => (sql.includes("FROM players") ? player : null),
      all: async () => ({ results: sql.includes("FROM matches") ? matches.filter((m) => args.length < 2 || m.ts >= args[1]) : [] }),
      run: async () => {},
    };
    return stmt;
  };
  return { prepare, batch: async () => {} };
}

const call = (path, env) =>
  worker.fetch(new Request(`https://tracker.test${path}`), env, { waitUntil: () => {} }).then((r) => r.json());

test("history covers the requested range, or everything since linking", async () => {
  const player = { id: "p1", game: "apex", score: 10_300, created_at: now - 40 * DAY };
  const matches = [
    { ts: now - 2 * DAY, delta: 100, score_after: 10_300, kind: "match" },
    { ts: now - 30 * DAY, delta: 200, score_after: 10_200, kind: "match" },
  ];
  const env = { DB: fakeDb({ player, matches }) };

  const week = await call("/v1/players/p1/history?days=7", env);
  assert.equal(week.days, 7);
  assert.equal(week.history.length, 7);
  assert.equal(week.history.at(-1).score, 10_300);
  assert.equal(week.history[0].score, 10_200);

  const all = await call("/v1/players/p1/history?days=0", env);
  assert.equal(all.days, 41);
  assert.equal(all.history[0].score, 10_000);
});

test("breakdown adds up every recorded game by legend and map", async () => {
  const player = { id: "p1", game: "apex", score: 10_300, created_at: now - 400 * DAY };
  const game = (ts, delta, legend, map) => ({ ts, delta, kind: "match", detail: JSON.stringify({ legend, map }) });
  const matches = [
    game(now - DAY, 100, "Wraith", "Olympus"),
    game(now - 200 * DAY, -20, "Wraith", "Olympus"), // long before this split
    game(now - 300 * DAY, 50, "Bangalore", "World's Edge"),
  ];
  const env = { DB: fakeDb({ player, matches }) };
  const all = await call("/v1/players/p1/breakdown", env);
  assert.equal(all.games, 3);
  assert.deepEqual(all.characters[0], { name: "Wraith", matches: 2, delta: 80, wins: 1 });
  assert.deepEqual(all.maps.map((m) => [m.map, m.matches, m.delta]), [["Olympus", 2, 80], ["World's Edge", 1, 50]]);
});

test("linking an Apex uid looks the account up by uid, not by name", async (t) => {
  const apexCalls = [];
  t.mock.method(globalThis, "fetch", async (url) => {
    apexCalls.push(new URL(url).searchParams);
    return new Response(JSON.stringify({ global: { uid: 1001040582944, name: "PHAMI", rank: { rankScore: 5888, rankName: "Gold", rankDiv: 4 } } }));
  });
  const inserted = [];
  const db = {
    prepare: (sql) => {
      let args = [];
      const stmt = {
        bind: (...a) => ((args = a), stmt),
        // Only the row inserted below exists, so the uid lookup misses at first.
        first: async () => (sql.includes("WHERE id = ?") ? { id: args[0], game: "apex", name: "phami", external_id: "1001040582944" } : null),
        run: async () => (sql.startsWith("INSERT") && inserted.push(args), {}),
        all: async () => ({ results: [] }),
      };
      return stmt;
    },
    batch: async () => {},
  };
  const res = await worker.fetch(
    new Request("https://tracker.test/v1/players", {
      method: "POST",
      body: JSON.stringify({ game: "apex", uid: "1001040582944", platform: "PC" }),
    }),
    { DB: db, APEX_API_KEY: "k" },
    { waitUntil: () => {} },
  );

  assert.equal(res.status, 201);
  assert.equal(apexCalls[0].get("uid"), "1001040582944");
  assert.equal(apexCalls[0].get("player"), null);
  assert.equal(inserted[0][2], "phami"); // stored under the account's real name
  assert.equal(inserted[0][6], "1001040582944");
});

test("linking an Apex uid refuses a name that belongs to another account", async (t) => {
  t.mock.method(globalThis, "fetch", async () =>
    new Response(JSON.stringify({ global: { uid: 1001040582944, name: "PHAMI", rank: { rankScore: 5888 } } })),
  );
  const db = {
    prepare: (sql) => {
      const stmt = {
        bind: () => stmt,
        first: async () => (sql.includes("name = ?") ? { id: "other", external_id: "999" } : null),
        run: async () => ({}),
      };
      return stmt;
    },
  };
  const res = await worker.fetch(
    new Request("https://tracker.test/v1/players", {
      method: "POST",
      body: JSON.stringify({ game: "apex", uid: "1001040582944", platform: "PC" }),
    }),
    { DB: db, APEX_API_KEY: "k" },
    { waitUntil: () => {} },
  );
  assert.equal(res.status, 409);
});

// A DB where nobody is tracked and nothing is cached; records what gets cached.
function emptyDb(cached = []) {
  return {
    prepare: (sql) => {
      let args = [];
      const stmt = {
        bind: (...a) => ((args = a), stmt),
        first: async () => null,
        all: async () => ({ results: [] }),
        run: async () => (sql.startsWith("INSERT OR REPLACE INTO cache") && cached.push(args), {}),
      };
      return stmt;
    },
  };
}

test("searching VALORANT builds a page from recent games without tracking", async (t) => {
  const today = new Date(now).toISOString();
  t.mock.method(globalThis, "fetch", async (url) => {
    const path = new URL(url).pathname;
    if (path.includes("/v3/mmr/")) {
      return Response.json({ data: { account: { puuid: "pu", name: "Phami", tag: "EUW" }, current: { elo: 1542, rr: 42, tier: { id: 18, name: "Diamond 1" } } } });
    }
    if (path.includes("mmr-history")) {
      return Response.json({ data: { history: [
        { match_id: "m2", date: today, map: { name: "Ascent" }, last_change: 21, elo: 1542, tier: { name: "Diamond 1" } },
        { match_id: "m1", date: today, map: { name: "Bind" }, last_change: -15, elo: 1521, tier: { name: "Platinum 3" } },
      ] } });
    }
    return Response.json({ data: [] }); // v4 matches
  });
  const cached = [];
  const res = await call("/v1/search?game=valorant&name=Phami&tag=%23EUW&region=eu", { DB: emptyDb(cached), HENRIK_API_KEY: "k" });

  assert.equal(res.player.id, null);
  assert.equal(res.player.name, "Phami");
  assert.equal(res.player.tag, "EUW");
  assert.equal(res.rankLabel, "Diamond 1");
  assert.equal(res.tracked, false);
  assert.equal(res.matches.length, 2);
  assert.equal(res.matches[0].map, "Ascent");
  assert.equal(res.today.delta, 6);
  assert.equal(cached.length, 1);
});

test("searching Apex shows the live rank", async (t) => {
  t.mock.method(globalThis, "fetch", async () =>
    Response.json({ global: { uid: 42, name: "PHAMI", level: 500, rank: { rankScore: 13460, rankName: "Diamond", rankDiv: 3 } } }),
  );
  const res = await call("/v1/search?game=apex&name=phami&platform=pc", { DB: emptyDb(), APEX_API_KEY: "k" });
  assert.equal(res.player.name, "PHAMI");
  assert.equal(res.rankLabel, "Diamond III");
  assert.equal(res.score, 13460);
  assert.deepEqual(res.matches, []);
  assert.deepEqual(res.history, []);
});

test("search validates its input", async () => {
  assert.equal((await call("/v1/search?game=apex", { DB: emptyDb() })).error, "name is required");
  assert.equal((await call("/v1/search?game=valorant&name=x", { DB: emptyDb() })).error, "tag is required");
});

test("match scoreboard is fetched once and then served from the cache", async (t) => {
  const id = "0d4e5a3c-1111-2222-3333-444455556666";
  const fetchMock = t.mock.method(globalThis, "fetch", async (url) => {
    assert.ok(String(url).endsWith(`/v4/match/eu/${id}`));
    return Response.json({ data: { metadata: { match_id: id, map: { name: "Bind" } }, teams: [], players: [] } });
  });
  const store = new Map();
  const db = {
    prepare: (sql) => {
      let args = [];
      const stmt = {
        bind: (...a) => ((args = a), stmt),
        first: async () => store.get(args[0]) ?? null,
        run: async () => (sql.startsWith("INSERT") && store.set(args[0], { value: args[1], expires_at: args[2] }), {}),
      };
      return stmt;
    },
  };
  const first = await call(`/v1/valorant/matches/${id}?region=eu`, { DB: db, HENRIK_API_KEY: "k" });
  const second = await call(`/v1/valorant/matches/${id}?region=eu`, { DB: db, HENRIK_API_KEY: "k" });
  assert.equal(first.map, "Bind");
  assert.deepEqual(second, first);
  assert.equal(fetchMock.mock.callCount(), 1);
  assert.equal((await call("/v1/valorant/matches/nope", { DB: db })).error, "Bad match id");
});

test("unknown sub-routes 404", async () => {
  const env = { DB: fakeDb({ player: { id: "p1", game: "apex", created_at: now }, matches: [] }) };
  assert.equal((await call("/v1/players/p1/nope", env)).error, "Not found");
});

test("summary includes split recap, legends and survives missing season/predator data", async (t) => {
  t.mock.method(globalThis, "fetch", async () => new Response("down", { status: 503 }));
  t.mock.method(console, "error", () => {});
  const player = {
    id: "p1", game: "apex", platform: "PC", score: 10_150, created_at: now - 40 * DAY, last_polled_at: now,
    state: JSON.stringify({ rank: { name: "Platinum", div: 1 } }),
  };
  const matches = [
    { ts: now - 2 * DAY, delta: 100, score_after: 10_100, kind: "match", detail: JSON.stringify({ legend: "Wraith" }) },
    { ts: now - DAY, delta: 50, score_after: 10_150, kind: "match", detail: JSON.stringify({ legend: "Wraith" }) },
  ];
  const res = await call("/v1/players/p1", { DB: fakeDb({ player, matches }) });
  assert.equal(res.split.name, "Last 90 days");
  assert.equal(res.split.games, 2);
  assert.equal(res.split.net, 150);
  assert.deepEqual(res.characters, [{ name: "Wraith", matches: 2, delta: 150, wins: 2 }]);
  assert.equal(res.predator, null);
  assert.equal(res.previousSplit, null);
});

test("cron housekeeping runs every 15 minutes, session check every minute", async () => {
  const { isTidyMinute } = await import("../src/index.js");
  const run = async (minute) => {
    const sql = [];
    const DB = {
      prepare: (q) => {
        const stmt = { bind: () => stmt, first: async () => null, all: async () => ({ results: [] }), run: async () => (sql.push(q), {}) };
        if (/^SELECT/.test(q)) sql.push(q);
        return stmt;
      },
    };
    const waits = [];
    await worker.scheduled({ scheduledTime: Date.UTC(2026, 10, 6, 18, minute) }, { DB }, { waitUntil: (p) => waits.push(p) });
    await Promise.all(waits);
    return sql;
  };
  const quiet = await run(7);
  assert.ok(quiet.some((q) => q.includes("FROM live_sessions")));
  assert.ok(!quiet.some((q) => q.startsWith("DELETE")));
  const tidy = await run(15);
  assert.equal(tidy.filter((q) => q.startsWith("DELETE")).length, 2);
  assert.deepEqual([0, 14, 15, 30, 45, 59].map((m) => isTidyMinute(Date.UTC(2026, 10, 6, 18, m))), [true, false, true, true, true, false]);
});
