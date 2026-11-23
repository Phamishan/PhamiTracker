-- Searching a player tracks them for a while (SEARCH_TRACK_DAYS, 21 by default, after the last search), so their
-- games are recorded from the first search on, even if nobody links or favourites them.
ALTER TABLE players ADD COLUMN last_searched_at INTEGER;
