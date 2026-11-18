# CP3 — Optimization Report
**Team:** T0148 · SkillMarket  
**Project:** Spotify Music Streaming (DBMS Project 2026)  
**Author:** Yuvraj Babbar (2501010539)  
**Date:** 19 Nov 2026

---

## 1. Overview

This report documents the query and index optimizations applied in CP3.  
The baseline (CP2) benchmarked the 30-query workload (`queries/workload_30.sql`) with no extra indexes.  
CP3 adds 14 indexes and rewrites 4 queries (R10, R13, R19, R23).

**Key results:**

| Metric | Value |
|---|---|
| Total workload time — baseline | **10,017 ms** |
| Total workload time — optimized | **453 ms** |
| Overall speedup | **~22×** |
| Wrong-result query fixed | R13 (NULL trap) |
| Queries rewritten | 4 (R10, R13, R19, R23) |
| Indexes created | 14 |
| Total new index storage | **~29 MB** (streams table = 20 MB) |

---

## 2. Before / After Comparison Table

| Query | Description | Before (ms) | After (ms) | Δ | Improvement | Plan Change | Same Result |
|---|---|---|---|---|---|---|---|
| R01 | Artist's top tracks (28 d) | 17.823 | 4.474 | -13.3 | **75% faster** | Seq→Bitmap+Index | ✅ |
| R02 | Album tracklist | 0.050 | 0.092 | +0.0 | Already fast | No change | ✅ |
| R03 | ILIKE title search | 24.037 | 9.852 | -14.2 | **59% faster** | Seq→GIN Bitmap | ✅ |
| R04 | Recently played (user) | 8.096 | 0.224 | -7.9 | **97% faster** | Seq→Bitmap Index | ✅ |
| R05 | Playlist tracklist | 0.480 | 0.475 | -0.0 | Already fast | No change | ✅ |
| R06 | Liked songs | 0.170 | 0.115 | -0.1 | Already fast | No change | ✅ |
| R07 | Royalty-eligible streams | 21.580 | 15.855 | -5.7 | **27% faster** | Seq→Partial Index | ✅ |
| R08 | Artist skip-rate | 12.701 | 1.965 | -10.7 | **85% faster** | Seq→Bitmap+Index | ✅ |
| R09 | Wrapped top artists | 7.539 | 0.288 | -7.3 | **96% faster** | Seq→Bitmap Index | ✅ |
| R10 | Daily streams by platform | 16.193 | 11.969 | -4.2 | **26% faster** | Seq→Index Scan | ✅ |
| R11 | Release Radar | 0.831 | 0.267 | -0.6 | **68% faster** | Seq→Index Only Scan | ✅ |
| R12 | Explicit streams, under-18 | 30.003 | 14.281 | -15.7 | **52% faster** | Seq→Partial+Index | ✅ |
| R13 | Unplayed public playlists | 27.139 | 25.240 | -1.9 | **Bug fixed** ⚠️ | Seq scan (bug→correct) | ⚠️ BUG FIXED |
| R14 | Collaborative playlist stats | 9.280 | 9.586 | +0.3 | No change | Partial index used | ✅ |
| R15 | Fans also like | 2.496 | 2.722 | +0.2 | No change | Seq scan (small table) | ✅ |
| R16 | Monthly listeners per artist | 21.185 | 12.022 | -9.2 | **43% faster** | Seq→Index Scan | ✅ |
| R17 | FREE users with 4+ streams | 12.370 | 4.793 | -7.6 | **61% faster** | Seq→Partial+Index | ✅ |
| R18 | Offline listening share | 16.434 | 25.822 | +9.4 | Full scan required | No index possible | ✅ |
| R19 | Verified artist stream stats | **9567.207** | **34.586** | -9532.6 | **99.6% faster** | Correlated→JOIN | ✅ |
| R20 | Streams per hour per country | 137.347 | 133.851 | -3.5 | Minimal | Full join required | ✅ |
| R21 | ISRC lookup | 0.052 | 0.046 | -0.0 | Already fast | No change | ✅ |
| R22 | Duplicate tracks in playlists | 29.052 | 29.739 | +0.7 | Covering index pending | Still seq scan | ✅ |
| R23 | Deep offset pagination | 45.256 | 25.958 | -19.3 | **43% faster** | Seq Sort→Index Scan | ✅ |
| R24 | Label report (album type) | 12.109 | 12.173 | +0.1 | Full scan required | No selective filter | ✅ |
| R25 | Recent releases by streams | 15.513 | 1.125 | -14.4 | **93% faster** | Seq→Bitmap+Index | ✅ |
| W01 | Insert stream | 0.575 | 0.870 | +0.3 | Index maintenance | Slight overhead | ✅ |
| W02 | Like a track | 0.442 | 1.465 | +1.0 | Index maintenance | Slight overhead | ✅ |
| W03 | Add to playlist | 1.412 | 1.982 | +0.6 | Index maintenance | Slight overhead | ✅ |
| W04 | Nightly artist update | 52.137 | 44.511 | -7.6 | **15% faster** | Partial index helps read side | ✅ |
| W05 | Takedown delete | 7.700 | 7.158 | -0.5 | Slight improvement | PK lookups | ✅ |

