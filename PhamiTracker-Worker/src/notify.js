// Push notifications about favourited players' grind: rank ups/downs, win and loss streaks, and a
// recap when their session ends. Phones register their APNs token plus the players they
// favourited (POST /v1/notifications); the poller calls notifyFollowers after every poll.

import { liveActivitiesEnabled, sendApns, sessionAttributes } from "./live.js";
import { rankLabel } from "./poller.js";
import { sessionIdleMs } from "./stats.js";

const MINUTES = 60_000;
// A session ends this long after the last game (same as Live Activities).
export const RECAP_AFTER_MS = sessionIdleMs("apex");
// Streak lengths that get a notification (and every 5 after 20).
const STREAK_MILESTONES = new Set([3, 5, 8, 10, 15, 20]);
export const isStreakMilestone = (n) =>
  STREAK_MILESTONES.has(n) || (n > 20 && n % 5 === 0);

const HEX_TOKEN = /^[0-9a-f]{32,256}$/;

/** Saves the phone and replaces the list of players it follows. `players` are worker ids. */
export async function registerDevice(
  env,
  { token, sandbox, players, goals = [] },
  now = Date.now(),
) {
  token = String(token ?? "").toLowerCase();
  if (!HEX_TOKEN.test(token))
    return { error: "token must be the hex push token" };
  // The phone's own rank goals: {playerId, label, targetScore}, only for players that exist.
  const valid = goals.filter(
    (g) =>
      g &&
      typeof g.playerId === "string" &&
      Number.isFinite(g.targetScore) &&
      g.label,
  );
  const known = valid.length
    ? new Set(
        (
          await env.DB.prepare(
            `SELECT id FROM players WHERE id IN (${valid.map(() => "?").join(",")})`,
          )
            .bind(...valid.map((g) => g.playerId))
            .all()
        ).results.map((row) => row.id),
      )
    : new Set();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT OR REPLACE INTO devices (token, sandbox, updated_at) VALUES (?, ?, ?)",
    ).bind(token, sandbox ? 1 : 0, now),
    env.DB.prepare("DELETE FROM follows WHERE token = ?").bind(token),
    ...players.map((id) =>
      env.DB.prepare(
        "INSERT OR IGNORE INTO follows (token, player_id, created_at) VALUES (?, ?, ?)",
      ).bind(token, id, now),
    ),
    env.DB.prepare("DELETE FROM goals WHERE token = ?").bind(token),
    ...valid
      .filter((g) => known.has(g.playerId))
      .map((g) =>
        env.DB.prepare(
          "INSERT OR REPLACE INTO goals (token, player_id, label, target_score) VALUES (?, ?, ?, ?)",
        ).bind(
          token,
          g.playerId,
          String(g.label).slice(0, 40),
          Math.round(g.targetScore),
        ),
      ),
  ]);
  return { ok: true, players, pushEnabled: liveActivitiesEnabled(env) };
}

const GOAL_REACHED = [
  "Screenshot it. Frame it. 🖼️",
  "Time to set a new one. 😤",
  "The grind paid off. 🏆",
];

/**
 * Called after every poll that moved the score up: tells the phone whose goal this player just
 * reached. Only fires when the score crosses the target, so it happens once.
 */
