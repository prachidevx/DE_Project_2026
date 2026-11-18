-- =====================================================================
-- CP3: Query Optimization - Indexes
-- File: sql/05_indexes.sql
-- Beginner-friendly, thoroughly explained implementation.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

-- ---------------------------------------------------------------------
-- Extension: pg_trgm (PostgreSQL Trigram Search)
-- ---------------------------------------------------------------------
-- Why it is needed:
-- Query R03 searches for place names containing 'biryani' using ILIKE '%biryani%'.
-- A standard B-tree index only works when matching from the beginning (e.g. 'biryani%').
-- The pg_trgm extension breaks text into 3-letter pieces (trigrams), allowing
-- PostgreSQL to search for words anywhere inside a text string using a GIN index.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA gmaps;


-- =====================================================================
-- 1. Indexes on the "places" table
-- =====================================================================

-- [Index 1] Serves Query R01: "Restaurants near me" (Koramangala Bounding Box)
-- What it does:
--   Filters by category_id = 1 (Restaurants) and coordinates within a box.
-- Why B-tree:
--   B-tree supports both exact equality (=) and range queries (BETWEEN).
-- Why this column order:
--   Rule: Equality columns first (category_id), then Range columns (latitude, longitude).
--   This lets the database jump straight to category 1, then scan only the narrow box.
-- Why Partial (WHERE NOT is_permanently_closed):
--   We only care about open places. Excluding closed places saves memory and disk space.
-- Why INCLUDE (name, avg_rating):
--   Stores these columns in the index leaves so the database gets all needed data
--   directly from the index without having to visit the main table (Index Only Scan).
CREATE INDEX IF NOT EXISTS idx_places_r01
    ON places (category_id, latitude, longitude)
    INCLUDE (name, avg_rating)
    WHERE NOT is_permanently_closed;


-- [Index 2] Serves Query R03: Search places with "biryani" in the name
-- What it does:
--   Finds places where name ILIKE '%biryani%'.
-- Why GIN with gin_trgm_ops:
--   GIN (Generalized Inverted Index) stores every 3-letter combination in place names.
--   When searching for 'biryani', PostgreSQL looks up the trigrams ('bir', 'iry', 'rya'...)
--   and immediately finds matching rows without scanning all 40,000 places.
CREATE INDEX IF NOT EXISTS idx_places_name_trgm
    ON places USING gin (name gin_trgm_ops);


-- [Index 3] Serves Query R04: "Open now" late-night Saturday restaurants
-- What it does:
--   Finds open restaurants in Bengaluru (city_id = 1, category_id = 1) sorted by rating.
-- Why this column order:
--   city_id and category_id are equality filters (=), followed by avg_rating DESC
--   so rows are already sorted by rating, avoiding a separate Sort step before LIMIT 30.
CREATE INDEX IF NOT EXISTS idx_places_city_cat_rating
    ON places (city_id, category_id, avg_rating DESC NULLS LAST)
    INCLUDE (name)
    WHERE NOT is_permanently_closed;


-- [Index 4] Serves Queries R12 and R19: City-level place lookups
-- What it does:
--   Quickly finds all places in a specific city (e.g. city_id = 2 for Mumbai in R12).
-- Why covering with INCLUDE (name):
--   Contains city_id, place_id, and name, enabling an Index Only Scan when joining.
CREATE INDEX IF NOT EXISTS idx_places_city_place
    ON places (city_id, place_id)
    INCLUDE (name);


-- [Index 5] Serves Query R16: Data quality check for closed places
-- What it does:
--   Finds permanently closed places that still received navigation trips in 2026.
-- Why a partial index:
--   Only a tiny fraction of places are closed. Indexing only closed places makes
--   this index tiny (only ~72 kB) and super fast.
CREATE INDEX IF NOT EXISTS idx_places_closed
    ON places (place_id, name)
    WHERE is_permanently_closed;


