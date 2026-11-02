import test from "node:test";
import assert from "node:assert/strict";
import { normalizeApexMaps, normalizeApexPlayer, rankedMapAt } from "../src/apex.js";
import {
  normalizeValorantHistoryV1,
  normalizeValorantHistoryV2,
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
  assert.deepEqual(details.m1, { agent: "Jett", kills: 21, deaths: 14, assists: 5, won: true, roundsWon: 13, roundsLost: 9 });
});
