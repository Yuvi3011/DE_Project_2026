# Phase 3: Baseline Timings Report

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Team:** T0148 · **Section:** E · **Database:** PostgreSQL 17.11  
**Laptop:** Apple MacBook Pro (Apple Silicon)  
**Method:** `EXPLAIN (ANALYZE, BUFFERS)` · 3 runs per query · average of `Execution Time`  
**Benchmark script:** `./benchmarks/run_benchmark.sh spotify_db baseline`

---

## 1. Baseline Timing Table (All 30 Queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Artist page: artist 33's 10 most-streamed tracks in the last 28 days | READ | 25.700 | 14.294 | 13.475 | 17.823 |
| R02: Album page: tracklist of album 1469 | READ | 0.026 | 0.042 | 0.082 | 0.050 |
| R03: Search: tracks whose title contains "love", most popular first | READ | 32.862 | 20.794 | 18.455 | 24.037 |
| R04: "Recently played": user 1038's last 50 streams | READ | 7.795 | 7.514 | 8.978 | 8.096 |
| R05: Playlist page: playlist 501 in order, with every artist on each track | READ | 0.615 | 0.457 | 0.369 | 0.480 |
| R06: "Liked Songs": user 1038's liked tracks, newest first | READ | 0.243 | 0.200 | 0.067 | 0.170 |
| R07: Royalties: streams of 30 seconds or more ("royalty-eligible") per artist in June 2026, top 20 | READ | 33.938 | 16.323 | 14.480 | 21.580 |
| R08: Spotify for Artists: skip rate of each of artist 33's tracks | READ | 12.702 | 13.180 | 12.221 | 12.701 |
| R09: Wrapped 2025: user 1038's top 5 artists by minutes listened | READ | 9.293 | 6.238 | 7.086 | 7.539 |
| R10: Platform analytics: daily streams per platform in June 2026 | READ | 17.929 | 15.425 | 15.224 | 16.193 |
| R11: "Release Radar": 2026 releases by artists user 1038 follows | READ | 0.704 | 0.480 | 1.309 | 0.831 |
| R12: Compliance: explicit tracks streamed by users who were under 18 at the time | READ | 37.398 | 27.013 | 25.598 | 30.003 |
| R13: Curation team: public playlists that have never been played | READ | 27.994 | 29.175 | 24.247 | 27.139 |
| R14: Collaborative playlists: number of different people who added tracks | READ | 9.519 | 9.296 | 9.025 | 9.280 |
| R15: "Fans also like": artists most followed by the followers of artist 33 | READ | 2.704 | 2.263 | 2.522 | 2.496 |
| R16: Artist profiles: distinct listeners of every artist in the last 28 days ("monthly listeners") | READ | 22.562 | 21.502 | 19.491 | 21.185 |
| R17: Growth: free users with 4+ streams in June 2026 (Premium upsell list) | READ | 12.816 | 12.027 | 12.266 | 12.370 |
| R18: Platform analytics: share of offline listening per platform | READ | 16.722 | 16.135 | 16.445 | 16.434 |
| R19: Verified artists report: total streams and the latest stream of every verified artist | READ | 9484.509 | 9511.404 | 9705.707 | 9567.207 |
| R20: Listening patterns: streams per hour of the day per country | READ | 135.143 | 137.980 | 138.919 | 137.347 |
| R21: Rights management: look up a recording by its ISRC code | READ | 0.053 | 0.041 | 0.063 | 0.052 |
| R22: Playlist hygiene: playlists that contain the same track more than once | READ | 32.488 | 28.576 | 26.091 | 29.052 |
| R23: Support console: all streams, newest first, page 8,001 (25 per page) | READ | 46.039 | 44.749 | 44.980 | 45.256 |
| R24: Label report: average track length and explicit share per album type | READ | 12.690 | 11.932 | 11.705 | 12.109 |
| R25: Discovery: tracks released in the last 30 days, ranked by streams | READ | 15.684 | 15.278 | 15.577 | 15.513 |
| W01: Player: log a stream of track 1389 by user 1038 | WRITE | 0.848 | 0.424 | 0.454 | 0.575 |
| W02: Heart button: user 1038 likes track 1389 | WRITE | 0.428 | 0.424 | 0.475 | 0.442 |
| W03: "Add to playlist": append track 1389 to the end of playlist 501 | WRITE | 1.417 | 1.415 | 1.404 | 1.412 |
| W04: Nightly job: recompute every artist's monthly listeners (last 28 days) | WRITE | 72.149 | 44.302 | 39.960 | 52.137 |
| W05: Takedown: the label withdrew the whole album of track 1389, so remove its tracks from every playlist | WRITE | 7.497 | 7.673 | 7.929 | 7.700 |
| **Total (sum of all 30)** | | **10,118.168** | **10,044.774** | **10,195.277** | **10,119.406** |

