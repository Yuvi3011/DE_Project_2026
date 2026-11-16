-- =====================================================================
-- Spotify Music Streaming Database: Data Loading Script
-- Phase 2: sql/02_load_data.sql
--
-- Loads all 10 CSV data files into the 'spotify' schema in dependency order.
-- =====================================================================

SET search_path TO spotify;

\echo 'Loading artists...'
\copy artists FROM 'seed_data/artists.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading albums...'
\copy albums FROM 'seed_data/albums.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading users...'
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading tracks...'
\copy tracks FROM 'seed_data/tracks.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading track_artists...'
\copy track_artists FROM 'seed_data/track_artists.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading playlists...'
\copy playlists FROM 'seed_data/playlists.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading playlist_tracks...'
\copy playlist_tracks FROM 'seed_data/playlist_tracks.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading streams...'
\copy streams FROM 'seed_data/streams.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading liked_tracks...'
\copy liked_tracks FROM 'seed_data/liked_tracks.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading artist_follows...'
\copy artist_follows FROM 'seed_data/artist_follows.csv' WITH (FORMAT csv, HEADER true);

\echo 'Running ANALYZE to update statistics...'
ANALYZE;

\echo 'Data load complete.'
