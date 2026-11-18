-- =====================================================================
-- Spotify DBMS Project – CP3: Index Definitions
-- File: sql/05_indexes.sql
--
-- PURPOSE: Create all indexes needed to speed up the 30-query workload.
-- Run ONCE against the database: psql -h localhost -d spotify_db -f sql/05_indexes.sql
-- =====================================================================
SET search_path TO spotify;

-- -----------------------------------------------------------------------
-- EXTENSION: pg_trgm (required for GIN trigram indexes used in ILIKE search)
-- -----------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- -----------------------------------------------------------------------
-- TABLE: streams  (698 k rows — the hottest table in the workload)
-- -----------------------------------------------------------------------

-- R04, R09, W04
-- User + time index: "recently played" lookups, Wrapped stats, nightly update job.
-- Composite (user_id, started_at DESC) lets PG do an index-only scan when
-- filtering by user_id and sorting by started_at without touching the heap.
CREATE INDEX IF NOT EXISTS idx_streams_user_started
    ON streams (user_id, started_at DESC);

-- R07, R10, R16, R25
-- Bare started_at index: covers all range queries on streams.started_at
-- (June 2026 filter in R07/R10, last-28-days window in R16, 30-day window in R25).
CREATE INDEX IF NOT EXISTS idx_streams_started_at
    ON streams (started_at);

-- R01, R08, R19
-- track_id index on streams: needed for the JOIN streams→track_artists in every
-- artist-centric query. Without it PG does a full seq scan of 698 k rows.
CREATE INDEX IF NOT EXISTS idx_streams_track_id
    ON streams (track_id);

-- R07: royalty partial index
-- Only streams with ms_played >= 30000 are royalty-eligible.
-- A partial index is much smaller than a full index and covers R07 exactly.
CREATE INDEX IF NOT EXISTS idx_streams_royalty
    ON streams (started_at, track_id)
    WHERE ms_played >= 30000;

-- -----------------------------------------------------------------------
-- TABLE: track_artists
-- -----------------------------------------------------------------------

-- R01, R08, R15, R16, W04
-- artist_id index on track_artists: used in every "find tracks by artist" join.
-- Column order: artist_id first so PG can filter by artist before joining streams.
CREATE INDEX IF NOT EXISTS idx_track_artists_artist
    ON track_artists (artist_id);

-- -----------------------------------------------------------------------
-- TABLE: playlists
-- -----------------------------------------------------------------------

-- R13 (fixed version): partial index for public playlists only.
-- WHERE is_public = true keeps the index tiny (only public playlists qualify).
CREATE INDEX IF NOT EXISTS idx_playlists_public
    ON playlists (playlist_id)
    WHERE is_public = true;

-- R14: collaborative playlists lookup.
-- Partial index covers the WHERE p.is_collaborative filter with minimal storage.
CREATE INDEX IF NOT EXISTS idx_playlists_collab
    ON playlists (playlist_id)
    WHERE is_collaborative = true;

-- -----------------------------------------------------------------------
-- TABLE: albums
-- -----------------------------------------------------------------------

-- R11: "Release Radar" – filter by artist_id then sort by release_date DESC.
-- Composite (artist_id, release_date DESC) is an index-only covering scan for R11.
CREATE INDEX IF NOT EXISTS idx_albums_artist_release
    ON albums (artist_id, release_date DESC);

-- R25: tracks released in the last 30 days.
-- range scan on release_date to find recent albums.
CREATE INDEX IF NOT EXISTS idx_albums_release_date
    ON albums (release_date);

-- R24: album_type lookup for label report.
CREATE INDEX IF NOT EXISTS idx_albums_album_type
    ON albums (album_type);

-- -----------------------------------------------------------------------
-- TABLE: tracks
-- -----------------------------------------------------------------------

-- R03: ILIKE '%love%' search.
-- GIN trigram index converts the ILIKE into a bitmap index scan instead of a
-- full seq scan.  Requires pg_trgm extension (created above).
CREATE INDEX IF NOT EXISTS idx_tracks_title_trgm
    ON tracks USING gin (title gin_trgm_ops);

-- R12: compliance query filters WHERE t.explicit.
-- Partial index returns only explicit tracks, drastically shrinking the probe set.
CREATE INDEX IF NOT EXISTS idx_tracks_explicit
    ON tracks (track_id)
    WHERE explicit = true;

-- -----------------------------------------------------------------------
-- TABLE: playlist_tracks
-- -----------------------------------------------------------------------

-- R22: duplicate-track detection (GROUP BY playlist_id, track_id).
-- Covering index lets PG resolve the GROUP BY from the index alone.
CREATE INDEX IF NOT EXISTS idx_playlist_tracks_dup
    ON playlist_tracks (playlist_id, track_id);

-- -----------------------------------------------------------------------
-- TABLE: users
-- -----------------------------------------------------------------------

-- R17: filter users WHERE subscription = 'FREE'.
-- Partial index (subscription is an enum with 3 values) keeps the index small.
CREATE INDEX IF NOT EXISTS idx_users_subscription_free
    ON users (user_id)
    WHERE subscription = 'FREE';

-- -----------------------------------------------------------------------
-- ANALYZE – update planner statistics so the new indexes are used immediately
-- -----------------------------------------------------------------------
ANALYZE streams;
ANALYZE track_artists;
ANALYZE playlists;
ANALYZE albums;
ANALYZE tracks;
ANALYZE playlist_tracks;
ANALYZE users;