---

## 2. Scan Type and Performance Analysis per Query

### Fast Queries (< 1 ms average) — Already use index scans

| Query | Avg (ms) | Scan Type | Why fast? |
|---|---:|---|---|
| **R02** | 0.050 | Index Scan using `uq_tracks_album_disc_track` | Composite UNIQUE index on `(album_id, disc_no, track_no)` enables direct lookup by `album_id = 1469`. Very few rows returned (one album's tracklist). |
| **R05** | 0.480 | Index Scan on `pk_playlist_tracks`, `pk_tracks`, `pk_track_artists`, `pk_artists` | PK index on `(playlist_id, position)` narrows to ~12 tracks. All subsequent joins use PK indexes. Small result set. |
| **R06** | 0.170 | Index Scan on `pk_liked_tracks`, `pk_tracks` | PK `(user_id, track_id)` lets PG find user 1038's liked tracks directly. Small result set for one user. |
| **R11** | 0.831 | Index Only Scan on `pk_artist_follows` + Seq Scan on `albums` | PK `(user_id, artist_id)` retrieves user 1038's followed artists instantly. Albums table is scanned but filtered quickly by `release_date >= '2026-01-01'`. |
| **R21** | 0.052 | Index Scan on `uq_tracks_isrc` + `pk_albums` | UNIQUE index on `isrc` gives O(log n) lookup. Single row returned. |
| **W01** | 0.575 | (no scan) — direct INSERT | Simple insert into `streams`. PK constraint check is O(log n). |
| **W02** | 0.442 | (no scan) — INSERT with ON CONFLICT | PK `(user_id, track_id)` on `liked_tracks` handles conflict detection efficiently. |

### Moderate Queries (1–50 ms) — Mostly Seq Scans on `streams` (250k rows)

| Query | Avg (ms) | Scan Type | Why this speed? |
|---|---:|---|---|
| **R01** | 17.823 | Seq Scan on `streams` + Seq Scan on `track_artists` | No index on `streams(started_at)` or `track_artists(artist_id)`. Must scan 250k streams rows + 77k track_artists rows. |
| **R03** | 24.037 | Seq Scan on `tracks` | `ILIKE '%love%'` with leading wildcard prevents any B-tree usage. Must scan all 67,808 tracks. |
| **R04** | 8.096 | Seq Scan on `streams` | No index on `streams(user_id)`. Scans 250k rows to find one user's streams. |
| **R07** | 21.580 | Seq Scan on `streams` | Needs to scan streams for June 2026 date range + ms_played >= 30000 filter. No index exists. |
| **R08** | 12.701 | Seq Scan on `streams` + Seq Scan on `track_artists` | No index on `track_artists(artist_id)` or `streams(track_id)`. Joins two large unindexed tables. |
| **R09** | 7.539 | Seq Scan on `streams` | No index on `streams(user_id)` or `streams(started_at)`. Full scan filtered by user + year. |
| **R10** | 16.193 | Seq Scan on `streams` | `started_at::date` cast prevents index usage. Full table scan of 250k rows with grouping. |
| **R12** | 30.003 | Seq Scan on `streams`, `tracks`, `users` | Three-way join with Seq Scans on all three tables. `age()` computation and `explicit` filter prevent efficient access. |
| **R13** | 27.139 | Seq Scan on `playlists` + Seq Scan on `streams` | `NOT IN (SELECT playlist_id FROM streams)` triggers full scan of streams. Also returns 0 rows due to NULL bug (see Phase 2). |
| **R14** | 9.280 | Seq Scan on `playlist_tracks` + `playlists` | No index on `playlists(is_collaborative)`. Scans 120k playlist_tracks. |
| **R15** | 2.496 | Seq Scan on `artist_follows` + Index Only Scan on `pk_artist_follows` | Self-join on artist_follows. First scan finds followers of artist 33, second uses PK index. Moderate cardinality. |
| **R16** | 21.185 | Seq Scan on `streams` + `track_artists` | Full scan of 250k streams joined with 77k track_artists. Heavy aggregation (count DISTINCT). |
| **R17** | 12.370 | Seq Scan on `streams` + `users` | Full scan of streams joined with users filtered by subscription = 'FREE'. No index on either filter column. |
| **R18** | 16.434 | Seq Scan on `streams` | Full table aggregation over 250k rows. Groups by platform. No filter to narrow scan. |
| **R22** | 29.052 | Seq Scan on `playlist_tracks` | Full scan of 120k rows for GROUP BY + HAVING. No selective filter. |
| **R23** | 45.256 | Seq Scan on `streams` | `ORDER BY started_at DESC OFFSET 200000 LIMIT 25` requires sorting all 250k rows and skipping 200k. Extremely wasteful pagination pattern. |
| **R24** | 12.109 | Seq Scan on `tracks` + `albums` | Full scan of 67k tracks joined with 12k albums. Groups by album_type (only 4 categories). |
| **R25** | 15.513 | Seq Scan on `streams` + `albums` | Date filter on albums + LEFT JOIN streams. No index on `albums(release_date)`. |
| **W03** | 1.412 | Index Scan on `pk_playlists` + Index Only Scan on `pk_playlist_tracks` | Subquery uses PK indexes to find max position and owner. Efficient. |
| **W04** | 52.137 | Seq Scan on `streams`, `track_artists`, `artists` | Recomputes monthly_listeners for ALL 3,000 artists. Seq scans on streams (250k) and track_artists (77k). Heavy aggregation. |
| **W05** | 7.700 | Index Scan on `pk_tracks` + Seq Scan on `playlist_tracks` | Subquery finds album tracks via PK. Delete scans playlist_tracks (120k) for matching track_ids. |

### Slowest Query — The Intentional Bottleneck

| Query | Avg (ms) | Scan Type | Why extremely slow? |
|---|---:|---|---|
| **R19** | 9,567.207 | Seq Scan on `artists` + Seq Scan on `streams` + `track_artists` (×2 correlated subqueries) | **Two correlated scalar subqueries** execute independently for each of the ~1,500 verified artists. Each subquery joins 250k streams × 77k track_artists. Total: ~1,500 × 2 × (250k join) = catastrophic O(n²) performance. This is the query the README warned about ("takes several seconds"). |
| **R20** | 137.347 | Seq Scan on `streams` + `users` | Full cross of 250k streams × 30k users grouped by country and hour. Large hash join + heavy grouping. |

---

## 3. Summary Statistics

| Metric | Value |
|---|---|
| **Total baseline time (all 30 queries)** | **10,119.406 ms** (~10.1 seconds) |
| **Slowest query** | R19 — 9,567.207 ms (94.5% of total time) |
| **Second slowest** | R20 — 137.347 ms |
| **Fastest query** | R02 — 0.050 ms |
| **Queries already fast (< 1 ms)** | R02, R05, R06, R11, R21, W01, W02 (7 queries) |
| **Queries needing optimization (> 10 ms)** | R01, R03, R04, R07, R08, R10, R12, R13, R14, R16, R17, R18, R19, R20, R22, R23, R24, R25, W04 (19 queries) |
| **Dominant scan type** | Seq Scan on `streams` (appears in 20 of 30 queries) |

---

## 4. Key Observations for Phase 4 Optimization

1. **`streams` table is the bottleneck**: 20 out of 30 queries perform Seq Scans on the 250k-row streams table. Targeted indexes on `(user_id, started_at)`, `(track_id)`, `(started_at)`, and partial indexes for date ranges will yield dramatic improvements.

2. **R19 is catastrophically slow**: Two correlated subqueries against the full streams table, repeated per verified artist. Rewriting as a single JOIN with GROUP BY should reduce this from ~9.5 seconds to under 100 ms.

3. **R13 returns wrong results**: The `NOT IN` with NULLable `playlist_id` column produces 0 rows instead of the correct answer. This is the "wrong-result query" mentioned in Phase 4 instructions.

4. **R23 uses OFFSET 200,000**: Deep pagination with OFFSET forces PG to sort and skip 200k rows. Keyset pagination (`WHERE started_at < last_seen_value`) would eliminate this.

5. **R03 uses `ILIKE '%love%'`**: Leading wildcard prevents B-tree indexes. A GIN trigram index (`pg_trgm`) is needed.

6. **R10 casts `started_at::date`**: Function on column prevents index usage. Rewriting as a range predicate (`started_at >= '2026-06-01' AND started_at < '2026-07-01'`) enables sargable index scans.
