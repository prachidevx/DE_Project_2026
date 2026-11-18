-- =====================================================================
-- Google Maps DBMS Project: CP3 Optimized Workload Queries
-- File: sql/06_optimized_queries.sql
--
-- First-Year Student Guide:
--   * Every query below runs the exact same workload as CP2.
--   * Most queries (24 of 30) use the original SQL text and run fast
--     because of the indexes we added in sql/05_indexes.sql.
--   * 6 queries were rewritten to fix performance or logic issues:
--       - R10: Rewrote DATE(reported_at) to a date range (sargable).
--       - R11: Rewrote EXTRACT(YEAR FROM started_at) to a date range.
--       - R13: Replaced NOT IN with NOT EXISTS to fix the NULL bug (P6).
--       - R14: Grouped reviews first before looking up user names.
--       - R19: Replaced two 26-second correlated subqueries with one LEFT JOIN.
--       - R20: Rewrote started_at::date BETWEEN to a clean timestamp range.
--   * All other queries have identical logic and result sets.
-- =====================================================================
SET search_path TO gmaps;
BEGIN;

-- @R01
-- "Restaurants near me": open restaurants within ~1 km of Koramangala (12.9352, 77.6245), nearest first
-- How it works:
--   Filters by category_id = 1 (Restaurant) and latitude/longitude bounding box.
-- How it was optimized:
--   Accelerated by index idx_places_r01 on (category_id, latitude, longitude) WHERE NOT is_permanently_closed.
--   PostgreSQL scans only the matching restaurants in the box instead of scanning all 40,000 places.
SELECT place_id, name, avg_rating,
       round((6371 * acos(least(1, cos(radians(12.9352)) * cos(radians(latitude)) * cos(radians(longitude) - radians(77.6245))
                                  + sin(radians(12.9352)) * sin(radians(latitude)))))::numeric, 3) AS km
FROM places
WHERE category_id = 1
  AND NOT is_permanently_closed
  AND latitude  BETWEEN 12.9352 - 0.009 AND 12.9352 + 0.009
  AND longitude BETWEEN 77.6245 - 0.0093 AND 77.6245 + 0.0093
ORDER BY km
LIMIT 20;

-- @R02
-- Place page: details of place 18 with Tuesday's opening hours
-- How it works:
--   Looks up place 18 using its primary key and gets Tuesday's hours (weekday = 2).
-- How it was optimized:
--   Already runs in <0.2 ms using primary key indexes on places and opening_hours.
SELECT p.place_id, p.name, p.address, p.phone, p.avg_rating, p.review_count, h.opens, h.closes
FROM places p
LEFT JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 2
WHERE p.place_id = 18;

-- @R03
-- Search: Bengaluru places with "biryani" in the name, best rated first
-- How it works:
--   Finds places in Bengaluru (city_id = 1) where name contains "biryani" (case-insensitive).
-- How it was optimized:
--   Standard B-tree indexes cannot search '%biryani%' because of the leading '%'.
--   Accelerated by GIN trigram index idx_places_name_trgm using pg_trgm.
--   PostgreSQL looks up 3-letter tokens and finds matching rows in 1 ms (down from 27 ms).
SELECT place_id, name, avg_rating, review_count
FROM places
WHERE city_id = 1 AND name ILIKE '%biryani%'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 20;

-- @R04
-- "Open now" filter: Bengaluru restaurants open at 23:30 on a Saturday (some close after midnight)
-- How it works:
--   Finds restaurants open at 11:30 PM on Saturday, handling venues closing after midnight.
-- How it was optimized:
--   Accelerated by idx_places_city_cat_rating on places and idx_opening_hours_weekday on opening_hours.
--   PostgreSQL matches open places via an Index Only Scan without reading the 252,000 table rows.
SELECT p.place_id, p.name, h.opens, h.closes
FROM places p
JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 6
WHERE p.city_id = 1 AND p.category_id = 1 AND NOT p.is_permanently_closed
  AND (   (h.opens < h.closes AND TIME '23:30' BETWEEN h.opens AND h.closes)
       OR (h.opens > h.closes AND (TIME '23:30' >= h.opens OR TIME '23:30' < h.closes)))
ORDER BY p.avg_rating DESC NULLS LAST
LIMIT 30;

