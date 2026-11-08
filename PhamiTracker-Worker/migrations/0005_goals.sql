-- Rank goals, so the worker can notify the phone the moment its owner reaches one.
-- The app sends them with its notification registration (POST /v1/notifications).
CREATE TABLE goals (
  token TEXT NOT NULL REFERENCES devices (token) ON DELETE CASCADE,
  player_id TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  target_score INTEGER NOT NULL,
  PRIMARY KEY (token, player_id)
);
CREATE INDEX goals_player ON goals (player_id);
