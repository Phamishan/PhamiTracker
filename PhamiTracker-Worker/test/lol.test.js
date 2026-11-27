import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { lolScore, lolRankName, normalizeLolMatch, normalizeLolPlayer, lolGameDetail } from "../src/lol.js";
import { pollPlayer, splitLp } from "../src/poller.js";
import { nextPollDelay } from "../src/stats.js";

const MIN = 60_000;

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

const entry = (queueType, tier, rank, lp) => ({ queueType, tier, rank, leaguePoints: lp, wins: 40, losses: 35 });

/** A match where our player (puuid "me") played `champion` in `position`. */
function match(id, { won = true, champion = "Ahri", position = "MIDDLE", end = Date.now(), queueId = 420, duration = 1800 } = {}) {
  const others = Array.from({ length: 9 }, (_, i) => ({
    puuid: `p${i}`, riotIdGameName: `Player${i}`, riotIdTagline: "EUW", teamId: i < 4 ? 100 : 200,
    championName: "Garen", championId: 86, teamPosition: "TOP", kills: 2, deaths: 3, assists: 4,
    totalMinionsKilled: 150, neutralMinionsKilled: 0, totalDamageDealtToChampions: 12000, win: i < 4 ? won : !won,
  }));
  return {
    metadata: { matchId: id },
    info: {
      queueId, gameDuration: duration, gameStartTimestamp: end - duration * 1000, gameEndTimestamp: end,
      teams: [{ teamId: 100, win: won }, { teamId: 200, win: !won }],
      participants: [
        { puuid: "me", riotIdGameName: "PH4M1", riotIdTagline: "SH4N", teamId: 100, championName: champion, championId: 103,
          teamPosition: position, kills: 8, deaths: 2, assists: 6, totalMinionsKilled: 190, neutralMinionsKilled: 12,
          totalDamageDealtToChampions: 25000, win: won },
        ...others,
      ],
    },
  };
}

test("one score line: 100 per division, Master+ on LP", () => {
  assert.equal(lolScore("IRON", "IV", 0), 0);
  assert.equal(lolScore("GOLD", "II", 50), 1450); // Gold is tier 3: (3*4 + 2) * 100 + 50
  assert.equal(lolScore("EMERALD", "I", 99), 2399);
  assert.equal(lolScore("MASTER", null, 120), 2920);
  assert.equal(lolScore("CHALLENGER", null, 1500), 4300);
  assert.equal(lolRankName("GRANDMASTER"), "Grandmaster");
  assert.equal(lolRankName("PLATINUM", "III"), "Platinum III");
});

test("Solo/Duo and Flex are separate ladders", () => {
  const entries = [entry("RANKED_SOLO_5x5", "GOLD", "II", 50), entry("RANKED_FLEX_SR", "SILVER", "I", 10)];
  const live = { gameQueueConfigId: 440 };
  const solo = normalizeLolPlayer({ puuid: "me", account: { gameName: "PH4M1", tagLine: "SH4N" }, entries, live, queue: "solo" });
  const flex = normalizeLolPlayer({ puuid: "me", account: { gameName: "PH4M1", tagLine: "SH4N" }, entries, live, queue: "flex" });
  assert.deepEqual([solo.score, solo.rank.name, solo.status.inGame], [1450, "Gold II", false]);
  assert.deepEqual([flex.score, flex.rank.name, flex.status.inGame], [1110, "Silver I", true]);
  assert.match(solo.rank.image, /emblem-gold\.png$/);
  const unranked = normalizeLolPlayer({ puuid: "me", entries: [], queue: "solo" });
  assert.deepEqual([unranked.score, unranked.rank.name], [null, "Unranked"]);
});

test("a game's line: champion, role as the map, KDA, CS, result; remakes flagged", () => {
  const d = lolGameDetail(match("EUW1_1", { champion: "Ahri", position: "UTILITY", won: false }), "me");
  assert.deepEqual([d.champion, d.map, d.kills, d.cs, d.won, d.remake], ["Ahri", "Support", 8, 202, false, false]);
  assert.equal(lolGameDetail(match("EUW1_2", { duration: 180 }), "me").remake, true);
});

test("scoreboard shaped like VALORANT's", () => {
  const s = normalizeLolMatch(match("EUW1_1", { won: true, queueId: 440 }));
  assert.equal(s.mode, "Ranked Flex");
  assert.equal(s.players.length, 10);
  assert.deepEqual(s.teams.map((t) => [t.id, t.won]), [["Blue", true], ["Red", false]]);
  const me = s.players.find((p) => p.name === "PH4M1");
  assert.deepEqual([me.tag, me.agent, me.role, me.cs], ["SH4N", "Ahri", "Mid", 202]);
  assert.match(me.agentIcon, /champion\/103\/square$/);
});

test("LP over several missed games is split by result", () => {
  assert.deepEqual(splitLp(22, [{ won: true }]), [22]);
  assert.deepEqual(splitLp(44, [{ won: true }, { won: true }]), [22, 22]);
  assert.deepEqual(splitLp(22, [{ won: true }, { won: false }, { won: true }]), [22, -22, 22]);
  assert.deepEqual(splitLp(0, [{ won: true }, { won: false }]), [0, 0]);
});

