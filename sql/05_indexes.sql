-- =====================================================================
-- CP3: Database Optimization Indexes
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

-- Extension for substring searching (ILIKE '%...%')
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA gmaps;


-- ---------------------------------------------------------------------
-- 1. Table: places
-- ---------------------------------------------------------------------

-- Serves: R01
-- Type: Partial B-tree covering index
-- Column order: category_id (equality) then latitude, longitude (bounding box range).
CREATE INDEX IF NOT EXISTS idx_places_r01
    ON places (category_id, latitude, longitude)
    INCLUDE (name, avg_rating)
    WHERE NOT is_permanently_closed;

-- Serves: R03
-- Type: GIN index with gin_trgm_ops
-- Column order: name (trigrams allow substring search with leading wildcard).
CREATE INDEX IF NOT EXISTS idx_places_name_trgm
    ON places USING gin (name gin_trgm_ops);

-- Serves: R04
-- Type: Partial B-tree covering index
-- Column order: city_id, category_id (equality), then avg_rating DESC (pre-sorted).
CREATE INDEX IF NOT EXISTS idx_places_city_cat_rating
    ON places (city_id, category_id, avg_rating DESC NULLS LAST)
    INCLUDE (name)
    WHERE NOT is_permanently_closed;

-- Serves: R12, R19, R24
-- Type: B-tree covering index
-- Column order: city_id (equality filter), place_id (join key).
CREATE INDEX IF NOT EXISTS idx_places_city_place
    ON places (city_id, place_id)
    INCLUDE (name);

-- Serves: R16
-- Type: Partial B-tree index
-- Column order: place_id, name for permanently closed venues.
CREATE INDEX IF NOT EXISTS idx_places_closed
    ON places (place_id, name)
    WHERE is_permanently_closed;

-- Serves: R02, R06, R21
-- Type: Composite B-tree index
-- Column order: place_id (join key), category_id (filtering/grouping).
CREATE INDEX IF NOT EXISTS idx_places_place_cat
    ON places (place_id, category_id);


-- ---------------------------------------------------------------------
-- 2. Table: opening_hours
-- ---------------------------------------------------------------------

-- Serves: R02, R04
-- Type: Composite B-tree covering index
-- Column order: weekday (equality filter), place_id (join key).
CREATE INDEX IF NOT EXISTS idx_opening_hours_weekday
    ON opening_hours (weekday, place_id)
    INCLUDE (opens, closes);


-- ---------------------------------------------------------------------
-- 3. Table: place_reviews
-- ---------------------------------------------------------------------

-- Serves: R05
-- Type: Composite B-tree index
-- Column order: place_id (equality), created_at DESC (pre-sorted newest first).
CREATE INDEX IF NOT EXISTS idx_place_reviews_place_created
    ON place_reviews (place_id, created_at DESC);

-- Serves: R14
-- Type: Composite B-tree covering index
-- Column order: created_at (range filter), user_id (grouping).
CREATE INDEX IF NOT EXISTS idx_reviews_created_user
    ON place_reviews (created_at, user_id)
    INCLUDE (photo_count);

-- Serves: R15, W04
-- Type: B-tree covering index
-- Column order: place_id (join/group key), includes rating for aggregate calculation.
CREATE INDEX IF NOT EXISTS idx_place_reviews_place_rating
    ON place_reviews (place_id)
    INCLUDE (rating);

-- Serves: R22
-- Type: B-tree covering index
-- Column order: created_at DESC (avoids in-memory sorting for deep pagination).
CREATE INDEX IF NOT EXISTS idx_reviews_created_covering
    ON place_reviews (created_at DESC)
    INCLUDE (review_id, place_id, user_id, rating);


-- ---------------------------------------------------------------------
-- 4. Table: saved_places
-- ---------------------------------------------------------------------

-- Serves: R06
-- Type: Composite B-tree covering index
-- Column order: user_id (equality), list_name, saved_at DESC (matches ORDER BY).
CREATE INDEX IF NOT EXISTS idx_saved_places_user_list_saved
    ON saved_places (user_id, list_name, saved_at DESC)
    INCLUDE (place_id);


-- ---------------------------------------------------------------------
-- 5. Table: traffic_readings & road_segments
-- ---------------------------------------------------------------------

-- Serves: R07, R09
-- Type: Composite B-tree covering index
-- Column order: segment_id (equality/DISTINCT ON), recorded_at DESC (latest reading first).
CREATE INDEX IF NOT EXISTS idx_traffic_readings_segment_recorded
    ON traffic_readings (segment_id, recorded_at DESC)
    INCLUDE (avg_speed_kmph, congestion_level);

-- Serves: R08
-- Type: Partial B-tree covering index
-- Column order: recorded_at DESC, segment_id for heavy traffic only.
CREATE INDEX IF NOT EXISTS idx_traffic_heavy
    ON traffic_readings (recorded_at DESC, segment_id)
    INCLUDE (avg_speed_kmph, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');

-- Serves: R07, R08, R10
-- Type: Composite B-tree covering index
-- Column order: city_id (equality filter), road_name (prefix filter).
CREATE INDEX IF NOT EXISTS idx_road_segments_city_road
    ON road_segments (city_id, road_name)
    INCLUDE (segment_id);


-- ---------------------------------------------------------------------
-- 6. Table: incident_reports
-- ---------------------------------------------------------------------

-- Serves: R10
-- Type: Composite B-tree index
-- Column order: reported_at DESC (range filter and sort), segment_id (join key).
CREATE INDEX IF NOT EXISTS idx_incident_reported_at
    ON incident_reports (reported_at DESC, segment_id);


-- ---------------------------------------------------------------------
-- 7. Table: navigation_sessions
-- ---------------------------------------------------------------------

-- Serves: R11
-- Type: Partial B-tree covering index
-- Column order: started_at (range filter), travel_mode (grouping) for completed trips.
CREATE INDEX IF NOT EXISTS idx_nav_completed_started
    ON navigation_sessions (started_at, travel_mode)
    INCLUDE (actual_minutes, eta_minutes)
    WHERE status = 'COMPLETED';

-- Serves: R12, R16, R20
-- Type: Composite B-tree index
-- Column order: started_at (date range filter), dest_place_id (join/group key).
CREATE INDEX IF NOT EXISTS idx_nav_started_dest
    ON navigation_sessions (started_at, dest_place_id);

-- Serves: R13
-- Type: Partial B-tree index
-- Column order: origin_place_id (anti-join for non-null starting places).
CREATE INDEX IF NOT EXISTS idx_nav_origin_place
    ON navigation_sessions (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

-- Serves: R18
-- Type: Composite B-tree covering index
-- Column order: travel_mode, status (enables parallel index-only aggregation).
CREATE INDEX IF NOT EXISTS idx_nav_mode_status
    ON navigation_sessions (travel_mode, status);


-- ---------------------------------------------------------------------
-- Statistics
-- ---------------------------------------------------------------------
ANALYZE;
