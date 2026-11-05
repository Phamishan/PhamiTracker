import test from "node:test";
import assert from "node:assert/strict";
import { normalizeApexMaps, normalizeApexPlayer, rankedMapAt } from "../src/apex.js";
import {
  normalizeValorantHistoryV1,
  normalizeValorantHistoryV2,
  normalizeValorantMatch,
  normalizeValorantMatches,
  normalizeValorantMmr,
} from "../src/valorant.js";

test("apex bridge response", () => {
  const p = normalizeApexPlayer({
    global: {
      name: "Phami",
      uid: 1009,
      level: 512,
      rank: { rankScore: 12_345, rankName: "Diamond", rankDiv: 3, rankImg: "x.png", rankedSeason: "season26_split_1" },
    },
    realtime: { isOnline: 1, isInGame: 1, currentStateAsText: "In match", selectedLegend: "Wraith" },
  });
  assert.equal(p.externalId, "1009");
  assert.equal(p.score, 12_345);
  assert.deepEqual([p.rank.name, p.rank.div, p.rank.ladderPos], ["Diamond", 3, null]);
  assert.deepEqual([p.status.inGame, p.status.legend], [true, "Wraith"]);
});

test("apex maps + ranked map guess", () => {
  const start = Date.parse("2026-11-02T18:00:00Z");
  const maps = normalizeApexMaps({
    ranked: { current: { map: "E-District", start: start / 1000, end: start / 1000 + 86_400 }, next: { map: "Olympus" } },
  });
  maps.previousRanked = "Broken Moon";
  assert.equal(rankedMapAt(maps, start + 5 * 60_000), "Broken Moon");
  assert.equal(rankedMapAt(maps, start + 60 * 60_000), "E-District");
  assert.equal(rankedMapAt(null, start), null);
});

test("valorant v3 mmr", () => {
  const p = normalizeValorantMmr({
    account: { puuid: "abc", name: "Phami", tag: "EUW" },
    current: { tier: { id: 18, name: "Diamond 1" }, rr: 42, last_change: 21, elo: 1542, games_needed_for_rating: 0 },
    peak: { tier: { name: "Ascendant 1" } },
  });
  assert.deepEqual([p.score, p.rank.tier, p.rank.rr, p.rank.peak], [1542, 18, 42, "Ascendant 1"]);
  assert.match(p.rank.image, /competitivetiers\/.+\/18\/largeicon\.png$/);
});

test("valorant mmr history v1 and v2", () => {
  const v2 = normalizeValorantHistoryV2({
    history: [
      { match_id: "m1", date: "2026-11-02T19:00:00.000Z", map: { name: "Ascent" }, last_change: -18, elo: 1521, tier: { name: "Diamond 1" } },
    ],
  });
  assert.deepEqual(v2[0], {
    matchId: "m1",
    ts: Date.parse("2026-11-02T19:00:00Z"),
    map: "Ascent",
    delta: -18,
    eloAfter: 1521,
    tier: "Diamond 1",
  });
  const v1 = normalizeValorantHistoryV1([
    { match_id: "m2", date_raw: 1_790_000_000, map: { name: "Lotus" }, mmr_change_to_last_game: 23, elo: 1544, currenttierpatched: "Diamond 1" },
  ]);
  assert.deepEqual([v1[0].ts, v1[0].delta, v1[0].map], [1_790_000_000_000, 23, "Lotus"]);
});

test("valorant match details", () => {
  const details = normalizeValorantMatches(
    [
      {
        metadata: { match_id: "m1" },
        players: [
          { puuid: "other", team_id: "Blue" },
          { puuid: "abc", team_id: "Red", agent: { name: "Jett" }, stats: { kills: 21, deaths: 14, assists: 5 } },
        ],
        teams: [
          { team_id: "Red", won: true, rounds: { won: 13, lost: 9 } },
          { team_id: "Blue", won: false },
        ],
      },
    ],
    { puuid: "abc" },
  );
  assert.deepEqual(details.m1, {
    agent: "Jett", kills: 21, deaths: 14, assists: 5,
    headshots: null, bodyshots: null, legshots: null, score: null, damage: null,
    won: true, roundsWon: 13, roundsLost: 9,
  });
});


test("valorant full match scoreboard", () => {
  const m = normalizeValorantMatch({
    metadata: {
      match_id: "m1", map: { id: "map-uuid", name: "Ascent" }, queue: { name: "Competitive" },
      started_at: "2026-11-04T18:00:00Z", game_length_in_ms: 2_100_000,
    },
    teams: [
      { team_id: "Red", won: true, rounds: { won: 13, lost: 7 } },
      { team_id: "Blue", won: false, rounds: { won: 7, lost: 13 } },
    ],
    players: [
      { puuid: "a", name: "Low", tag: "1", team_id: "Blue", agent: { id: "sage", name: "Sage" }, tier: { id: 12, name: "Gold 1" },
        stats: { score: 2000, kills: 8, deaths: 15, assists: 9, headshots: 2, bodyshots: 18, legshots: 0, damage: { dealt: 1600 } } },
      { puuid: "b", name: "Phami", tag: "EUW", team_id: "Red", agent: { id: "jett", name: "Jett" }, tier: { id: 18, name: "Diamond 1" },
        stats: { score: 6000, kills: 25, deaths: 10, assists: 3, headshots: 10, bodyshots: 30, legshots: 0, damage: { dealt: 3200 } } },
    ],
  });
  assert.equal(m.map, "Ascent");
  assert.equal(m.rounds, 20);
  assert.equal(m.startedAt, Date.parse("2026-11-04T18:00:00Z"));
  assert.equal(m.players[0].name, "Phami"); // sorted by ACS
  assert.deepEqual(
    [m.players[0].acs, m.players[0].adr, m.players[0].headshotPct, m.players[0].rank],
    [300, 160, 25, "Diamond 1"],
  );
  assert.match(m.players[0].rankIcon, /\/18\/largeicon\.png$/);
  assert.match(m.players[0].agentIcon, /agents\/jett\/displayicon\.png$/);
});
