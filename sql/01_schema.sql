-- =====================================================================
-- Spotify Music Streaming Database: Schema Definition
-- Phase 2: sql/01_schema.sql
--
-- Rules:
--  * Schema: spotify
--  * Contains ONLY primary keys, foreign keys, unique constraints,
--    not-null constraints, and check constraints (no secondary tuning indexes).
--  * Satisfies 3NF/BCNF requirements and passes all seed data loads cleanly.
-- =====================================================================

DROP SCHEMA IF EXISTS spotify CASCADE;
CREATE SCHEMA spotify;
SET search_path TO spotify;

-- ---------------------------------------------------------------------
-- 1. artists: Artists and bands publishing music on the platform
-- ---------------------------------------------------------------------
CREATE TABLE artists (
    artist_id           INTEGER,
    artist_name         VARCHAR(255)                NOT NULL,
    country_code        CHAR(2)                     NOT NULL,
    primary_genre       VARCHAR(50)                 NOT NULL,
    is_verified         BOOLEAN                     NOT NULL DEFAULT FALSE,
    monthly_listeners   INTEGER                     NOT NULL DEFAULT 0,
    created_at          TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_artists PRIMARY KEY (artist_id),
    CONSTRAINT chk_artists_monthly_listeners CHECK (monthly_listeners >= 0),
    CONSTRAINT chk_artists_country_code CHECK (country_code ~ '^[A-Z]{2}$')
);

-- ---------------------------------------------------------------------
-- 2. albums: Musical releases (Albums, EPs, Singles, Compilations)
-- ---------------------------------------------------------------------
CREATE TABLE albums (
    album_id            INTEGER,
    artist_id           INTEGER                     NOT NULL,
    album_title         VARCHAR(255)                NOT NULL,
    album_type          VARCHAR(20)                 NOT NULL,
    release_date        DATE                        NOT NULL,
    label               VARCHAR(100)                NOT NULL,
    upc                 CHAR(12)                    NOT NULL,
    CONSTRAINT pk_albums PRIMARY KEY (album_id),
    CONSTRAINT fk_albums_artist FOREIGN KEY (artist_id)
        REFERENCES artists(artist_id) ON DELETE RESTRICT,
    CONSTRAINT uq_albums_upc UNIQUE (upc),
    CONSTRAINT chk_albums_album_type CHECK (album_type IN ('ALBUM', 'SINGLE', 'EP', 'COMPILATION')),
    CONSTRAINT chk_albums_upc_format CHECK (upc ~ '^[0-9]{12}$')
);

-- ---------------------------------------------------------------------
-- 3. users: Listeners and playlist curators
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id             INTEGER,
    email               VARCHAR(255)                NOT NULL,
    display_name        VARCHAR(100)                NOT NULL,
    country_code        CHAR(2)                     NOT NULL,
    birth_date          DATE                        NOT NULL,
    subscription        VARCHAR(20)                 NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_users_country_code CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT chk_users_subscription CHECK (subscription IN ('FREE', 'PREMIUM', 'DUO', 'FAMILY', 'STUDENT')),
    CONSTRAINT chk_users_birth_date CHECK (birth_date >= '1900-01-01' AND birth_date <= CURRENT_DATE)
);

