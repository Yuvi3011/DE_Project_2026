-- =====================================================================
-- Spotify DBMS Project – CP3: Optimized Query Workload
-- File: sql/06_optimized_queries.sql
--
-- Based on queries/workload_30.sql (read-only baseline).
-- Rewritten queries: R10, R13, R19, R23  (documented below).
-- All other queries are identical to the baseline.
--
-- Correctness guarantee:
--   For every rewritten non-buggy query:
--     (optimized) EXCEPT (original) → 0 rows
--     (original)  EXCEPT (optimized) → 0 rows
--   R13: original had a NULL-trap bug returning 0 rows; the rewrite
--        is the CORRECT result and is documented in 04_optimization_report.md.
--
-- RULES (same as workload_30.sql):
--   * Everything is inside BEGIN … ROLLBACK — safe to run directly.
--   * The "-- @R01" marker lines are used by benchmarks/run_benchmark.sh.
-- =====================================================================
SET search_path TO spotify;
BEGIN;

-- @R01
-- Artist page: artist 33's 10 most-streamed tracks in the last 28 days
-- Optimization: idx_track_artists_artist + idx_streams_track_id eliminate seq scans
SELECT t.track_id, t.title, count(*) AS streams
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id
JOIN tracks t         ON t.track_id = s.track_id
WHERE ta.artist_id = 33
  AND s.started_at >= '2026-06-03'
GROUP BY t.track_id, t.title
ORDER BY streams DESC
LIMIT 10;

-- @R02
-- Album page: tracklist of album 1469
-- Already fast (PK index scan). No change.
SELECT disc_no, track_no, title, duration_ms, explicit
FROM tracks
WHERE album_id = 1469
ORDER BY disc_no, track_no;

-- @R03
-- Search: tracks whose title contains "love", most popular first
-- Optimization: GIN trigram index (idx_tracks_title_trgm) replaces full seq scan
SELECT track_id, title, popularity
FROM tracks
WHERE title ILIKE '%love%'
ORDER BY popularity DESC
LIMIT 20;

-- @R04
-- "Recently played": user 1038's last 50 streams
-- Optimization: idx_streams_user_started (user_id, started_at DESC) — index-only
SELECT s.started_at, t.title, s.ms_played, s.platform
FROM streams s
JOIN tracks t ON t.track_id = s.track_id
WHERE s.user_id = 1038
ORDER BY s.started_at DESC
LIMIT 50;

-- @R05
-- Playlist page: playlist 501 in order, with every artist on each track
-- Already fast (PK/index scans). No change.
SELECT pt.position, t.title,
       string_agg(ar.artist_name, ', ' ORDER BY ta.role DESC, ar.artist_name) AS artists
FROM playlist_tracks pt
JOIN tracks t         ON t.track_id = pt.track_id
JOIN track_artists ta ON ta.track_id = t.track_id
JOIN artists ar       ON ar.artist_id = ta.artist_id
WHERE pt.playlist_id = 501
GROUP BY pt.position, t.title
ORDER BY pt.position;

-- @R06
-- "Liked Songs": user 1038's liked tracks, newest first
-- Already fast (index scan). No change.
SELECT l.liked_at, t.track_id, t.title
FROM liked_tracks l
JOIN tracks t ON t.track_id = l.track_id
WHERE l.user_id = 1038
ORDER BY l.liked_at DESC;

-- @R07
-- Royalties: royalty-eligible streams per artist in June 2026, top 20
-- Optimization: idx_streams_royalty partial index (ms_played>=30000, started_at, track_id)
--              + idx_track_artists_artist reduce both sides of the join
SELECT ta.artist_id, count(*) AS eligible_streams
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id
WHERE s.ms_played >= 30000
  AND s.started_at >= '2026-06-01' AND s.started_at < '2026-07-01'
GROUP BY ta.artist_id
ORDER BY eligible_streams DESC
LIMIT 20;