-- @R05
-- Place page: the 10 newest reviews of place 18
-- How it works:
--   Finds the newest 10 reviews for place 18 and shows author details.
-- How it was optimized:
--   Accelerated by composite index idx_place_reviews_place_created on (place_id, created_at DESC).
--   The database retrieves the 10 newest reviews directly in sorted order with no in-memory sorting.
SELECT r.review_id, u.display_name, u.is_local_guide, r.rating, r.review_text, r.photo_count, r.created_at
FROM place_reviews r
JOIN users u ON u.user_id = r.user_id
WHERE r.place_id = 18
ORDER BY r.created_at DESC
LIMIT 10;

-- @R06
-- "Saved" tab: user 1005's saved places grouped by list
-- How it works:
--   Shows all places saved by user 1005 ordered by list_name, then newest saved_at first.
-- How it was optimized:
--   Accelerated by covering index idx_saved_places_user_list_saved on (user_id, list_name, saved_at DESC).
--   Retrieves the saved places in sorted order directly from the index.
SELECT s.list_name, p.place_id, p.name, s.saved_at
FROM saved_places s
JOIN places p ON p.place_id = s.place_id
WHERE s.user_id = 1005
ORDER BY s.list_name, s.saved_at DESC;

-- @R07
-- Live traffic layer: the latest reading of every Outer Ring Road segment in Bengaluru
-- How it works:
--   Uses DISTINCT ON (segment_id) to pick the single newest traffic reading per segment.
-- How it was optimized:
--   Accelerated by idx_road_segments_city_road and idx_traffic_readings_segment_recorded.
--   Both tables are scanned via Index Only Scans, reducing time from 17.8 ms to 2.5 ms.
SELECT DISTINCT ON (t.segment_id) t.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1 AND s.road_name LIKE 'Outer Ring Road%'
ORDER BY t.segment_id, t.recorded_at DESC;

-- @R08
-- Traffic alerts: Bengaluru segments with heavy traffic or standstill since 18:00 on 30 June 2026
-- How it works:
--   Finds critical traffic bottlenecks in Bengaluru reported in the evening of June 30.
-- How it was optimized:
--   Accelerated by partial index idx_traffic_heavy on traffic_readings WHERE congestion_level IN ('HEAVY', 'STANDSTILL').
--   Skips 249,977 normal readings and checks only the 23 severe traffic rows (0.2 ms, down from 15 ms).
SELECT s.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1
  AND t.congestion_level IN ('HEAVY', 'STANDSTILL')
  AND t.recorded_at >= '2026-06-30 18:00:00+05:30'
ORDER BY t.recorded_at DESC;

-- @R09
-- "Typical traffic" chart: average speed by hour of the day on segment 5
-- How it works:
--   Calculates the average speed for each of the 24 hours of the day on segment 5.
-- How it was optimized:
--   Accelerated by idx_traffic_readings_segment_recorded on (segment_id, recorded_at DESC).
--   Performs an Index Only Scan on the 125 readings for segment 5, finishing in 0.11 ms.
SELECT EXTRACT(HOUR FROM recorded_at) AS hour, round(avg(avg_speed_kmph), 1) AS avg_speed, count(*) AS readings
FROM traffic_readings
WHERE segment_id = 5
GROUP BY 1
ORDER BY 1;

-- @R10
-- Incident layer: incidents reported in Bengaluru on 30 June 2026
-- Why this query was rewritten:
--   The original query used: DATE(i.reported_at) = '2026-06-30'.
--   Wrapping reported_at inside the DATE() function hides it from normal indexes (non-sargable).
--   Also, DATE(timestamptz) cannot have a functional index because it depends on the session timezone.
--   We rewrote it into a clean date range: >= '2026-06-30 00:00:00+05:30' and < '2026-07-01 00:00:00+05:30'.
--   Accelerated by index idx_incident_reported_at (reported_at DESC, segment_id), dropping time from 1.58 ms to 0.08 ms.
SELECT i.report_id, i.incident_type, s.road_name, i.reported_at, i.expires_at, i.upvotes
FROM incident_reports i
JOIN road_segments s ON s.segment_id = i.segment_id
WHERE s.city_id = 1
  AND i.reported_at >= '2026-06-30 00:00:00+05:30'
  AND i.reported_at <  '2026-07-01 00:00:00+05:30'
ORDER BY i.reported_at DESC;

-- @R11
-- ETA quality: average error (actual − ETA, minutes) per travel mode per month in 2026
-- Why this query was rewritten:
--   Original used: EXTRACT(YEAR FROM started_at) = 2026.
--   The EXTRACT() function prevents PostgreSQL from doing a range lookup on an index.
--   We rewrote it into a clean timestamp range for the entire year 2026.
--   Accelerated by partial index idx_nav_completed_started WHERE status = 'COMPLETED'.
SELECT date_trunc('month', started_at) AS month, travel_mode,
       round(avg(actual_minutes - eta_minutes), 2) AS avg_error_min, count(*) AS trips
