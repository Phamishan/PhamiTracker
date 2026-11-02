-- One row per tracked account. `state` holds the latest normalized snapshot as JSON.
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  game TEXT NOT NULL,                 -- 'apex' | 'valorant'
  name TEXT NOT NULL,
  tag TEXT NOT NULL DEFAULT '',       -- VALORANT tag, '' for Apex
  platform TEXT NOT NULL,             -- Apex: PC/PS4/X1/SWITCH, VALORANT: pc/console
  region TEXT NOT NULL DEFAULT '',    -- VALORANT region, '' for Apex
  external_id TEXT,                   -- Apex uid / VALORANT puuid
  score INTEGER,                      -- Apex RP / VALORANT elo
  state TEXT,
  next_poll_at INTEGER NOT NULL DEFAULT 0,
  last_polled_at INTEGER,
  last_change_at INTEGER,
  last_opened_at INTEGER NOT NULL,
  error TEXT,
  error_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  UNIQUE (game, platform, region, name, tag)
);
CREATE INDEX players_due ON players (game, next_poll_at);

-- Every rank change the poller sees. `detail` is JSON (legend/agent, map, KDA, ...).
CREATE TABLE matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  ts INTEGER NOT NULL,
  delta INTEGER NOT NULL,
  score_after INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'match', -- 'match' | 'adjust' (season reset, decay, ...)
  detail TEXT,
  external_id TEXT,
  UNIQUE (player_id, external_id)
);
CREATE INDEX matches_player_ts ON matches (player_id, ts);

CREATE TABLE cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
