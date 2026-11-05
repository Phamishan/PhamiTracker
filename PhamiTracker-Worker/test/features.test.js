import test from "node:test";
import assert from "node:assert/strict";
import { normalizeApexPredator } from "../src/apex.js";
import { apnsJwt } from "../src/live.js";
import { actAt, parseActs } from "../src/periods.js";
import { characterStats, periodStats } from "../src/stats.js";

const DAY = 86_400_000;
const t0 = Date.UTC(2026, 10, 1, 12);
const game = (i, delta, score, detail = {}) => ({ ts: t0 + i * 3_600_000, delta, score_after: score, kind: "match", detail });

test("legend/agent stats", () => {
  const stats = characterStats([
    game(0, 50, 1050, { legend: "Wraith" }),
    game(1, -20, 1030, { legend: "Wraith" }),
    game(2, 80, 1110, { legend: "Bangalore" }),
    { ...game(3, -500, 610), kind: "adjust" },
  ]);
  assert.deepEqual(stats, [
    { name: "Wraith", matches: 2, delta: 30, wins: 1 },
    { name: "Bangalore", matches: 1, delta: 80, wins: 1 },
  ]);
});

test("split recap and records", () => {
  const rows = [
    { ...game(-1, -2000, 8000), kind: "adjust" }, // split reset
    game(0, 60, 8060, { legend: "Wraith" }),
    game(1, 90, 8150, { legend: "Wraith" }),
    game(2, -40, 8110, { legend: "Bangalore" }),
    game(26, 120, 8230, { legend: "Bangalore" }), // next day
    game(27, 30, 8260, { legend: "Bangalore" }),
  ];
  const s = periodStats(rows);
  assert.equal(s.games, 5);
  assert.equal(s.startScore, 8000);
  assert.equal(s.endScore, 8260);
  assert.equal(s.net, 260);
  assert.deepEqual(s.peak, { score: 8260, ts: rows.at(-1).ts });
  assert.deepEqual(s.streak, { won: true, count: 2 });
  assert.equal(s.longestWinStreak, 2);
  assert.deepEqual(s.bestDay, { day: "2026-11-02", delta: 150 });
  assert.equal(s.biggestGain.delta, 120);
  assert.equal(s.biggestLoss.delta, -40);
  assert.equal(s.topCharacter.name, "Wraith"); // 150 vs 110, both played twice+
  assert.equal(s.daysPlayed, 2);
  assert.deepEqual(periodStats([]), { games: 0 });
});

test("VALORANT acts from valorant-api.com", () => {
  const acts = parseActs({
    data: [
      { uuid: "e9", displayName: "EPISODE 9", type: null, startTime: "2026-01-01T00:00:00Z", endTime: "2026-12-01T00:00:00Z" },
      { uuid: "a2", displayName: "ACT II", type: "EAresSeasonType::Act", parentUuid: "e9", startTime: "2026-09-01T00:00:00Z", endTime: "2026-11-15T00:00:00Z" },
      { uuid: "a1", displayName: "ACT I", type: "EAresSeasonType::Act", parentUuid: "e9", startTime: "2026-06-01T00:00:00Z", endTime: "2026-09-01T00:00:00Z" },
    ],
  });
  assert.deepEqual(acts.map((a) => a.name), ["Episode 9 · Act I", "Episode 9 · Act II"]);
  const { current, previous } = actAt(acts, t0);
  assert.equal(current.name, "Episode 9 · Act II");
  assert.equal(previous.name, "Episode 9 · Act I");
});

test("predator cutoffs", () => {
  const p = normalizeApexPredator({
    RP: { PC: { val: 24078, totalMastersAndPreds: 13000, updateTimestamp: 1_790_000_000 }, SWITCH: { val: 0 } },
  });
  assert.deepEqual(p, { PC: { cutoff: 24078, masters: 13000, updatedAt: 1_790_000_000_000 } });
});

test("APNs token is a valid ES256 JWT", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  const env = { APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "KEY123", APNS_TEAM_ID: "TEAM42" };
  const jwt = await apnsJwt(env, t0);
  const [header, claims, signature] = jwt.split(".");
  const decode = (s) => JSON.parse(Buffer.from(s, "base64url").toString());
  assert.deepEqual(decode(header), { alg: "ES256", kid: "KEY123" });
  assert.deepEqual(decode(claims), { iss: "TEAM42", iat: t0 / 1000 });
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    Buffer.from(signature, "base64url"),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.ok(ok);
});