-- ---------------------------------------------------------------------
-- 4. tracks: Individual audio recordings included on albums
-- ---------------------------------------------------------------------
CREATE TABLE tracks (
    track_id            INTEGER,
    album_id            INTEGER                     NOT NULL,
    disc_no             SMALLINT                    NOT NULL DEFAULT 1,
    track_no            SMALLINT                    NOT NULL,
    title               VARCHAR(255)                NOT NULL,
    duration_ms         INTEGER                     NOT NULL,
    explicit            BOOLEAN                     NOT NULL DEFAULT FALSE,
    isrc                CHAR(12)                    NOT NULL,
    popularity          SMALLINT                    NOT NULL DEFAULT 0,
    CONSTRAINT pk_tracks PRIMARY KEY (track_id),
    CONSTRAINT fk_tracks_album FOREIGN KEY (album_id)
        REFERENCES albums(album_id) ON DELETE CASCADE,
    CONSTRAINT uq_tracks_isrc UNIQUE (isrc),
    CONSTRAINT uq_tracks_album_disc_track UNIQUE (album_id, disc_no, track_no),
    CONSTRAINT chk_tracks_disc_no CHECK (disc_no > 0),
    CONSTRAINT chk_tracks_track_no CHECK (track_no > 0),
    CONSTRAINT chk_tracks_duration_ms CHECK (duration_ms > 0),
    CONSTRAINT chk_tracks_isrc_format CHECK (isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$'),
    CONSTRAINT chk_tracks_popularity CHECK (popularity >= 0 AND popularity <= 100)
);

-- ---------------------------------------------------------------------
-- 5. track_artists: Many-to-many relationship mapping artists to tracks
-- ---------------------------------------------------------------------
CREATE TABLE track_artists (
    track_id            INTEGER                     NOT NULL,
    artist_id           INTEGER                     NOT NULL,
    role                VARCHAR(10)                 NOT NULL,
    CONSTRAINT pk_track_artists PRIMARY KEY (track_id, artist_id),
    CONSTRAINT fk_track_artists_track FOREIGN KEY (track_id)
        REFERENCES tracks(track_id) ON DELETE CASCADE,
    CONSTRAINT fk_track_artists_artist FOREIGN KEY (artist_id)
        REFERENCES artists(artist_id) ON DELETE RESTRICT,
    CONSTRAINT chk_track_artists_role CHECK (role IN ('PRIMARY', 'FEATURED'))
);

-- ---------------------------------------------------------------------
-- 6. playlists: User-curated playlists
-- ---------------------------------------------------------------------
CREATE TABLE playlists (
    playlist_id         INTEGER,
    owner_user_id       INTEGER                     NOT NULL,
    name                VARCHAR(255)                NOT NULL,
    is_public           BOOLEAN                     NOT NULL DEFAULT TRUE,
    is_collaborative    BOOLEAN                     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_playlists PRIMARY KEY (playlist_id),
    CONSTRAINT fk_playlists_owner FOREIGN KEY (owner_user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_playlists_collab_not_public CHECK (NOT (is_public AND is_collaborative))
);

-- ---------------------------------------------------------------------
-- 7. playlist_tracks: Ordered entries of tracks in playlists
-- ---------------------------------------------------------------------
CREATE TABLE playlist_tracks (
    playlist_id         INTEGER                     NOT NULL,
    position            INTEGER                     NOT NULL,
    track_id            INTEGER                     NOT NULL,
    added_by_user_id    INTEGER                     NOT NULL,
    added_at            TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_playlist_tracks PRIMARY KEY (playlist_id, position),
    CONSTRAINT fk_playlist_tracks_playlist FOREIGN KEY (playlist_id)
        REFERENCES playlists(playlist_id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_tracks_track FOREIGN KEY (track_id)
        REFERENCES tracks(track_id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_tracks_added_by FOREIGN KEY (added_by_user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_playlist_tracks_position CHECK (position >= 1)
);

-- ---------------------------------------------------------------------
-- 8. streams: Playback logs for royalty, telemetry, and personalization
-- ---------------------------------------------------------------------
CREATE TABLE streams (
    stream_id           BIGINT,
    user_id             INTEGER                     NOT NULL,
    track_id            INTEGER                     NOT NULL,
    started_at          TIMESTAMP WITH TIME ZONE    NOT NULL,
    ms_played           INTEGER                     NOT NULL,
    platform            VARCHAR(20)                 NOT NULL,
    source_type         VARCHAR(20)                 NOT NULL,
    playlist_id         INTEGER,
    skipped             BOOLEAN                     NOT NULL DEFAULT FALSE,
    offline             BOOLEAN                     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_streams PRIMARY KEY (stream_id),
    CONSTRAINT fk_streams_user FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_streams_track FOREIGN KEY (track_id)
        REFERENCES tracks(track_id) ON DELETE RESTRICT,
    CONSTRAINT fk_streams_playlist FOREIGN KEY (playlist_id)
        REFERENCES playlists(playlist_id) ON DELETE SET NULL,
    CONSTRAINT chk_streams_ms_played CHECK (ms_played >= 0),
    CONSTRAINT chk_streams_platform CHECK (platform IN ('ANDROID', 'IOS', 'DESKTOP', 'WEB', 'SPEAKER', 'CAR')),
    CONSTRAINT chk_streams_source_type CHECK (source_type IN ('PLAYLIST', 'ALBUM', 'ARTIST', 'RADIO', 'SEARCH')),
    CONSTRAINT chk_streams_playlist_source CHECK (
        (source_type = 'PLAYLIST' AND playlist_id IS NOT NULL) OR
        (source_type <> 'PLAYLIST' AND playlist_id IS NULL)
    ),
    CONSTRAINT chk_streams_skipped CHECK (NOT skipped OR ms_played < 30000)
);

-- ---------------------------------------------------------------------
-- 9. liked_tracks: User "Liked Songs" library collection
-- ---------------------------------------------------------------------
CREATE TABLE liked_tracks (
    user_id             INTEGER                     NOT NULL,
    track_id            INTEGER                     NOT NULL,
    liked_at            TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_liked_tracks PRIMARY KEY (user_id, track_id),
    CONSTRAINT fk_liked_tracks_user FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_liked_tracks_track FOREIGN KEY (track_id)
        REFERENCES tracks(track_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 10. artist_follows: Users following artists
-- ---------------------------------------------------------------------
CREATE TABLE artist_follows (
    user_id             INTEGER                     NOT NULL,
    artist_id           INTEGER                     NOT NULL,
    followed_at         TIMESTAMP WITH TIME ZONE    NOT NULL,
    CONSTRAINT pk_artist_follows PRIMARY KEY (user_id, artist_id),
    CONSTRAINT fk_artist_follows_user FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_artist_follows_artist FOREIGN KEY (artist_id)
        REFERENCES artists(artist_id) ON DELETE CASCADE
);
