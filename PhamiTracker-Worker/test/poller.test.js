import test from "node:test";
import assert from "node:assert/strict";
import { pollPlayer } from "../src/poller.js";

// Just enough D1 to see what pollPlayer writes.
function fakeDb() {
  const writes = [];
  const prepare = (sql) => {
    const stmt = { sql, args: [] };
    stmt.bind = (...args) => ({ ...stmt, args });
    stmt.run = async () => writes.push(stmt);
    stmt.first = async () => null;
    return stmt;
  };
  return { writes, prepare, batch: async (stmts) => writes.push(...stmts) };
}

function mockFetch(routes) {
  globalThis.fetch = async (url) => {
    const href = String(url);
    const body = routes.find(([pattern]) => href.includes(pattern))?.[1];
    if (!body) return new Response(JSON.stringify({ errors: [{ message: `not mocked ${href}` }] }), { status: 500 });
    return new Response(JSON.stringify(body), { status: 200 });
  };
}

const env = (db) => ({ DB: db, APEX_API_KEY: "k", HENRIK_API_KEY: "k" });
const matchInserts = (db) => db.writes.filter((w) => w.sql.includes("INSERT OR IGNORE INTO matches"));

test("apex RP change is recorded as a match with legend and ranked map", async () => {
  const db = fakeDb();
  mockFetch([
    ["/bridge", {
      global: { uid: 7, name: "Phami", rank: { rankScore: 10_150, rankName: "Platinum", rankDiv: 1 } },
      realtime: { isOnline: 1, isInGame: 0, selectedLegend: "Bangalore" },
    }],
    ["/maprotation", { ranked: { current: { map: "Olympus", start: 1, end: 9_999_999_999 } } }],
  ]);
  const player = {
    id: "p1", game: "apex", name: "phami", platform: "PC", external_id: "7", score: 10_000,
    state: JSON.stringify({ name: "Phami", status: { inGame: true, legend: "Wraith" } }),
    last_opened_at: Date.now(),
  };
  const updated = await pollPlayer(env(db), player);

  const [insert] = matchInserts(db);
  assert.ok(insert, "match inserted");
  assert.equal(insert.args[2], 150);
  assert.deepEqual(JSON.parse(insert.args[5]), { legend: "Wraith", map: "Olympus", rank: "Platinum I" });
  assert.equal(updated.score, 10_150);
});

test("apex with no change writes no match", async () => {
  const db = fakeDb();
  mockFetch([["/bridge", { global: { rank: { rankScore: 500, rankName: "Rookie", rankDiv: 4 } }, realtime: {} }]]);
  await pollPlayer(env(db), { id: "p1", game: "apex", name: "x", platform: "PC", score: 500, state: null, last_opened_at: 0 });
  assert.equal(matchInserts(db).length, 0);
});

test("valorant waits for mmr-history before moving its synced score", async () => {
  const db = fakeDb();
  const mmr = {
    account: { puuid: "abc", name: "Phami", tag: "EUW" },
    current: { tier: { id: 18, name: "Diamond 1" }, rr: 40, elo: 1540 },
  };
  const prevState = { name: "Phami", tag: "EUW", rank: { gamesNeeded: 0 }, syncedScore: 1520, historyCursor: 1000 };
  const player = {
    id: "v1", game: "valorant", name: "phami", tag: "euw", region: "eu", platform: "pc",
    score: 1520, state: JSON.stringify(prevState), last_opened_at: 0,
  };

  mockFetch([["/v3/mmr/", { data: mmr }], ["/v2/mmr-history/", { data: { history: [] } }]]);
  let updated = await pollPlayer(env(db), player);
  let state = JSON.parse(updated.state);
  assert.equal(state.syncedScore, 1520, "still waiting for the game to show up");
  assert.ok(state.pendingSince);

  mockFetch([
    ["/v3/mmr/", { data: mmr }],
    ["/v2/mmr-history/", { data: {
      history: [
        { match_id: "new", date: "2026-11-02T19:00:00Z", last_change: 20, elo: 1540, map: { name: "Bind" } },
        { match_id: "old", date: "1970-01-01T00:00:00.500Z", last_change: 5, elo: 1520 },
      ],
    } }],
    ["/v4/matches/", { data: [{
      metadata: { match_id: "new" },
      players: [{ puuid: "abc", team_id: "Red", agent: { name: "Sova" }, stats: { kills: 18, deaths: 12, assists: 9 } }],
      teams: [{ team_id: "Red", won: true, rounds: { won: 13, lost: 7 } }],
    }] }],
  ]);
  updated = await pollPlayer(env(db), updated);
  state = JSON.parse(updated.state);
  const inserts = matchInserts(db);
  assert.equal(inserts.length, 1, "only games after the cursor");
  assert.equal(inserts[0].args[6], "new");
  assert.equal(JSON.parse(inserts[0].args[5]).agent, "Sova");
  assert.equal(state.syncedScore, 1540);
  assert.equal(state.pendingSince, null);
});