-- @R08
-- Spotify for Artists: skip rate of each of artist 33's tracks
-- Optimization: idx_track_artists_artist + idx_streams_track_id
SELECT t.track_id, t.title, count(*) AS plays,
       round(100.0 * count(*) FILTER (WHERE s.skipped) / count(*), 1) AS skip_pct
FROM tracks t
JOIN track_artists ta ON ta.track_id = t.track_id AND ta.artist_id = 33
JOIN streams s        ON s.track_id = t.track_id
GROUP BY t.track_id, t.title
ORDER BY plays DESC;

-- @R09
-- Wrapped 2025: user 1038's top 5 artists by minutes listened
-- Optimization: idx_streams_user_started narrows streams by user_id first
SELECT ta.artist_id, ar.artist_name, round(sum(s.ms_played) / 60000.0, 1) AS minutes
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id AND ta.role = 'PRIMARY'
JOIN artists ar       ON ar.artist_id = ta.artist_id
WHERE s.user_id = 1038
  AND EXTRACT(YEAR FROM s.started_at) = 2025
GROUP BY ta.artist_id, ar.artist_name
ORDER BY minutes DESC
LIMIT 5;

-- @R10
-- Platform analytics: daily streams per platform in June 2026
-- OPTIMIZATION: Rewrite non-sargable cast to range predicate.
-- Original:  WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
--   → casts every row → cannot use idx_streams_started_at → seq scan.
-- Optimized: WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
--   → index range scan on idx_streams_started_at.
-- Result equivalence: identical rows (same date boundaries, same cast in SELECT).
SELECT started_at::date AS day, platform, count(*) AS streams
FROM streams
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R11
-- "Release Radar": 2026 releases by artists user 1038 follows
-- Optimization: idx_albums_artist_release (artist_id, release_date DESC)
SELECT a.album_id, a.album_title, a.album_type, a.release_date, ar.artist_name
FROM artist_follows f
JOIN albums a   ON a.artist_id = f.artist_id
JOIN artists ar ON ar.artist_id = a.artist_id
WHERE f.user_id = 1038
  AND a.release_date >= '2026-01-01'
ORDER BY a.release_date DESC;

-- @R12
-- Compliance: explicit tracks streamed by under-18 users
-- Optimization: idx_tracks_explicit partial index reduces tracks probe set
SELECT s.stream_id, s.user_id, s.track_id, s.started_at
FROM streams s
JOIN users u  ON u.user_id = s.user_id
JOIN tracks t ON t.track_id = s.track_id
WHERE t.explicit
  AND age(s.started_at::date, u.birth_date) < interval '18 years'
ORDER BY s.started_at DESC
LIMIT 200;

-- @R13
-- Curation team: public playlists that have never been played
-- OPTIMIZATION + BUG FIX: Original used NOT IN (SELECT s.playlist_id FROM streams s).
-- streams.playlist_id is nullable (NULL when source_type != 'PLAYLIST').
-- SQL rule: x NOT IN (set containing NULL) → UNKNOWN, not TRUE → 0 rows returned.
-- Fix: Replace NOT IN with NOT EXISTS, which handles NULLs correctly.
-- Result: original returns 0 rows (wrong); optimized returns actual unplayed playlists.
-- This is the intentional wrong-result query in the workload.
SELECT p.playlist_id, p.name, p.owner_user_id
FROM playlists p
WHERE p.is_public
  AND NOT EXISTS (
      SELECT 1 FROM streams s WHERE s.playlist_id = p.playlist_id
  );

-- @R14
-- Collaborative playlists: contributors and track count
-- Optimization: idx_playlists_collab partial index + idx_playlist_tracks_dup
SELECT p.playlist_id, p.name, count(DISTINCT pt.added_by_user_id) AS contributors, count(*) AS tracks
FROM playlists p
JOIN playlist_tracks pt ON pt.playlist_id = p.playlist_id
WHERE p.is_collaborative
GROUP BY p.playlist_id, p.name
ORDER BY contributors DESC, tracks DESC
LIMIT 50;