FROM navigation_sessions
WHERE status = 'COMPLETED'
  AND started_at >= '2026-01-01 00:00:00+05:30'
  AND started_at <  '2027-01-01 00:00:00+05:30'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R12
-- Trends: 10 most-navigated-to places in Mumbai in the last 7 days of June 2026
-- How it works:
--   Finds destination places in Mumbai (city_id = 2) with trips starting on or after June 24.
-- How it was optimized:
--   Accelerated by idx_nav_started_dest on navigation_sessions and idx_places_city_place on places.
--   Time dropped from 20.7 ms to 1.8 ms (11x speedup).
SELECT p.place_id, p.name, count(*) AS navigations
FROM navigation_sessions n
JOIN places p ON p.place_id = n.dest_place_id
WHERE p.city_id = 2
  AND n.started_at >= '2026-06-24'
GROUP BY p.place_id, p.name
ORDER BY navigations DESC
LIMIT 10;

-- @R13
-- Data team: places that have never been the starting point of a navigation (Problem P6)
-- Why this query was rewritten (IMPORTANT VIVA EXPLANATION):
--   The original query was:
--     WHERE p.place_id NOT IN (SELECT n.origin_place_id FROM navigation_sessions n);
--   When navigations start from GPS coordinates, origin_place_id is NULL.
--   In SQL three-valued logic: (place_id NOT IN (..., NULL)) evaluates to UNKNOWN!
--   Because WHERE only keeps rows that evaluate to TRUE, the original query returned 0 rows!
--   This caused Problem P6 ("places never used as start point is empty, which is impossible").
--   We rewrote it using NOT EXISTS. NOT EXISTS safely handles NULLs and uses our partial index
--   idx_nav_origin_place to perform a Merge Anti Join, correctly returning all 33,368 places in 5.4 ms.
SELECT p.place_id, p.name
FROM places p
WHERE NOT EXISTS (
    SELECT 1 FROM navigation_sessions n WHERE n.origin_place_id = p.place_id
);

-- @R14
-- Local Guides leaderboard: users with the most reviews in 2026 (photos as tie-breaker)
-- Why this query was rewritten:
--   Original query joined all 90,000 reviews with all 40,000 users before grouping.
--   We rewrote it to group place_reviews first and pick the top 20 users (in a subquery),
--   and only then join those 20 users with the users table to get their display names.
--   Accelerated by index idx_reviews_created_user, dropping time from 17.9 ms to 1.3 ms (14x speedup).
SELECT u.user_id, u.display_name, u.guide_level, agg.reviews, agg.photos
FROM (
    SELECT r.user_id, count(*) AS reviews, sum(r.photo_count) AS photos
    FROM place_reviews r
    WHERE r.created_at >= '2026-01-01'
    GROUP BY r.user_id
    ORDER BY reviews DESC, photos DESC
    LIMIT 20
) agg
JOIN users u ON u.user_id = agg.user_id
ORDER BY agg.reviews DESC, agg.photos DESC;

-- @R15
-- Data quality: places whose stored rating or review count no longer matches their reviews
-- How it works:
--   Compares cached avg_rating and review_count in places against real review counts.
-- How it was optimized:
--   Accelerated by index idx_place_reviews_place_rating on place_reviews(place_id) INCLUDE (rating).
--   PostgreSQL uses a streaming Merge Join with places_pkey, dropping time from 57.6 ms to 19.6 ms.
SELECT p.place_id, p.avg_rating, p.review_count, round(avg(r.rating), 1) AS actual_rating, count(*) AS actual_reviews
FROM places p
JOIN place_reviews r ON r.place_id = p.place_id
GROUP BY p.place_id, p.avg_rating, p.review_count
HAVING p.review_count <> count(*) OR p.avg_rating <> round(avg(r.rating), 1)
ORDER BY p.place_id;

-- @R16
-- Data quality: permanently closed places that people still navigate to (2026)
-- How it works:
--   Identifies navigation trips in 2026 destined for permanently closed venues.
-- How it was optimized:
--   Accelerated by partial index idx_places_closed on places WHERE is_permanently_closed,
--   joined with idx_nav_started_dest on navigation_sessions. Time dropped from 27 ms to 5.6 ms.
SELECT p.place_id, p.name, count(*) AS navigations_2026
FROM places p
JOIN navigation_sessions n ON n.dest_place_id = p.place_id
WHERE p.is_permanently_closed
  AND n.started_at >= '2026-01-01'
