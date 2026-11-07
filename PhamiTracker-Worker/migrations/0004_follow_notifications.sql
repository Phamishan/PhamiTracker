-- Push notifications about favourited players. A phone with notifications on registers its APNs
-- token and the players it favourited; the poller tracks those players (every 5 minutes) and
-- notifies the phone about rank changes, streaks and session recaps.
CREATE TABLE devices (
  token TEXT PRIMARY KEY,
  sandbox INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);

CREATE TABLE follows (
  token TEXT NOT NULL REFERENCES devices (token) ON DELETE CASCADE,
  player_id TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (token, player_id)
);
CREATE INDEX follows_player ON follows (player_id);

-- Streak and session bookkeeping for followed players (JSON), so notifications fire once.
ALTER TABLE players ADD COLUMN notify TEXT;