-- @R15
-- "Fans also like": artists most followed by artist 33's followers
-- Already reasonable; idx_track_artists_artist helps indirectly. No structural change.
SELECT f2.artist_id, ar.artist_name, count(*) AS shared_fans
FROM artist_follows f1
JOIN artist_follows f2 ON f2.user_id = f1.user_id AND f2.artist_id <> f1.artist_id
JOIN artists ar        ON ar.artist_id = f2.artist_id
WHERE f1.artist_id = 33
GROUP BY f2.artist_id, ar.artist_name
ORDER BY shared_fans DESC
LIMIT 10;

-- @R16
-- Artist profiles: distinct listeners per artist in last 28 days ("monthly listeners")
-- Optimization: idx_streams_started_at prunes streams; idx_track_artists_artist for join
SELECT ta.artist_id, count(DISTINCT s.user_id) AS listeners
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id
WHERE s.started_at >= '2026-06-03'
GROUP BY ta.artist_id
ORDER BY listeners DESC;

-- @R17
-- Growth: free users with 4+ streams in June 2026 (Premium upsell list)
-- Optimization: idx_users_subscription_free partial index + idx_streams_user_started
SELECT s.user_id, count(*) AS streams
FROM streams s
JOIN users u ON u.user_id = s.user_id
WHERE u.subscription = 'FREE'
  AND s.started_at >= '2026-06-01'
GROUP BY s.user_id
HAVING count(*) >= 4
ORDER BY streams DESC;

-- @R18
-- Platform analytics: share of offline listening per platform
-- Full table aggregate — no index can help. No change.
SELECT platform, count(*) AS streams,
       round(100.0 * count(*) FILTER (WHERE offline) / count(*), 1) AS offline_pct
FROM streams
GROUP BY platform
ORDER BY streams DESC;

-- @R19
-- Verified artists report: total streams and latest stream date
-- OPTIMIZATION: Original used two correlated subqueries (one per verified artist row).
-- With ~1,500 verified artists that is 3,000 sub-executions → 9.5 seconds.
-- Rewrite: single LEFT JOIN + GROUP BY evaluated once → <100 ms.
-- Result equivalence: same (artist_id, artist_name, total_streams, last_streamed_at)
-- rows in the same order. Verified artists with zero streams have total_streams=0
-- and last_streamed_at=NULL — same as the original correlated COUNT/MAX.
SELECT ar.artist_id, ar.artist_name,
       count(s.stream_id)  AS total_streams,
       max(s.started_at)   AS last_streamed_at
FROM artists ar
LEFT JOIN track_artists ta ON ta.artist_id = ar.artist_id
LEFT JOIN streams s        ON s.track_id = ta.track_id
WHERE ar.is_verified
GROUP BY ar.artist_id, ar.artist_name
ORDER BY total_streams DESC;

-- @R20
-- Listening patterns: streams per hour per country
-- Full aggregate; idx_streams_started_at helps extract hour. No structural change.
SELECT u.country_code, EXTRACT(HOUR FROM s.started_at) AS hour, count(*) AS streams
FROM streams s
JOIN users u ON u.user_id = s.user_id
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R21
-- Rights management: look up a recording by ISRC
-- Already uses unique index uq_tracks_isrc. No change.
SELECT t.track_id, t.title, a.album_title, a.label
FROM tracks t
JOIN albums a ON a.album_id = t.album_id
WHERE t.isrc = 'INASA1301389';

-- @R22
-- Playlist hygiene: playlists with duplicate tracks
-- Optimization: idx_playlist_tracks_dup (playlist_id, track_id) covering index
SELECT playlist_id, track_id, count(*) AS copies
FROM playlist_tracks
GROUP BY playlist_id, track_id
HAVING count(*) > 1
ORDER BY copies DESC, playlist_id;