-- [Index 6] Serves Query R21: Places category anti-join
-- What it does:
--   Finds places without opening hours and groups them by category.
-- Why composite on (place_id, category_id):
--   Allows PostgreSQL to quickly check place_id and retrieve its category_id in one go.
CREATE INDEX IF NOT EXISTS idx_places_place_cat
    ON places (place_id, category_id);


-- =====================================================================
-- 2. Indexes on the "opening_hours" table
-- =====================================================================

-- [Index 8] Serves Query R04: Saturday operating hours lookup
-- What it does:
--   Finds operating hours for Saturday (weekday = 6) and joins on place_id.
-- Why composite covering index:
--   Filters by weekday first, then joins place_id, and includes opens/closes times.
--   PostgreSQL performs an Index Only Scan and never touches the 252,000-row table heap.
CREATE INDEX IF NOT EXISTS idx_opening_hours_weekday
    ON opening_hours (weekday, place_id)
    INCLUDE (opens, closes);


-- =====================================================================
-- 3. Indexes on the "place_reviews" table
-- =====================================================================

-- [Index 9] Serves Query R05: Place page newest 10 reviews
-- What it does:
--   Retrieves the 10 newest reviews for place 18.
-- Why (place_id, created_at DESC):
--   Filters to place 18 and provides reviews pre-sorted from newest to oldest.
--   PostgreSQL simply reads the first 10 entries and stops (no memory sort needed).
CREATE INDEX IF NOT EXISTS idx_place_reviews_place_created
    ON place_reviews (place_id, created_at DESC);


-- [Index 10] Serves Query R14: Local Guides leaderboard in 2026
-- What it does:
--   Finds reviews written in 2026 (created_at >= '2026-01-01') and counts them per user.
-- Why covering index:
--   Contains created_at, user_id, and photo_count so the database reads only the index.
CREATE INDEX IF NOT EXISTS idx_reviews_created_user
    ON place_reviews (created_at, user_id)
    INCLUDE (photo_count);


-- [Index 11] Serves Queries R15 and W04: Review rating aggregation
-- What it does:
--   Calculates average rating and review count per place to check for data mismatch.
-- Why on (place_id) INCLUDE (rating):
--   Enables a streaming index-only scan ordered by place_id, speeding up both R15 and W04.
CREATE INDEX IF NOT EXISTS idx_place_reviews_place_rating
    ON place_reviews (place_id)
    INCLUDE (rating);


-- [Index 12] Serves Query R22: Review moderation deep pagination (OFFSET 50000)
-- What it does:
--   Retrieves page 2,001 of reviews ordered by created_at DESC.
-- Why covering on created_at DESC:
--   Without an index, PostgreSQL must sort all 90,000 reviews in memory.
--   With this index, it walks directly through the index to row 50,000 in ~3 ms.
CREATE INDEX IF NOT EXISTS idx_reviews_created_covering
    ON place_reviews (created_at DESC)
    INCLUDE (review_id, place_id, user_id, rating);


-- =====================================================================
-- 4. Indexes on the "saved_places" table
-- =====================================================================

-- [Index 13] Serves Query R06: "Saved" tab grouped by list
-- What it does:
--   Shows user 1005's saved places ordered by list_name, then newest saved_at first.
-- Why (user_id, list_name, saved_at DESC):
--   Matches the exact WHERE clause (user_id = 1005) and ORDER BY clause.
--   Result is retrieved in index order with zero in-memory sorting.
CREATE INDEX IF NOT EXISTS idx_saved_places_user_list_saved
    ON saved_places (user_id, list_name, saved_at DESC)
    INCLUDE (place_id);


-- =====================================================================
-- 5. Indexes on "traffic_readings" and "road_segments" tables
-- =====================================================================

-- [Index 14] Serves Queries R07 and R09: Segment traffic history & live readings
-- What it does:
--   Retrieves the latest reading per segment (R07) or 24-hour speeds on segment 5 (R09).
-- Why (segment_id, recorded_at DESC):
--   Groups readings by segment and puts the newest readings first.
CREATE INDEX IF NOT EXISTS idx_traffic_readings_segment_recorded
    ON traffic_readings (segment_id, recorded_at DESC)
    INCLUDE (avg_speed_kmph, congestion_level);