export async function notifyGoals(
  env,
  player,
  previousScore,
  now = Date.now(),
  rng = Math.random,
) {
  if (
    previousScore == null ||
    player.score == null ||
    player.score <= previousScore
  )
    return 0;
  const goals = (
    await env.DB.prepare(
      `SELECT g.label, g.target_score, d.token, d.sandbox FROM goals g JOIN devices d ON d.token = g.token
       WHERE g.player_id = ? AND g.target_score > ? AND g.target_score <= ?`,
    )
      .bind(player.id, previousScore, player.score)
      .all()
  ).results;
  if (goals.length === 0 || !liveActivitiesEnabled(env)) return 0;
  const unit = player.game === "apex" ? "RP" : "elo";
  let sent = 0;
  for (const goal of goals) {
    const joke =
      GOAL_REACHED[
        Math.floor(rng() * GOAL_REACHED.length) % GOAL_REACHED.length
      ];
    const payload = {
      aps: {
        alert: {
          title: "🎯 GOAL REACHED",
          body: `You hit ${goal.label} (${player.score.toLocaleString("en-US")} ${unit})\n${joke}`,
        },
        sound: "default",
        "thread-id": `goal-${player.id}`,
      },
    };
    const res = await sendApns(env, goal, payload, now, "alert").catch(() => ({
      ok: false,
    }));
    if (res.ok) sent++;
    else if (
      res.status === 410 ||
      /BadDeviceToken|ExpiredToken|Unregistered/.test(res.reason ?? "")
    ) {
      await unregisterDevice(env, goal.token);
    }
  }
  return sent;
}

export async function unregisterDevice(env, token) {
  token = String(token).toLowerCase();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM follows WHERE token = ?").bind(token),
    env.DB.prepare("DELETE FROM goals WHERE token = ?").bind(token),
    env.DB.prepare("DELETE FROM devices WHERE token = ?").bind(token),
  ]);
}

/**
 * What happened in this poll that followers should hear about, plus the updated bookkeeping.
 * `notify` = {streak: {won, count}, session: {games, net, lastAt}} from earlier polls.
 */
export function followEvents(game, prevState, state, matches, notify, now) {
  const next = {
    streak: notify?.streak ?? null,
    session: notify?.session ?? null,
  };
  const events = [];
  const played = matches
    .filter((m) => m.kind === "match")
    .sort((a, b) => a.ts - b.ts);
  const reset = matches.some((m) => m.kind === "adjust");
  const idle = sessionIdleMs(game);
  // When a game ended, roughly. Apex times are already when the RP changed; VALORANT times are
  // when the game started, so use when the poller saw it (this poll).
  const endedAt = (m) => (game === "valorant" ? now : m.ts);

  // A session that went quiet before these games is over: recap it first.
  const recap = () => {
    if (next.session?.games > 0)
      events.push({
        type: "recap",
        games: next.session.games,
        net: next.session.net,
      });
    next.session = null;
  };

  for (const m of played) {
    if (next.session && endedAt(m) - next.session.lastAt >= idle) recap();
    next.session ??= { games: 0, net: 0, lastAt: endedAt(m) };
    next.session.games += 1;
    next.session.net += m.delta;
    next.session.lastAt = endedAt(m);

    const won = m.detail?.won ?? m.delta > 0;
    next.streak =
      next.streak?.won === won
        ? { won, count: next.streak.count + 1 }
        : { won, count: 1 };
    if (isStreakMilestone(next.streak.count)) {
      events.push({
        type: won ? "winStreak" : "lossStreak",
        count: next.streak.count,
      });
    }
  }
  if (played.length === 0 && next.session && now - next.session.lastAt >= idle)
    recap();

  // Rank change (not season/act resets, and not dropping to unranked).
  const before = rankLabel(game, prevState);
  const after = rankLabel(game, state);
  if (
    !reset &&
    before &&
    after &&
    before !== after &&
    !/unrated|unranked/i.test(after + before)
  ) {
    events.push({
      type: state.score > prevState.score ? "rankUp" : "rankDown",
      rank: after,
    });
  }
  return { events, notify: next };
}

const RANK_UP = [
  "What a nerd! 🤓",
  "Mom, get the camera! 📸",
  "Respect the climb 🧗",
];
const RANK_DOWN = [
  "It's a tactical retreat.",
  "We don't talk about this one 🤫",
  "Must have been the teammates.",
];
const WIN_STREAK = [
  "Maybe touch some grass? 🌱",
  "THE GOAT 🐐",
  "Built different 🔥",
];
const LOSS_STREAK = [
  "The comeback starts soon 🙏",
  "Someone check up on them 😱😱",
  "It's not a slump, it's a vibe.",
];
const RECAP_UP = [
  "Certified grinder.",
  "Good shift. 🫡",
  "Time to celebrate! 🎉",
];
const RECAP_DOWN = [
  "Tomorrow's another day.",
  "We'll call that a warm-up.",
  "Better luck next time.",
];
const RECAP_EVEN = ["All that for nothing."];