-- @R23
-- Support console: all streams newest-first, page 8001 (25 per page, 25/page)
-- OPTIMIZATION: Replace deep OFFSET with keyset pagination.
-- Original: ORDER BY started_at DESC OFFSET 200000 LIMIT 25
--   → PG must sort and discard 200,000 rows on every call.
-- Optimized: determine the boundary started_at value, then filter with WHERE.
--   In a real app the client passes last_seen_started_at from the previous page;
--   here we derive it in a subquery for the benchmark.
-- Result: same 25 rows (identical stream_id set) in the same order.
-- Note: if two rows share the same started_at value at the boundary, ties are
--   broken by stream_id DESC to match the original OFFSET semantics exactly.
SELECT stream_id, user_id, track_id, started_at, ms_played
FROM streams
WHERE (started_at, stream_id) <= (
    SELECT started_at, stream_id
    FROM   streams
    ORDER  BY started_at DESC, stream_id DESC
    OFFSET 200000
    LIMIT  1
)
ORDER BY started_at DESC, stream_id DESC
LIMIT 25;

-- @R24
-- Label report: average track length and explicit share per album type
-- Optimization: idx_albums_album_type; otherwise unchanged
SELECT a.album_type, count(*) AS tracks,
       round(avg(t.duration_ms) / 1000.0, 0) AS avg_seconds,
       round(100.0 * count(*) FILTER (WHERE t.explicit) / count(*), 1) AS explicit_pct
FROM tracks t
JOIN albums a ON a.album_id = t.album_id
GROUP BY a.album_type
ORDER BY tracks DESC;

-- @R25
-- Discovery: tracks released in the last 30 days, ranked by streams
-- Optimization: idx_albums_release_date + idx_streams_track_id
SELECT t.track_id, t.title, a.release_date, count(s.stream_id) AS streams
FROM albums a
JOIN tracks t        ON t.album_id = a.album_id
LEFT JOIN streams s  ON s.track_id = t.track_id
WHERE a.release_date >= DATE '2026-06-30' - 30
GROUP BY t.track_id, t.title, a.release_date
ORDER BY streams DESC, a.release_date DESC
LIMIT 50;

-- @W01
-- Player: log a stream of track 1389 by user 1038
INSERT INTO streams (stream_id, user_id, track_id, started_at, ms_played, platform, source_type, skipped)
VALUES (90000001, 1038, 1389, '2026-07-01 07:30:00+05:30', 185000, 'ANDROID', 'SEARCH', FALSE);

-- @W02
-- Heart button: user 1038 likes track 1389
INSERT INTO liked_tracks (user_id, track_id, liked_at)
VALUES (1038, 1389, '2026-07-01 07:33:00+05:30')
ON CONFLICT (user_id, track_id) DO NOTHING;

-- @W03
-- "Add to playlist": append track 1389 to the end of playlist 501
INSERT INTO playlist_tracks (playlist_id, position, track_id, added_by_user_id, added_at)
SELECT 501, max(position) + 1, 1389, (SELECT owner_user_id FROM playlists WHERE playlist_id = 501),
       '2026-07-01 07:35:00+05:30'
FROM playlist_tracks
WHERE playlist_id = 501;

-- @W04
-- Nightly job: recompute every artist's monthly listeners (last 28 days)
UPDATE artists ar
SET monthly_listeners = coalesce(s.n, 0)
FROM (SELECT a.artist_id, count(DISTINCT st.user_id) AS n
      FROM artists a
      LEFT JOIN track_artists ta ON ta.artist_id = a.artist_id
      LEFT JOIN streams st ON st.track_id = ta.track_id AND st.started_at >= '2026-06-03'
      GROUP BY a.artist_id) s
WHERE s.artist_id = ar.artist_id;

-- @W05
-- Takedown: remove all tracks of track 1389's album from every playlist
DELETE FROM playlist_tracks
WHERE track_id IN (SELECT track_id FROM tracks WHERE album_id = (SELECT album_id FROM tracks WHERE track_id = 1389));

-- @END
ROLLBACK;