-- [Index 15] Serves Query R08: Real-time traffic alerts for heavy traffic
-- What it does:
--   Finds recent traffic readings that are 'HEAVY' or 'STANDSTILL'.
-- Why partial index:
--   Only a small fraction of readings represent severe traffic. We ignore 'LOW' and
--   'MODERATE' readings, cutting the search from 250,000 rows to just 23 rows.
CREATE INDEX IF NOT EXISTS idx_traffic_heavy
    ON traffic_readings (recorded_at DESC, segment_id)
    INCLUDE (avg_speed_kmph, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');


-- [Index 16] Serves Query R07: Road segment name filtering by city
-- What it does:
--   Finds Outer Ring Road segments in Bengaluru (city_id = 1).
CREATE INDEX IF NOT EXISTS idx_road_segments_city_road
    ON road_segments (city_id, road_name)
    INCLUDE (segment_id);


-- =====================================================================
-- 6. Indexes on the "incident_reports" table
-- =====================================================================

-- [Index 17] Serves Query R10: Incidents reported on a specific date
-- What it does:
--   Quickly finds incidents reported on 2026-06-30 sorted by newest first.
CREATE INDEX IF NOT EXISTS idx_incident_reported_at
    ON incident_reports (reported_at DESC, segment_id);


-- =====================================================================
-- 7. Indexes on the "navigation_sessions" table
-- =====================================================================

-- [Index 19] Serves Query R11: Completed navigation sessions analysis
-- What it does:
--   Calculates average ETA error for completed trips in 2026 grouped by travel mode.
-- Why partial index:
--   Indexes only rows WHERE status = 'COMPLETED', skipping cancelled and in-progress trips.
CREATE INDEX IF NOT EXISTS idx_nav_completed_started
    ON navigation_sessions (started_at, travel_mode)
    INCLUDE (actual_minutes, eta_minutes)
    WHERE status = 'COMPLETED';


-- [Index 20] Serves Queries R12, R16, R19, R20: Destination and date filtering
-- What it does:
--   Quickly filters navigation sessions by start time and destination place.
CREATE INDEX IF NOT EXISTS idx_nav_started_dest
    ON navigation_sessions (started_at, dest_place_id);


-- [Index 21] Serves Query R13: Places never used as origin (Fixes Problem P6)
-- What it does:
--   Indexes non-null origin_place_id values.
-- Why partial (WHERE origin_place_id IS NOT NULL):
--   Trips starting from GPS coordinates have origin_place_id = NULL.
--   Excluding NULLs enables a fast Merge Anti Join and resolves the SQL NOT IN NULL bug.
CREATE INDEX IF NOT EXISTS idx_nav_origin_place
    ON navigation_sessions (origin_place_id)
    WHERE origin_place_id IS NOT NULL;



-- [Index 23] Serves Query R18: Share of cancelled navigations
-- What it does:
--   Counts total sessions and cancelled sessions grouped by travel_mode.
-- Why covering on (travel_mode, status):
--   Contains both columns needed by the query, allowing a Parallel Index Only Scan.
CREATE INDEX IF NOT EXISTS idx_nav_mode_status
    ON navigation_sessions (travel_mode, status);


-- Remove candidate indexes that were not selected
-- by PostgreSQL in any of the 30 optimized query plans.

DROP INDEX IF EXISTS gmaps.idx_places_name_id;
DROP INDEX IF EXISTS gmaps.idx_incident_expires_at;
DROP INDEX IF EXISTS gmaps.idx_nav_dest_rerouted;
DROP INDEX IF EXISTS gmaps.idx_nav_dest_started;

-- Refresh optimizer statistics.
ANALYZE;

-- Update optimizer statistics so PostgreSQL knows about all new indexes
ANALYZE;