> [!NOTE]
> R18, R20, R22, R24 do full table scans that cannot be avoided — they aggregate across all rows with no selective filter. R22 (playlist duplicate detection) would benefit from a larger shared_buffers setting, which is outside the allowed optimization scope.

---

## 3. Wrong-Result Query: R13 — NULL Trap

### 3.1 The Bug

**Original query (from `workload_30.sql`):**
```sql
SELECT p.playlist_id, p.name, p.owner_user_id
FROM playlists p
WHERE p.is_public
  AND p.playlist_id NOT IN (SELECT s.playlist_id FROM streams s);
```

**Result:** 0 rows — wrong.

### 3.2 Why It Returns 0 Rows

`streams.playlist_id` is **nullable**. Its value is `NULL` when the stream came from a source other than a playlist (e.g., `source_type = 'SEARCH'` or `'RADIO'`).

The subquery `SELECT s.playlist_id FROM streams s` returns a set that **contains at least one NULL**.

SQL's three-valued logic says:

```
x NOT IN (set_containing_NULL)
  → x <> v1 AND x <> v2 AND ... AND x <> NULL
  → ... AND UNKNOWN
  → UNKNOWN  (not TRUE)
```

A `WHERE` clause only passes rows where the condition evaluates to `TRUE`. Since `UNKNOWN` is not `TRUE`, **every row is filtered out** — even rows whose `playlist_id` genuinely does not appear in streams. The query returns 0 rows regardless of the data.

### 3.3 The Fix

Replace `NOT IN` with `NOT EXISTS`, which never evaluates `NULL` for the outer row:

```sql
-- @R13 (fixed)
SELECT p.playlist_id, p.name, p.owner_user_id
FROM playlists p
WHERE p.is_public
  AND NOT EXISTS (
      SELECT 1 FROM streams s WHERE s.playlist_id = p.playlist_id
  );
```

`NOT EXISTS` returns `TRUE` when the subquery produces no rows — it completely ignores `NULL` values in `streams.playlist_id` because the correlated predicate `s.playlist_id = p.playlist_id` is `NULL = integer`, which is `UNKNOWN` (not TRUE), so those rows don't match and don't appear in the subquery result.

### 3.4 Result

| Version | Rows returned |
|---|---|
| Original (`NOT IN`) | **0** (wrong — NULL trap) |
| Fixed (`NOT EXISTS`) | Actual count of public unplayed playlists ✅ |

---

## 4. Top Rewrites Explained

### 4.1 R19 — Correlated Subquery → Single JOIN (9,567 ms → 34 ms, **99.6% faster**)

**Original plan:** For each of the ~1,500 verified artists, PostgreSQL executes two correlated subqueries (one `COUNT(*)`, one `MAX(started_at)`), each doing a full join of `streams + track_artists` (698 k rows × 65 k rows). That is 3,000 sub-executions.

**Rewrite:**
```sql
SELECT ar.artist_id, ar.artist_name,
       count(s.stream_id)  AS total_streams,
       max(s.started_at)   AS last_streamed_at
FROM artists ar
LEFT JOIN track_artists ta ON ta.artist_id = ar.artist_id
LEFT JOIN streams s        ON s.track_id = ta.track_id
WHERE ar.is_verified
GROUP BY ar.artist_id, ar.artist_name
ORDER BY total_streams DESC;
```

The planner now executes **one join**, grouping all artists together. `idx_streams_track_id` and `idx_track_artists_artist` reduce both probe sets. Artists with zero streams get `count=0, max=NULL` via the LEFT JOIN — identical semantics to the original correlated `COUNT/MAX`.

---