export function message(event, { name, game, unit }, rng = Math.random) {
  const pick = (lines) =>
    lines[Math.floor(rng() * lines.length) % lines.length];
  // Short title (it only gets one line), what happened + the joke in the body.
  const note = (title, what, lines) => ({
    title,
    body: `${what}
${pick(lines)}`,
  });
  const apex = game === "apex";
  switch (event.type) {
    case "rankUp":
      return note("📈 RANK UP", `${name} ranked up to ${event.rank}`, RANK_UP);
    case "rankDown":
      return note(
        "📉 RANK DOWN",
        `${name} dropped to ${event.rank}`,
        RANK_DOWN,
      );
    case "winStreak":
      return note(
        "🔥 WIN STREAK",
        apex
          ? `${name} gained RP ${event.count} games in a row`
          : `${name} won ${event.count} games in a row`,
        WIN_STREAK,
      );
    case "lossStreak":
      return note(
        "🧊 LOSS STREAK",
        apex
          ? `${name} lost RP ${event.count} games in a row`
          : `${name} lost ${event.count} games in a row`,
        LOSS_STREAK,
      );
    case "recap": {
      const net = event.net > 0 ? `+${event.net}` : `${event.net}`;
      const games = `${event.games} ${event.games === 1 ? "game" : "games"}`;
      return note(
        "🎮 SESSION RECAP",
        `${name} finished with ${net} ${unit} over ${games}`,
        event.net > 0 ? RECAP_UP : event.net < 0 ? RECAP_DOWN : RECAP_EVEN,
      );
    }
    default:
      return null;
  }
}

/**
 * Called after every poll. Cheap when nothing happened: it only looks up followers when there
 * were games, a rank change or an open session to recap.
 */
export async function notifyFollowers(
  env,
  player,
  prevState,
  state,
  matches,
  now = Date.now(),
  rng = Math.random,
) {
  // First poll of a newly followed player: that's the baseline (and VALORANT's backfill), not news.
  if (!prevState) return 0;
  const notify = player.notify ? JSON.parse(player.notify) : null;
  const rankChanged =
    rankLabel(player.game, prevState) !== rankLabel(player.game, state);
  if (matches.length === 0 && !rankChanged && !notify?.session) return 0;

  const followers = (
    await env.DB.prepare(
      "SELECT d.token, d.sandbox FROM follows f JOIN devices d ON d.token = f.token WHERE f.player_id = ?",
    )
      .bind(player.id)
      .all()
  ).results;
  if (followers.length === 0) return 0;

  const { events, notify: next } = followEvents(
    player.game,
    prevState,
    state,
    matches,
    notify,
    now,
  );
  if (JSON.stringify(next) !== JSON.stringify(notify)) {
    await env.DB.prepare("UPDATE players SET notify = ? WHERE id = ?")
      .bind(JSON.stringify(next), player.id)
      .run();
  }
  if (events.length === 0 || !liveActivitiesEnabled(env)) return 0;

  const who = {
    name: sessionAttributes(player, state).player,
    game: player.game,
    unit: player.game === "apex" ? "RP" : "RR",
  };
  let sent = 0;
  for (const event of events) {
    const { title, body } = message(event, who, rng);
    const payload = {
      aps: { alert: { title, body }, sound: "default", "thread-id": player.id },
    };
    for (const follower of followers) {
      const res = await sendApns(env, follower, payload, now, "alert").catch(
        () => ({ ok: false }),
      );
      if (res.ok) sent++;
      else if (
        res.status === 410 ||
        /BadDeviceToken|ExpiredToken|Unregistered/.test(res.reason ?? "")
      ) {
        await unregisterDevice(env, follower.token);
      }
    }
  }
  return sent;
}