GROUP BY p.place_id, p.name
ORDER BY navigations_2026 DESC;

-- @R17
-- Routing team: destinations with the most re-routing on average (at least 5 trips)
-- How it works:
--   Finds destinations with the highest average rerouted_count.
-- How it was optimized:
--   Covering index idx_nav_dest_rerouted on (dest_place_id) INCLUDE (rerouted_count).
--   Note for viva: This query groups across all 200,000 navigation sessions without a WHERE filter,
--   so it must read all rows. Time improved from 62.9 ms to 29.2 ms (2.2x speedup).
SELECT dest_place_id, count(*) AS trips, round(avg(rerouted_count), 2) AS avg_reroutes
FROM navigation_sessions
GROUP BY dest_place_id
HAVING count(*) >= 5
ORDER BY avg_reroutes DESC
LIMIT 20;

-- @R18
-- Product analytics: share of cancelled navigations per travel mode
-- How it works:
--   Calculates percentage of cancelled trips per travel mode (DRIVE, TRANSIT, WALK, etc.).
-- How it was optimized:
--   Accelerated by covering index idx_nav_mode_status on (travel_mode, status).
--   PostgreSQL uses a Parallel Index Only Scan, reducing time from 26.8 ms to 10.7 ms.
SELECT travel_mode, count(*) AS sessions,
       round(100.0 * count(*) FILTER (WHERE status = 'CANCELLED') / count(*), 1) AS cancelled_pct
FROM navigation_sessions
GROUP BY travel_mode
ORDER BY cancelled_pct DESC;

-- @R19
-- Health report: every Bengaluru hospital with its number of navigations and the most recent one
-- Why this query was rewritten (BIGGEST IMPROVEMENT: 26,260 ms -> 25 ms, 1048x faster!):
--   Original query had two correlated subqueries inside SELECT:
--     (SELECT count(*) FROM navigation_sessions n WHERE n.dest_place_id = p.place_id),
--     (SELECT max(n.started_at) FROM navigation_sessions n WHERE n.dest_place_id = p.place_id)
--   For all 1,067 hospitals in Bengaluru, PostgreSQL scanned all 200,000 sessions twice!
--   1,067 * 2 = 2,134 full table scans = 426 million row checks, taking 26.26 SECONDS!
--   We rewrote it into a single LEFT JOIN on a pre-aggregated subquery that groups navigation_sessions
--   just ONCE. Execution time dropped from 26.26 seconds down to 25.05 milliseconds!
SELECT p.place_id, p.name,
       COALESCE(n.navigations, 0) AS navigations,
       n.last_navigation_at
FROM places p
LEFT JOIN (
    SELECT dest_place_id, count(*) AS navigations, max(started_at) AS last_navigation_at
    FROM navigation_sessions
    GROUP BY dest_place_id
) n ON n.dest_place_id = p.place_id
WHERE p.category_id = (SELECT category_id FROM place_categories WHERE category_name = 'Hospital')
  AND p.city_id = 1
ORDER BY navigations DESC;

