-- Running Live Activities: the ActivityKit push token for each, and the score the session started at.
CREATE TABLE live_activities (
  token TEXT PRIMARY KEY,
  player_id TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  sandbox INTEGER NOT NULL DEFAULT 0,  -- 1 for debug builds (APNs sandbox)
  start_score INTEGER,
  started_at INTEGER NOT NULL
);
CREATE INDEX live_activities_player ON live_activities (player_id, started_at);
