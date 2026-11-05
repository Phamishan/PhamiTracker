-- Automatic Live Activities. A phone with the setting on registers its push-to-start token for
-- its linked players; the poller starts an activity on it when one of them starts playing.
CREATE TABLE live_subscriptions (
  start_token TEXT NOT NULL,
  player_id TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  sandbox INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (start_token, player_id)
);
CREATE INDEX live_subscriptions_player ON live_subscriptions (player_id);

-- A player's current session: from the first sign of play until 45 minutes after the last game.
CREATE TABLE live_sessions (
  player_id TEXT PRIMARY KEY REFERENCES players (id) ON DELETE CASCADE,
  started_at INTEGER NOT NULL,
  start_score INTEGER,
  last_activity_at INTEGER NOT NULL
);
