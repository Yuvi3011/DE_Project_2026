# Phase 2: Schema Design, Normalization & Data Loading Report

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Team:** T0148 · **Section:** E · **Database:** PostgreSQL 17.11  
**Team Members:** Yuvraj Babbar (Lead: 2501010539), Samriddhi (2501010403), Vansh Grover (2501010493), Udhav Munish Sehgal (2501010595)  
**Repository:** [DE_Project_2026](https://github.com/Yuvi3011/DE_Project_2026)

---

## 1. Schema Architecture & Design Philosophy

The Spotify relational schema was reverse-engineered from raw production data exports (`seed_data/`), encompassing 698,735 records across 10 distinct entities. The architecture satisfies three foundational design criteria:
1. **Type Safety & Domain Precision:** Explicit domain types (e.g., `TIMESTAMPTZ` with timezone offsets, fixed-width `CHAR(12)` for standard ISRC and UPC codes, constrained `SMALLINT` for track indices) prevent data corruption at the storage layer.
2. **Referential & Business Rule Invariants:** Strict primary keys, candidate unique keys, and over 20 `CHECK` constraints encode core business rules (such as the 30-second royalty rule, playlist stream contextual rules, and collaborative privacy rules).
3. **Rigorous Normalization:** Every entity is formally evaluated and structured to meet **Boyce-Codd Normal Form (BCNF)**, with justified, well-managed denormalization documented for high-throughput operational aggregates.

---

## 2. Complete Data Dictionary

All tables are encapsulated within the dedicated `spotify` schema (`SET search_path TO spotify;`).

### 2.1 Table: `artists`
Represents verified musical creators, solo artists, and bands.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `artist_id` | `INTEGER` | `PRIMARY KEY` | Unique synthetic identifier for each artist. Fits within 32-bit signed int (3,000 seed rows, 60,000 at 20×). |
| `artist_name` | `VARCHAR(255)` | `NOT NULL` | Artist or band legal/stage name. Cannot be empty. |
| `country_code` | `CHAR(2)` | `NOT NULL, CHECK (~ '^[A-Z]{2}$')` | ISO 3166-1 alpha-2 country of origin code. |
| `primary_genre` | `VARCHAR(50)` | `NOT NULL` | Primary categorization tag (e.g., 'Indie', 'Punjabi', 'Electronic'). |
| `is_verified` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Flag indicating verified artist badge on the platform. |
| `monthly_listeners` | `INTEGER` | `NOT NULL DEFAULT 0, CHECK (>= 0)` | Denormalized count of distinct listeners in the trailing 28 days (updated by `W04`). |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Platform onboarding timestamp with timezone offset (`+05:30`). |

### 2.2 Table: `albums`
Musical packages (Albums, EPs, Singles, Compilations) published under record labels.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `album_id` | `INTEGER` | `PRIMARY KEY` | Unique synthetic identifier for the album release. |
| `artist_id` | `INTEGER` | `NOT NULL, REFERENCES artists(artist_id) ON DELETE RESTRICT` | Primary artist or releasing entity. Restricts accidental deletion of active catalog artists. |
| `album_title` | `VARCHAR(255)` | `NOT NULL` | Title of the album release. |
| `album_type` | `VARCHAR(20)` | `NOT NULL, CHECK (IN ('ALBUM', 'SINGLE', 'EP', 'COMPILATION'))` | Standard industry release categorization. |
| `release_date` | `DATE` | `NOT NULL` | Commercial release date (calendar day). |
| `label` | `VARCHAR(100)` | `NOT NULL` | Publishing record label or distributor (e.g., 'Tips', 'Sony Music', 'Saregama'). |
| `upc` | `CHAR(12)` | `NOT NULL UNIQUE, CHECK (~ '^[0-9]{12}$')` | Universal Product Code (12 numeric digits). Unique natural identifier for the commercial release. |

### 2.3 Table: `users`
Registered listeners across free and subscription tiers.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `user_id` | `INTEGER` | `PRIMARY KEY` | Unique synthetic user account identifier. |
| `email` | `VARCHAR(255)` | `NOT NULL UNIQUE, CHECK (~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')` | Unique user email address; validated against RFC standard email pattern. |
| `display_name` | `VARCHAR(100)` | `NOT NULL` | Public user profile name. |
| `country_code` | `CHAR(2)` | `NOT NULL, CHECK (~ '^[A-Z]{2}$')` | ISO 3166-1 alpha-2 country of residence. |
| `birth_date` | `DATE` | `NOT NULL, CHECK (>= '1900-01-01' AND <= CURRENT_DATE)` | User birth date required for age gating and minor compliance (`R12`). |
| `subscription` | `VARCHAR(20)` | `NOT NULL, CHECK (IN ('FREE', 'PREMIUM', 'DUO', 'FAMILY', 'STUDENT'))` | Current subscription tier governing upsell targeting (`R17`). |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Account registration timestamp with timezone. |

### 2.4 Table: `tracks`
Individual master audio recordings contained within albums.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `track_id` | `INTEGER` | `PRIMARY KEY` | Unique synthetic identifier for the audio recording. |
| `album_id` | `INTEGER` | `NOT NULL, REFERENCES albums(album_id) ON DELETE CASCADE` | Release containing the track. Cascades on album takedown/withdrawal (`W05`). |
| `disc_no` | `SMALLINT` | `NOT NULL DEFAULT 1, CHECK (> 0)` | Disc index in multi-disc releases (stored in 2 bytes). |
| `track_no` | `SMALLINT` | `NOT NULL, CHECK (> 0)` | Sequence number of the track on the given disc. |
| `title` | `VARCHAR(255)` | `NOT NULL` | Recording title. |
| `duration_ms` | `INTEGER` | `NOT NULL, CHECK (> 0)` | Total audio duration in milliseconds (positive integer). |
| `explicit` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Flag for explicit parental advisory lyrics/content (`R12`, `R24`). |
| `isrc` | `CHAR(12)` | `NOT NULL UNIQUE, CHECK (~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$')` | International Standard Recording Code. Global unique natural key (`R21`). |
| `popularity` | `SMALLINT` | `NOT NULL DEFAULT 0, CHECK (BETWEEN 0 AND 100)` | Spotify algorithmic popularity index bounded from 0 to 100 (`R03`). |
| — | — | `UNIQUE (album_id, disc_no, track_no)` | Natural composite candidate key ensuring no duplicate track numbers per album disc. |

### 2.5 Table: `track_artists`
Many-to-many associative entity mapping artists to recordings with billing roles.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `track_id` | `INTEGER` | `NOT NULL, REFERENCES tracks(track_id) ON DELETE CASCADE` | Recording identifier. Cascades when recording is removed. |
| `artist_id` | `INTEGER` | `NOT NULL, REFERENCES artists(artist_id) ON DELETE RESTRICT` | Credited artist. Restricts deletion of artists with catalog tracks. |
| `role` | `VARCHAR(10)` | `NOT NULL, CHECK (IN ('PRIMARY', 'FEATURED'))` | Billing role credit distinguishing lead performers from featured guests (`R05`, `R09`). |
| — | — | `PRIMARY KEY (track_id, artist_id)` | Composite primary key preventing duplicate credits for an artist on the same track. |

### 2.6 Table: `playlists`
User-curated playlists of tracks.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `playlist_id` | `INTEGER` | `PRIMARY KEY` | Unique synthetic identifier for the playlist. |
| `owner_user_id` | `INTEGER` | `NOT NULL, REFERENCES users(user_id) ON DELETE CASCADE` | Playlist creator/curator. Cascades if user deletes their account. |
| `name` | `VARCHAR(255)` | `NOT NULL` | User-defined playlist title. |
| `is_public` | `BOOLEAN` | `NOT NULL DEFAULT TRUE` | Flag indicating public discovery visibility (`R13`). |
| `is_collaborative` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Flag indicating multi-user collaborative editing permissions (`R14`). |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Playlist creation timestamp. |
| — | — | `CHECK (NOT (is_public AND is_collaborative))` | Business rule: collaborative playlists cannot be public. |

### 2.7 Table: `playlist_tracks`
Ordered track entries inside playlists.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `playlist_id` | `INTEGER` | `NOT NULL, REFERENCES playlists(playlist_id) ON DELETE CASCADE` | Enclosing playlist. Cascades when playlist is deleted. |
| `position` | `INTEGER` | `NOT NULL, CHECK (position >= 1)` | 1-based sequential position index in the playlist (`R05`, `W03`). |
| `track_id` | `INTEGER` | `NOT NULL, REFERENCES tracks(track_id) ON DELETE CASCADE` | Added audio track. Cascades on catalog withdrawal (`W05`). |
| `added_by_user_id` | `INTEGER` | `NOT NULL, REFERENCES users(user_id) ON DELETE CASCADE` | User who added the track (owner or collaborator in `R14`). |
| `added_at` | `TIMESTAMPTZ` | `NOT NULL` | Timestamp when track was added to the playlist. |
| — | — | `PRIMARY KEY (playlist_id, position)` | Essential: Playlists allow duplicate track additions at different positions (`R22`); primary key is `(playlist_id, position)`. |

### 2.8 Table: `streams`
Event telemetry stream capturing playback sessions across platforms.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `stream_id` | `BIGINT` | `PRIMARY KEY` | Global unique identifier. 64-bit integer accommodates high telemetry volume (> 5M rows). |
| `user_id` | `INTEGER` | `NOT NULL, REFERENCES users(user_id) ON DELETE CASCADE` | Listener account identifier (`R04`, `R09`, `R17`, `W01`). |
| `track_id` | `INTEGER` | `NOT NULL, REFERENCES tracks(track_id) ON DELETE RESTRICT` | Streamed track. Preserves audit logs for royalty accounting (`R07`, `R08`). |
| `started_at` | `TIMESTAMPTZ` | `NOT NULL` | Playback initiation timestamp with timezone offset (`R10`, `R20`). |
| `ms_played` | `INTEGER` | `NOT NULL, CHECK (ms_played >= 0)` | Playback duration in milliseconds. Governs royalty rule (`R07`). |
| `platform` | `VARCHAR(20)` | `NOT NULL, CHECK (IN ('ANDROID', 'IOS', 'DESKTOP', 'WEB', 'SPEAKER', 'CAR'))` | Client playback hardware/OS interface (`R10`, `R18`). |
| `source_type` | `VARCHAR(20)` | `NOT NULL, CHECK (IN ('PLAYLIST', 'ALBUM', 'ARTIST', 'RADIO', 'SEARCH'))` | UI discovery context initiating playback. |
| `playlist_id` | `INTEGER` | `NULL, REFERENCES playlists(playlist_id) ON DELETE SET NULL` | Origin playlist ID. Explicitly NULL unless `source_type = 'PLAYLIST'`. |
| `skipped` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Flag indicating early user skip (`R08`). |
| `offline` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Flag indicating cached offline playback (`R18`). Required default for `W01`. |
| — | — | `CHECK ((source_type = 'PLAYLIST' AND playlist_id IS NOT NULL) OR (source_type <> 'PLAYLIST' AND playlist_id IS NULL))` | Structural integrity: Playlist ID present if and only if source is `PLAYLIST`. |
| — | — | `CHECK (NOT skipped OR ms_played < 30000)` | Royalty rule: Skipped streams must have `ms_played < 30000`. |

### 2.9 Table: `liked_tracks`
Listener "Liked Songs" personal library collection.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `user_id` | `INTEGER` | `NOT NULL, REFERENCES users(user_id) ON DELETE CASCADE` | User saving the track (`R06`, `W02`). Cascades on user deletion. |
| `track_id` | `INTEGER` | `NOT NULL, REFERENCES tracks(track_id) ON DELETE CASCADE` | Favorited track. Cascades on track deletion. |
| `liked_at` | `TIMESTAMPTZ` | `NOT NULL` | Timestamp when user favorited the track. |
| — | — | `PRIMARY KEY (user_id, track_id)` | Composite PK preventing duplicate likes and supporting `ON CONFLICT` in `W02`. |

### 2.10 Table: `artist_follows`
Listener subscription to artist updates and Release Radar feeds.

| Column | Data Type | Constraints & Defaults | Rationale / Why |
|---|---|---|---|
| `user_id` | `INTEGER` | `NOT NULL, REFERENCES users(user_id) ON DELETE CASCADE` | Subscribing listener (`R11`, `R15`). |
| `artist_id` | `INTEGER` | `NOT NULL, REFERENCES artists(artist_id) ON DELETE CASCADE` | Followed artist. Cascades on account deletion. |
| `followed_at` | `TIMESTAMPTZ` | `NOT NULL` | Timestamp when follow action occurred. |
| — | — | `PRIMARY KEY (user_id, artist_id)` | Composite PK preventing redundant follow relationships. |

---

## 3. Entity-Relationship (ER) Diagram & Cardinalities

The physical schema relationships and cardinalities are rendered below. A high-resolution 3000×2150 diagram is committed in the repository at [er_diagram.png](file:///Users/yuvrajbabbar/Desktop/DE/diagrams/er_diagram.png).

![Spotify Relational ER Diagram](file:///Users/yuvrajbabbar/Desktop/DE/diagrams/er_diagram.png)

```mermaid
erDiagram
    artists ||--o{ albums : "releases (1:N)"
    albums ||--|{ tracks : "contains (1:N)"
    tracks ||--|{ track_artists : "performed_by (1:N)"
    artists ||--|{ track_artists : "credited_in (1:N)"
    users ||--o{ playlists : "owns / creates (1:N)"
    playlists ||--|{ playlist_tracks : "ordered_tracks (1:N)"
    tracks ||--o{ playlist_tracks : "included_in (1:N)"
    users ||--o{ playlist_tracks : "added_by (1:N)"
    users ||--o{ streams : "listens (1:N)"
    tracks ||--o{ streams : "played_in (1:N)"
    playlists ||--o{ streams : "context_source (0..1:N)"
    users ||--o{ liked_tracks : "likes (1:N)"
    tracks ||--o{ liked_tracks : "liked_by (1:N)"
    users ||--o{ artist_follows : "follows (1:N)"
    artists ||--o{ artist_follows : "followed_by (1:N)"

    artists {
        int artist_id PK
        varchar artist_name
        char country_code
        varchar primary_genre
        boolean is_verified
        int monthly_listeners
        timestamptz created_at
    }

    albums {
        int album_id PK
        int artist_id FK
        varchar album_title
        varchar album_type
        date release_date
        varchar label
        char upc UQ
    }

    tracks {
        int track_id PK
        int album_id FK
        smallint disc_no
        smallint track_no
        varchar title
        int duration_ms
        boolean explicit
        char isrc UQ
        smallint popularity
    }

    track_artists {
        int track_id PK,FK
        int artist_id PK,FK
        varchar role
    }

    users {
        int user_id PK
        varchar email UQ
        varchar display_name
        char country_code
        date birth_date
        varchar subscription
        timestamptz created_at
    }

    playlists {
        int playlist_id PK
        int owner_user_id FK
        varchar name
        boolean is_public
        boolean is_collaborative
        timestamptz created_at
    }

    playlist_tracks {
        int playlist_id PK,FK
        int position PK
        int track_id FK
        int added_by_user_id FK
        timestamptz added_at
    }

    streams {
        bigint stream_id PK
        int user_id FK
        int track_id FK
        timestamptz started_at
        int ms_played
        varchar platform
        varchar source_type
        int playlist_id FK
        boolean skipped
        boolean offline
    }

    liked_tracks {
        int user_id PK,FK
        int track_id PK,FK
        timestamptz liked_at
    }

    artist_follows {
        int user_id PK,FK
        int artist_id PK,FK
        timestamptz followed_at
    }
```

### 3.1 Referential Integrity & `ON DELETE` Action Matrix

| Foreign Key | Source Table | Target Table | `ON DELETE` | Engineering Justification |
|---|---|---|---|---|
| `fk_albums_artist` | `albums(artist_id)` | `artists(artist_id)` | `RESTRICT` | Prevents accidental cascading removal of active discography if artist record is purged. |
| `fk_tracks_album` | `tracks(album_id)` | `albums(album_id)` | `CASCADE` | Tracks are physical compositions of an album; withdrawal (`W05`) removes all associated tracks. |
| `fk_track_artists_track` | `track_artists(track_id)` | `tracks(track_id)` | `CASCADE` | Junction credits are dependent on the recording entity. |
| `fk_track_artists_artist` | `track_artists(artist_id)` | `artists(artist_id)` | `RESTRICT` | Cannot delete an artist if catalog tracks credit them as primary or featured. |
| `fk_playlists_owner` | `playlists(owner_user_id)` | `users(user_id)` | `CASCADE` | User account deletion removes user's curated playlists under GDPR privacy rules. |
| `fk_playlist_tracks_playlist` | `playlist_tracks(playlist_id)` | `playlists(playlist_id)` | `CASCADE` | Playlist track entries have no independent lifecycle without their parent playlist. |
| `fk_playlist_tracks_track` | `playlist_tracks(track_id)` | `tracks(track_id)` | `CASCADE` | When a recording is removed/withdrawn (`W05`), it must automatically disappear from all playlists. |
| `fk_playlist_tracks_added_by` | `playlist_tracks(added_by_user_id)` | `users(user_id)` | `CASCADE` | If a collaborator account is removed, their contributed track entries cascade cleanly. |
| `fk_streams_user` | `streams(user_id)` | `users(user_id)` | `CASCADE` | Account deletion purges private listening logs under right-to-be-forgotten regulations. |
| `fk_streams_track` | `streams(track_id)` | `tracks(track_id)` | `RESTRICT` | Essential for financial auditing: historical playback logs cannot be severed while royalties are payable. |
| `fk_streams_playlist` | `streams(playlist_id)` | `playlists(playlist_id)` | `SET NULL` | **Critical:** If a playlist is deleted, the playback telemetry remains valid historical data; `playlist_id` becomes `NULL`. |
| `fk_liked_tracks_user` | `liked_tracks(user_id)` | `users(user_id)` | `CASCADE` | User library entries are tied to user lifecycle. |
| `fk_liked_tracks_track` | `liked_tracks(track_id)` | `tracks(track_id)` | `CASCADE` | Favorited tracks are removed if track is deleted from platform. |
| `fk_artist_follows_user` | `artist_follows(user_id)` | `users(user_id)` | `CASCADE` | Follow relations are deleted if user departs. |
| `fk_artist_follows_artist` | `artist_follows(artist_id)` | `artists(artist_id)` | `CASCADE` | Follow relations are deleted if artist departs. |

---

## 4. Normalization & Functional Dependency Analysis

A relational schema is in **Boyce-Codd Normal Form (BCNF)** if and only if for every non-trivial functional dependency $X \rightarrow Y$, $X$ is a superkey. Every relation in our schema satisfies BCNF.

### 4.1 Relation: `artists`
- **Candidate Keys:** $\{ \text{artist\_id} \}$
- **Functional Dependencies:**
  - $\text{artist\_id} \rightarrow \{ \text{artist\_name}, \text{country\_code}, \text{primary\_genre}, \text{is\_verified}, \text{monthly\_listeners}, \text{created\_at} \}$
- **Analysis:** All attributes depend solely and directly on the primary key. Since $\text{artist\_id}$ is the sole determinant and is a superkey, `artists` is in **BCNF** (and trivially in 3NF).

### 4.2 Relation: `albums`
- **Candidate Keys:** $\{ \text{album\_id} \}$, $\{ \text{upc} \}$
- **Functional Dependencies:**
  - $\text{album\_id} \rightarrow \{ \text{artist\_id}, \text{album\_title}, \text{album\_type}, \text{release\_date}, \text{label}, \text{upc} \}$
  - $\text{upc} \rightarrow \{ \text{album\_id}, \text{artist\_id}, \text{album\_title}, \text{album\_type}, \text{release\_date}, \text{label} \}$
- **Analysis:** Both determinants are candidate keys. There are no transitive or partial dependencies. Thus, `albums` is in **BCNF**.

### 4.3 Relation: `users`
- **Candidate Keys:** $\{ \text{user\_id} \}$, $\{ \text{email} \}$
- **Functional Dependencies:**
  - $\text{user\_id} \rightarrow \{ \text{email}, \text{display\_name}, \text{country\_code}, \text{birth\_date}, \text{subscription}, \text{created\_at} \}$
  - $\text{email} \rightarrow \{ \text{user\_id}, \text{display\_name}, \text{country\_code}, \text{birth\_date}, \text{subscription}, \text{created\_at} \}$
- **Analysis:** Both $\text{user\_id}$ and $\text{email}$ are superkeys. The relation is in **BCNF**.

### 4.4 Relation: `tracks`
- **Candidate Keys:** $\{ \text{track\_id} \}$, $\{ \text{isrc} \}$, $\{ (\text{album\_id}, \text{disc\_no}, \text{track\_no}) \}$
- **Functional Dependencies:**
  - $\text{track\_id} \rightarrow \{ \text{album\_id}, \text{disc\_no}, \text{track\_no}, \text{title}, \text{duration\_ms}, \text{explicit}, \text{isrc}, \text{popularity} \}$
  - $\text{isrc} \rightarrow \{ \text{track\_id}, \text{album\_id}, \text{disc\_no}, \text{track\_no}, \text{title}, \text{duration\_ms}, \text{explicit}, \text{popularity} \}$
  - $\{ \text{album\_id}, \text{disc\_no}, \text{track\_no} \} \rightarrow \{ \text{track\_id}, \text{title}, \text{duration\_ms}, \text{explicit}, \text{isrc}, \text{popularity} \}$
- **Analysis:** Every determinant is a candidate key. There are no non-trivial dependencies on non-superkeys. Thus, `tracks` is in **BCNF**.

### 4.5 Relation: `track_artists`
- **Candidate Keys:** $\{ (\text{track\_id}, \text{artist\_id}) \}$
- **Functional Dependencies:**
  - $\{ \text{track\_id}, \text{artist\_id} \} \rightarrow \{ \text{role} \}$
- **Analysis:** The determinant is the entire composite primary key. No partial dependencies exist. `track_artists` is in **BCNF**.

### 4.6 Relation: `playlists`
- **Candidate Keys:** $\{ \text{playlist\_id} \}$
- **Functional Dependencies:**
  - $\text{playlist\_id} \rightarrow \{ \text{owner\_user\_id}, \text{name}, \text{is\_public}, \text{is\_collaborative}, \text{created\_at} \}$
- **Analysis:** Sole determinant is the primary key. `playlists` is in **BCNF**.

### 4.7 Relation: `playlist_tracks`
- **Candidate Keys:** $\{ (\text{playlist\_id}, \text{position}) \}$
- **Functional Dependencies:**
  - $\{ \text{playlist\_id}, \text{position} \} \rightarrow \{ \text{track\_id}, \text{added\_by\_user\_id}, \text{added\_at} \}$
- **Analysis:** Notice that $\text{track\_id}$ does NOT determine $\text{position}$ because a playlist can contain the same track multiple times (`R22`). The only candidate key is $\{ (\text{playlist\_id}, \text{position}) \}$. All non-key attributes functionally depend on the complete key. Thus, `playlist_tracks` is in **BCNF**.

### 4.8 Relation: `streams`
- **Candidate Keys:** $\{ \text{stream\_id} \}$
- **Functional Dependencies:**
  - $\text{stream\_id} \rightarrow \{ \text{user\_id}, \text{track\_id}, \text{started\_at}, \text{ms\_played}, \text{platform}, \text{source\_type}, \text{playlist\_id}, \text{skipped}, \text{offline} \}$
- **Analysis:** The determinant $\text{stream\_id}$ is a superkey. There are no partial or transitive dependencies. Thus, `streams` is in **BCNF**.

### 4.9 Relation: `liked_tracks` & `artist_follows`
- **Candidate Keys:** $\{ (\text{user\_id}, \text{track\_id}) \}$ and $\{ (\text{user\_id}, \text{artist\_id}) \}$ respectively.
- **Functional Dependencies:**
  - $\{ \text{user\_id}, \text{track\_id} \} \rightarrow \{ \text{liked\_at} \}$
  - $\{ \text{user\_id}, \text{artist\_id} \} \rightarrow \{ \text{followed\_at} \}$
- **Analysis:** All determinants are candidate superkeys. Both junction tables are in **BCNF**.

---

## 5. Analysis of Derived, Redundant & Denormalized Columns

In a pure theoretical relational model, redundant and derived attributes are eliminated. In production systems like Spotify, intentional denormalization is evaluated based on read/write tradeoffs and real-time SLA constraints:

### 5.1 `artists.monthly_listeners`
- **Derivation:** Recomputed via `count(DISTINCT s.user_id)` for streams occurring in the trailing 28 days (`s.started_at >= '2026-06-03'`).
- **Operational Reality:** Calculating 28-day distinct listeners on the fly requires an expensive aggregation across millions of stream rows (`R16`). If omitted, every single artist profile load would require an expensive hash aggregation, violating the < 5 ms page load SLA.
- **Maintenance Policy:** Spotify maintains this as a materialized metric updated by nightly batch jobs (`W04`). The slight staleness (eventual consistency) is acceptable in exchange for orders-of-magnitude faster profile reads. **Keeping this column is justified.**

### 5.2 `streams.skipped` vs `streams.ms_played`
- **Derivation:** In business logic, `skipped = TRUE` if and only if `ms_played < 30000` (and the user explicitly hit skip before natural track completion).
- **Operational Reality:** While `ms_played < 30000` could technically identify short streams, `skipped` explicitly records the *intent* (the listener actively skipped, as opposed to pausing, network failure, or listening to a 25-second interlude). Furthermore, querying `FILTER (WHERE s.skipped)` in `R08` avoids arithmetic evaluations on every row. **Keeping this boolean column is justified.**

### 5.3 Primary Artist in `track_artists` vs `albums.artist_id`
- **Derivation:** For single-artist albums, the track's primary artist usually matches `albums.artist_id`.
- **Operational Reality:** In compilations, movie soundtracks, EP collaborations, and split releases, individual tracks have different primary artists than the releasing curator or label (`albums.artist_id`). Normalizing artist credits to `track_artists` allows multi-artist billing (`PRIMARY` and `FEATURED`) as queried in `R05` and `R09`. **Separating these attributes is strictly required for musical correctness.**

---

## 6. Exploratory Data Analysis (EDA) & Data Inconsistencies Discovered

During comprehensive inspection of the 10 raw CSV files, several critical structural subtleties and edge cases were identified and solved:

### Discovery 1: `streams.playlist_id` Nullability Invariant
- **Finding:** Across all 250,000 stream records, `playlist_id` is populated in exactly 112,614 rows (45.0%) and `NULL` in 137,386 rows (55.0%).
- **Correlation:** An exact 1-to-1 correlation exists with `source_type`:
  - When `source_type = 'PLAYLIST'`, `playlist_id` is **never NULL** (112,614 / 112,614).
  - When `source_type IN ('ALBUM', 'ARTIST', 'RADIO', 'SEARCH')`, `playlist_id` is **always NULL** (137,386 / 137,386).
- **Enforcement:** Enforced via `CONSTRAINT chk_streams_playlist_source CHECK ((source_type = 'PLAYLIST' AND playlist_id IS NOT NULL) OR (source_type <> 'PLAYLIST' AND playlist_id IS NULL))`.

### Discovery 2: The `W01` Player Insert & Default Values
- **Finding:** Workload query `W01` executes the following write:
  ```sql
  INSERT INTO streams (stream_id, user_id, track_id, started_at, ms_played, platform, source_type, skipped)
  VALUES (90000001, 1038, 1389, '2026-07-01 07:30:00+05:30', 185000, 'ANDROID', 'SEARCH', FALSE);
  ```
- **Problem:** `W01` does not specify a value for `offline`. If `offline` is defined as `BOOLEAN NOT NULL` without a default, PostgreSQL aborts the transaction with `null value in column "offline" violates not-null constraint`.
- **Resolution:** Defined `offline BOOLEAN NOT NULL DEFAULT FALSE` and `skipped BOOLEAN NOT NULL DEFAULT FALSE`.

### Discovery 3: Duplicate Tracks in Playlists (`R22`)
- **Finding:** In `playlist_tracks.csv`, 1,800 track entries appear multiple times within the same playlist at different positions (e.g. tracks repeated in a long party playlist).
- **Design Impact:** Attempting to make `(playlist_id, track_id)` the primary key would fail and reject 1,800 valid production rows. Query `R22` specifically audits these duplicates. The true primary key is `(playlist_id, position)`.

### Discovery 4: The Three-Valued Logic NULL Trap in Query `R13`
- **Finding:** Query `R13` attempts to find unplayed public playlists using:
  ```sql
  SELECT p.playlist_id, p.name, p.owner_user_id
  FROM playlists p
  WHERE p.is_public
    AND p.playlist_id NOT IN (SELECT s.playlist_id FROM streams s);
  ```
- **Root Cause of Empty Result:** Because `streams.playlist_id` contains `NULL` values (for non-playlist streams), `NOT IN (SELECT s.playlist_id ...)` evaluates in SQL three-valued logic to `UNKNOWN` for all rows. Consequently, `R13` always returns 0 rows! This explains why the curation team reported Problem **P5** ("report always comes back empty"). In Phase 4, rewriting this to `NOT EXISTS` or filtering `WHERE s.playlist_id IS NOT NULL` will fix the bug.

---

## 7. Data Loading & Integrity Verification

### 7.1 Loading Script (`sql/02_load_data.sql`)
The database was populated using PostgreSQL's high-speed streaming `\copy` command in strict topological foreign-key order:
1. `artists` (3,000 rows)
2. `albums` (12,000 rows)
3. `users` (30,000 rows)
4. `tracks` (67,808 rows)
5. `track_artists` (77,489 rows)
6. `playlists` (10,000 rows)
7. `playlist_tracks` (120,004 rows)
8. `streams` (250,000 rows)
9. `liked_tracks` (58,533 rows)
10. `artist_follows` (69,901 rows)
Followed by `ANALYZE;` to construct planner query cost statistics.

### 7.2 Row Count Verification
Every table was audited against the faculty seed specification:

```sql
SET search_path TO spotify;
SELECT 'artists' AS tbl, count(*) AS loaded, 3000 AS expected FROM artists
UNION ALL SELECT 'albums', count(*), 12000 FROM albums
UNION ALL SELECT 'users', count(*), 30000 FROM users
UNION ALL SELECT 'tracks', count(*), 67808 FROM tracks
UNION ALL SELECT 'track_artists', count(*), 77489 FROM track_artists
UNION ALL SELECT 'playlists', count(*), 10000 FROM playlists
UNION ALL SELECT 'playlist_tracks', count(*), 120004 FROM playlist_tracks
UNION ALL SELECT 'streams', count(*), 250000 FROM streams
UNION ALL SELECT 'liked_tracks', count(*), 58533 FROM liked_tracks
UNION ALL SELECT 'artist_follows', count(*), 69901 FROM artist_follows;
```

**Output:**
```
       tbl       | loaded | expected 
-----------------+--------+----------
 artists         |   3000 |     3000
 albums          |  12000 |    12000
 users           |  30000 |    30000
 tracks          |  67808 |    67808
 track_artists   |  77489 |    77489
 playlists       |  10000 |    10000
 playlist_tracks | 120004 |   120004
 streams         | 250000 |   250000
 liked_tracks    |  58533 |    58533
 artist_follows  |  69901 |    69901
(10 rows)
```
*Result: 100% match across all 10 tables with 0 rejected rows.*

### 7.3 Integrity Check Queries & Execution Results

To guarantee physical consistency, four business integrity audits were executed:

#### Integrity Check 1: Album Release Date vs Stream Timestamp
*Hypothesis:* No listener streamed a track before its album was commercially released.
```sql
SELECT count(*) AS violations_streams_before_album_release
FROM streams s
JOIN tracks t ON t.track_id = s.track_id
JOIN albums a ON a.album_id = t.album_id
WHERE s.started_at::date < a.release_date;
```
**Result:**
```
 violations_streams_before_album_release 
-----------------------------------------
                                       0
(1 row)
```

#### Integrity Check 2: Playback Duration vs Track Length
*Hypothesis:* A playback event (`ms_played`) can never exceed the total recording length (`duration_ms`).
```sql
SELECT count(*) AS violations_stream_longer_than_track
FROM streams s
JOIN tracks t ON t.track_id = s.track_id
WHERE s.ms_played > t.duration_ms;
```
**Result:**
```
 violations_stream_longer_than_track 
-------------------------------------
                                   0
(1 row)
```

#### Integrity Check 3: Catalog Primary Artist Cardinality
*Hypothesis:* Every single track in the catalog must have exactly one artist credited with the `PRIMARY` role in `track_artists`.
```sql
SELECT count(*) AS tracks_without_exactly_one_primary
FROM (
    SELECT t.track_id, count(*) FILTER (WHERE ta.role = 'PRIMARY') AS primary_count
    FROM tracks t
    LEFT JOIN track_artists ta ON ta.track_id = t.track_id
    GROUP BY t.track_id
    HAVING count(*) FILTER (WHERE ta.role = 'PRIMARY') <> 1
) sub;
```
**Result:**
```
 tracks_without_exactly_one_primary 
------------------------------------
                                  0
(1 row)
```

#### Integrity Check 4: Chronological Sequence Integrity
*Hypothesis:* No track was added to a playlist before the playlist was created.
```sql
SELECT count(*) AS violations_added_before_playlist_created
FROM playlist_tracks pt
JOIN playlists p ON p.playlist_id = pt.playlist_id
WHERE pt.added_at < p.created_at;
```
**Result:**
```
 violations_added_before_playlist_created 
------------------------------------------
                                        0
(1 row)
```

---

## 8. Conclusion

Phase 2 successfully delivered an enterprise-grade, BCNF-compliant PostgreSQL schema that loads all 698,735 seed records with zero constraint violations. All 30 workload queries from `queries/workload_30.sql` run cleanly against this foundation, providing an authentic, un-tuned baseline for Phase 3 benchmarking.