test("LOL checks: every 2 minutes in a ranked game, every minute right after one", () => {
  const now = Date.now();
  assert.equal(nextPollDelay("lol", { now, state: { status: { inGame: true } } }), 2 * MIN);
  assert.equal(nextPollDelay("lol", { now, state: { pendingSince: now } }), MIN);
  assert.equal(nextPollDelay("lol", { now, lastChangeAt: now - 5 * MIN, state: {} }), MIN);
  assert.equal(nextPollDelay("lol", { now, state: {}, lastOpenedAt: now - 60 * MIN }), 3 * MIN);
});

test("polling: a game's LP is recorded with its match; a lag waits for the match; decay is an adjustment", async (t) => {
  const DB = d1();
  const now = Date.now();
  DB.raw.prepare(`INSERT INTO players (id, game, name, tag, platform, region, external_id, last_opened_at, created_at)
                  VALUES ('p1', 'lol', 'ph4m1', 'sh4n', 'solo', 'eun1', 'me', ?, ?)`).run(now, now);
  let lp = 50;
  let ids = [];
  const matches = {};
  const asked = [];
  t.mock.method(globalThis, "fetch", async (url) => {
    const u = new URL(url);
    asked.push(`${u.host.split(".")[0]} ${u.pathname}`);
    if (u.pathname.includes("/league/v4/entries/by-puuid/")) return Response.json([entry("RANKED_SOLO_5x5", "GOLD", "II", lp)]);
    if (u.pathname.includes("/spectator/")) return new Response("{}", { status: 404 });
    if (u.pathname.includes("/accounts/by-puuid/")) return Response.json({ puuid: "me", gameName: "PH4M1", tagLine: "SH4N" });
    if (u.pathname.endsWith("/ids")) {
      assert.equal(u.searchParams.get("queue"), "420");
      return Response.json(ids);
    }
    const id = u.pathname.split("/").pop();
    return Response.json(matches[id]);
  });
  const env = { DB, RIOT_API_KEY: "k" };
  const poll = async () => pollPlayer(env, DB.raw.prepare("SELECT * FROM players WHERE id = 'p1'").get());
  const recorded = () => DB.raw.prepare("SELECT delta, score_after, kind, detail, external_id FROM matches ORDER BY ts").all();

  // First poll: the starting point (EUNE uses the europe cluster for matches).
  await poll();
  assert.equal(DB.raw.prepare("SELECT score FROM players").get().score, 1450);
  assert.ok(asked.some((a) => a.startsWith("eun1 /lol/league")));

  // A win: +22 LP, and its match is there.
  lp = 72;
  ids = ["EUN1_100"];
  matches.EUN1_100 = match("EUN1_100", { won: true, end: Date.now() });
  await poll();
  let rows = recorded();
  assert.equal(rows.length, 1);
  assert.deepEqual([rows[0].delta, rows[0].score_after, rows[0].kind, rows[0].external_id], [22, 1472, "match", "EUN1_100"]);
  assert.deepEqual(JSON.parse(rows[0].detail).champion, "Ahri");
  assert.ok(asked.some((a) => a.startsWith("europe /lol/match/v5/matches/by-puuid/me/ids")));

  // LP moves but the match isn't listed yet: nothing recorded, the score waits.
  lp = 50;
  ids = ["EUN1_100"];
  await poll();
  assert.equal(recorded().length, 1);
  assert.equal(DB.raw.prepare("SELECT score FROM players").get().score, 1472);
  // ...then it shows up: recorded on the next poll.
  ids = ["EUN1_101", "EUN1_100"];
  matches.EUN1_101 = match("EUN1_101", { won: false, champion: "Lux", end: Date.now() });
  await poll();
  rows = recorded();
  assert.deepEqual(rows.map((r) => [r.delta, r.kind]), [[22, "match"], [-22, "match"]]);
  assert.equal(JSON.parse(rows[1].detail).champion, "Lux");

  // LP drops with no game for 10 minutes: decay, an adjustment.
  lp = 20;
  await poll();
  const state = JSON.parse(DB.raw.prepare("SELECT state FROM players").get().state);
  state.pendingSince = Date.now() - 11 * MIN;
  DB.raw.prepare("UPDATE players SET state = ?").run(JSON.stringify(state));
  await poll();
  rows = recorded();
  assert.deepEqual(rows.at(-1).kind, "adjust");
  assert.equal(rows.at(-1).delta, -30);
});

test("LOL season from wrangler.toml, then a new one with the old one as the last split", async () => {
  const { currentPeriod } = await import("../src/periods.js");
  const env = { LOL_SPLIT_NAME: "Season 2026", LOL_SPLIT_START: "2026-01-08T11:00:00Z", LOL_SPLIT_END: "2027-01-06T22:59:59Z" };
  const now = Date.parse("2026-11-27T10:15:00Z");
  const p = await currentPeriod(env, "lol", now);
  assert.deepEqual([p.kind, p.name, p.end], ["split", "Season 2026", Date.parse("2027-01-06T22:59:59Z")]);
  assert.equal(Math.floor((p.end - now) / 86_400_000), 40); // the countdown's 40 days

  const after = await currentPeriod(env, "lol", Date.parse("2027-01-10T12:00:00Z"));
  assert.deepEqual([after.name, after.start, after.end], ["New season", Date.parse("2027-01-06T22:59:59Z"), null]);
  assert.equal(after.previous.name, "Season 2026");
});