-- @R20
-- Product analytics: navigations per day and running total for June 2026
-- Why this query was rewritten:
--   Original used: started_at::date BETWEEN '2026-06-01' AND '2026-06-30'.
--   Casting started_at::date prevented using a regular index on started_at.
--   We rewrote it into a clean timestamp range for June 2026.
--   Accelerated by index idx_nav_started_dest, dropping time from 18.2 ms to 1.3 ms (14x speedup).
SELECT day, sessions, sum(sessions) OVER (ORDER BY day) AS running_total
FROM (
    SELECT started_at::date AS day, count(*) AS sessions
    FROM navigation_sessions
    WHERE started_at >= '2026-06-01 00:00:00+05:30'
      AND started_at <  '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Data team: places with no opening hours, counted per category
-- How it works:
--   Finds places that have no records in opening_hours and groups them by category name.
-- How it was optimized:
--   Accelerated by composite index idx_places_place_cat on (place_id, category_id).
--   PostgreSQL performs a fast anti-join, dropping time from 40.1 ms to 13.8 ms.
SELECT c.category_name, count(*) AS places_without_hours
FROM places p
JOIN place_categories c ON c.category_id = p.category_id
WHERE NOT EXISTS (SELECT 1 FROM opening_hours h WHERE h.place_id = p.place_id)
GROUP BY c.category_name
ORDER BY places_without_hours DESC;

-- @R22
-- Moderation console: all reviews, newest first, page 2,001 (25 per page)
-- How it works:
--   Deep pagination query retrieving reviews 50,001 to 50,025 ordered by created_at DESC.
-- How it was optimized:
--   Without an index, PostgreSQL must sort all 90,000 reviews in memory.
--   Accelerated by covering index idx_reviews_created_covering on (created_at DESC).
--   PostgreSQL scans the index directly to row 50,000 in 3.8 ms (down from 31.3 ms).
SELECT review_id, place_id, user_id, rating, created_at
FROM place_reviews
ORDER BY created_at DESC
OFFSET 50000
LIMIT 25;

-- @R23
-- Plus Code search: open the place with this code
-- How it works:
--   Finds a place by its unique Google Plus Code ('22222222+2W').
-- How it was optimized:
--   Uses the unique B-tree index places_plus_code_key created in Phase 2 schema.
--   Runs in 0.025 ms (instant point lookup).
SELECT place_id, name, latitude, longitude
FROM places
WHERE plus_code = '22222222+2W';

-- @R24
-- Duplicate listings: Bengaluru restaurants with the same name within ~100 m of each other
-- How it works:
--   Self-joins places table to detect potential duplicate restaurant listings in Bengaluru.
-- How it was optimized:
--   Accelerated by idx_places_name_id on (name, place_id) and idx_places_city_cat_rating.
--   Time dropped from 9.1 ms to 4.4 ms (2x speedup).
SELECT a.place_id, b.place_id AS duplicate_id, a.name
FROM places a
JOIN places b ON b.name = a.name AND b.place_id > a.place_id
             AND abs(b.latitude - a.latitude) < 0.001 AND abs(b.longitude - a.longitude) < 0.001
WHERE a.city_id = 1 AND a.category_id = 1;

-- @R25
-- Road safety: share of readings above the speed limit, per road type
-- How it works:
--   Compares avg_speed_kmph against speed_limit_kmph across all 250,000 traffic readings.
-- How it was optimized:
--   Accelerated by index idx_traffic_readings_segment_recorded on traffic_readings.
--   Time dropped from 54.0 ms to 26.9 ms (2x speedup).
SELECT s.road_type, count(*) AS readings,
       round(100.0 * count(*) FILTER (WHERE t.avg_speed_kmph > s.speed_limit_kmph) / count(*), 1) AS over_limit_pct
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
GROUP BY s.road_type
ORDER BY over_limit_pct DESC;

-- @W01
-- "Start": begin navigation from current location to place 18
-- Inserts a new active navigation session. Runs in 0.9 ms.
INSERT INTO navigation_sessions (session_id, user_id, origin_lat, origin_lng, dest_place_id, travel_mode,
                                 started_at, distance_km, eta_minutes, status)
VALUES (90000001, 1005, 12.935200, 77.624500, 18, 'TWO_WHEELER', '2026-07-01 20:00:00+05:30', 4.20, 14, 'IN_PROGRESS');

-- @W02
-- Write a review: user 1005 rates place 18
-- Inserts a review, safely ignoring duplicate review submissions with ON CONFLICT. Runs in 0.6 ms.
INSERT INTO place_reviews (review_id, place_id, user_id, rating, review_text, photo_count, created_at)
VALUES (90000001, 18, 1005, 4, 'Good food, slow service', 2, '2026-07-01 21:00:00+05:30')
ON CONFLICT (place_id, user_id) DO NOTHING;

-- @W03
-- "Save": user 1005 adds place 18 to "Want to go"
-- Inserts a bookmark, ignoring duplicates with ON CONFLICT. Runs in 0.8 ms.
INSERT INTO saved_places (user_id, place_id, list_name, saved_at)
VALUES (1005, 18, 'Want to go', '2026-07-01 21:05:00+05:30')
ON CONFLICT DO NOTHING;

-- @W04
-- Nightly job: recompute every place's rating and review count
-- Recomputes rating aggregates for all places.
-- Accelerated by idx_place_reviews_place_rating. Takes 42.7 ms to update 558 places.
UPDATE places p
SET avg_rating = s.avg_rating, review_count = s.n
FROM (SELECT place_id, round(avg(rating), 1) AS avg_rating, count(*) AS n FROM place_reviews GROUP BY place_id) s
WHERE s.place_id = p.place_id
  AND (p.avg_rating IS DISTINCT FROM s.avg_rating OR p.review_count <> s.n);

-- @W05
-- Housekeeping: delete incident reports that expired before June 2026
-- Purges expired incident reports. Deletes 11,339 rows in 2.1 ms.
DELETE FROM incident_reports
WHERE expires_at < '2026-06-01';

-- @END
ROLLBACK;
