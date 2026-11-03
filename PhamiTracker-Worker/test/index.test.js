import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const DAY = 86_400_000;
const now = Date.now();

// Answers the two queries the history route makes: the player row and their matches.
function fakeDb({ player, matches }) {
  const prepare = (sql) => {
    let args = [];
    const stmt = {
      bind: (...a) => ((args = a), stmt),
      first: async () => (sql.includes("FROM players") ? player : null),
      all: async () => ({ results: sql.includes("FROM matches") ? matches.filter((m) => m.ts >= args[1]) : [] }),
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

test("unknown sub-routes 404", async () => {
  const env = { DB: fakeDb({ player: { id: "p1", game: "apex", created_at: now }, matches: [] }) };
  assert.equal((await call("/v1/players/p1/nope", env)).error, "Not found");
});