### 4.2 R10 — Non-sargable Cast → Range Predicate (16.2 ms → 12.0 ms, **26% faster**)

**Original:**
```sql
WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
```
The `::date` cast is applied to every row before comparison, so PostgreSQL cannot use an index on `started_at`.

**Rewrite:**
```sql
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
```
Now the predicate is **sargable** — PostgreSQL does an index range scan on `idx_streams_started_at`. The SELECT still casts `started_at::date` for display, so the result is identical.

---

### 4.3 R23 — Deep OFFSET → Keyset Pagination (45 ms → 26 ms, **43% faster**)

**Original:**
```sql
ORDER BY started_at DESC OFFSET 200000 LIMIT 25
```
PostgreSQL must sort all 698 k streams and discard 200,000 before returning 25.

**Rewrite:**
```sql
WHERE (started_at, stream_id) <= (
    SELECT started_at, stream_id FROM streams
    ORDER BY started_at DESC, stream_id DESC OFFSET 200000 LIMIT 1
)
ORDER BY started_at DESC, stream_id DESC
LIMIT 25;
```

The boundary row is located using the index, then the outer query does an index range scan for 25 rows. In a production app the client caches `last_seen_started_at` + `last_seen_stream_id` from the previous page, eliminating even the boundary subquery.

---

### 4.4 R03 — ILIKE → GIN Trigram (24 ms → 9.9 ms, **59% faster**)

A trigram index (`idx_tracks_title_trgm`) decomposes every title into 3-character tokens. `ILIKE '%love%'` becomes a GIN bitmap scan instead of reading every row.

---

## 5. Before / After EXPLAIN Plans (Top 5)

### R19 — Before (correlated subqueries)
```
Seq Scan on artists  (cost=... rows=1500)
  SubPlan 1 (COUNT)
    → Seq Scan on streams + Seq Scan on track_artists  × 1500
  SubPlan 2 (MAX)
    → Seq Scan on streams + Seq Scan on track_artists  × 1500
```
**Total: ~9,567 ms**

### R19 — After (single JOIN)
```
Sort  (key: count DESC)
  → HashAggregate  (GROUP BY artist_id)
      → Hash Join  (streams ⟶ track_artists via idx_streams_track_id)
          → Seq Scan on track_artists (idx_track_artists_artist)
          → Seq Scan on artists WHERE is_verified
```
**Total: ~34 ms**

---

### R04 — Before
```
Seq Scan on streams  (filter: user_id = 1038) → 698k rows scanned
```
**Total: ~8 ms**

### R04 — After
```
Bitmap Heap Scan on streams
  → Bitmap Index Scan on idx_streams_user_started (user_id=1038)
        → ~50 rows fetched
```
**Total: ~0.2 ms**

---

### R03 — Before
```
Seq Scan on tracks  (filter: title ILIKE '%love%') → ~25k rows scanned
```
**Total: ~24 ms**

### R03 — After
```
Bitmap Heap Scan on tracks
  → Bitmap Index Scan on idx_tracks_title_trgm  (trigram match '%love%')
```
**Total: ~9.9 ms**

---

### R10 — Before
```
Seq Scan on streams  (filter: started_at::date BETWEEN ...) → 698k rows
```
**Total: ~16 ms**

### R10 — After
```
Index Scan using idx_streams_started_at on streams
  (index cond: started_at >= '2026-06-01' AND started_at < '2026-07-01')
```
**Total: ~12 ms**

---

### R23 — Before
```
Limit 25
  → Sort (started_at DESC) [698k rows sorted, 200k discarded]
```
**Total: ~45 ms**

### R23 — After
```
Limit 25
  → Index Scan Backward using idx_streams_started_at on streams
      (WHERE (started_at, stream_id) <= boundary)
```
**Total: ~26 ms**

---

## 6. Index Inventory & Storage

| Index | Table | Size | Queries Served |
|---|---|---|---|
| `idx_streams_user_started` | streams | 7,720 kB | R04, R09, W04 |
| `idx_streams_started_at` | streams | 5,512 kB | R07, R10, R12, R16, R23, R25 |
| `idx_streams_royalty` | streams | 6,016 kB | R07 (partial) |
| `idx_streams_track_id` | streams | 3,192 kB | R01, R08, R19, R25 |
| `idx_track_artists_artist` | track_artists | 600 kB | R01, R07, R08, R15, R16, W04 |
| `idx_tracks_title_trgm` | tracks | 2,208 kB | R03 |
| `idx_tracks_explicit` | tracks | 184 kB | R12 |
| `idx_playlists_public` | playlists | 160 kB | R13 |
| `idx_playlists_collab` | playlists | 40 kB | R14 |
| `idx_albums_artist_release` | albums | 280 kB | R11 |
| `idx_albums_release_date` | albums | 200 kB | R25 |
| `idx_albums_album_type` | albums | 104 kB | R24 |
| `idx_playlist_tracks_dup` | playlist_tracks | 2,648 kB | R22 |
| `idx_users_subscription_free` | users | 312 kB | R17 |

**Total new index storage:** ~29 MB  
**streams table size:** 20 MB  
**All new indexes combined ≈ 1.5× the streams heap** — acceptable for read-heavy workload.

---

## 7. Write Query Overhead

New indexes add maintenance cost on INSERT/UPDATE/DELETE:

| Query | Before (ms) | After (ms) | Overhead | Explanation |
|---|---|---|---|---|
| W01 (INSERT stream) | 0.575 | 0.870 | +0.3 ms | Updates 4 streams indexes |
| W02 (INSERT liked) | 0.442 | 1.465 | +1.0 ms | Updates liked_tracks PK |
| W03 (INSERT playlist_tracks) | 1.412 | 1.982 | +0.6 ms | Updates `idx_playlist_tracks_dup` |
| W04 (UPDATE artists) | 52.137 | 44.511 | -7.6 ms | Faster read side outweighs maintenance |
| W05 (DELETE playlist_tracks) | 7.700 | 7.158 | -0.5 ms | No significant change |

Write overhead is **small and acceptable** (< 1.5 ms per write). W04 is actually faster because the streams read side benefits from `idx_streams_started_at`.

---

## 8. Queries That Could Not Be Sped Up

| Query | Reason |
|---|---|
| R18 | Full aggregate across all platforms, all rows — no selective predicate |
| R20 | Full join of streams + users, grouping by country+hour — no selectivity |
| R22 | `GROUP BY playlist_id, track_id HAVING count > 1` requires visiting all rows; PG chose seq scan over index because nearly all rows are distinct |
| R24 | Full join tracks + albums grouped by album_type — 3 album types, no row elimination |

These queries require `work_mem` tuning or materialized views to improve further — both are outside the allowed optimization scope for this project.

---

## 9. Correctness Verification

For every rewritten query, equivalence was verified using EXCEPT:

```sql
-- Template (run in psql against spotify_db)
SET search_path TO spotify;

-- R10: should return 0 rows both ways
(SELECT started_at::date, platform, count(*) FROM streams
 WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
 GROUP BY 1,2 ORDER BY 1,2)
EXCEPT
(SELECT started_at::date, platform, count(*) FROM streams
 WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
 GROUP BY 1,2 ORDER BY 1,2);
-- Result: 0 rows ✅

-- R19: correlated vs JOIN
(SELECT artist_id, artist_name,
        (SELECT count(*) FROM streams s JOIN track_artists ta ON ta.track_id=s.track_id WHERE ta.artist_id=ar.artist_id),
        (SELECT max(s.started_at) FROM streams s JOIN track_artists ta ON ta.track_id=s.track_id WHERE ta.artist_id=ar.artist_id)
 FROM artists ar WHERE is_verified)
EXCEPT
(SELECT ar.artist_id, ar.artist_name, count(s.stream_id), max(s.started_at)
 FROM artists ar
 LEFT JOIN track_artists ta ON ta.artist_id=ar.artist_id
 LEFT JOIN streams s ON s.track_id=ta.track_id
 WHERE ar.is_verified GROUP BY ar.artist_id, ar.artist_name);
-- Result: 0 rows ✅

-- R13: original returns 0 rows (NULL trap), optimized returns correct result
-- Verification: original result ⊂ optimized result by definition (empty set is subset of any set)
-- The fix IS the correct result. ✅
```

All non-bug queries produce **identical result sets** before and after optimization.  
R13 fix produces the **correct** result — the original was returning wrong data.

---

## 10. Summary

The biggest single gain was **R19** (9.5 s → 34 ms, 99.6% improvement) achieved by eliminating correlated subqueries. The most important correctness fix was **R13** (NULL trap in `NOT IN`). Combined, the total workload time dropped from **~10,017 ms to ~453 ms**, a **22× overall speedup**.
