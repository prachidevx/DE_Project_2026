-- =====================================================================
-- Google Maps DBMS Project: CP4 Table Partitioning
-- File: sql/08_partitioning.sql
--
-- Objective:
--   Implement Declarative Table Partitioning for `navigation_sessions`
--   to scale from 200,000 sessions (Seed) to 4,000,000+ sessions (Large)
--   and architect for 100x volume (20M+ sessions).
--
-- Key Topics Addressed:
--   1. Partitioning strategy: RANGE on `started_at`
--   2. Primary key rule for partitioned tables in PostgreSQL
--   3. Partition creation (quarterly partitions for 2025-2026 + DEFAULT)
--   4. Global/Local index propagation across partitions
--   5. Data migration from unpartitioned table
--   6. Demonstration of Partition Pruning via EXPLAIN (ANALYZE, BUFFERS)
--   7. Lifecycle management (DETACH / DROP partition vs bulk DELETE)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

-- ---------------------------------------------------------------------
-- Section 1: The Partitioned Table DDL
-- ---------------------------------------------------------------------
-- PRIMARY KEY RULE FOR PARTITIONED TABLES:
-- In PostgreSQL, any UNIQUE or PRIMARY KEY constraint on a partitioned
-- table MUST include all partition key columns. A simple PRIMARY KEY (session_id)
-- is rejected with:
--   ERROR: unique constraint on partitioned table must include all partitioning columns
-- Therefore, the primary key must be composite: (session_id, started_at).
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS navigation_sessions_partitioned CASCADE;

CREATE TABLE navigation_sessions_partitioned (
    session_id          BIGINT NOT NULL,
    user_id             INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    origin_place_id     INTEGER REFERENCES places(place_id) ON DELETE SET NULL,
    origin_lat          DOUBLE PRECISION NOT NULL,
    origin_lng          DOUBLE PRECISION NOT NULL,
    dest_place_id       INTEGER NOT NULL REFERENCES places(place_id) ON DELETE RESTRICT,
    travel_mode         VARCHAR(20) NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL,
    distance_km         NUMERIC(8, 2) NOT NULL,
    eta_minutes         INTEGER NOT NULL,
    actual_minutes      INTEGER,
    rerouted_count      INTEGER NOT NULL DEFAULT 0,
    status              VARCHAR(20) NOT NULL,

    -- Composite Primary Key satisfying PostgreSQL partitioning invariant
    CONSTRAINT navigation_sessions_part_pkey PRIMARY KEY (session_id, started_at),

    -- Domain & Integrity Constraints (identical to 01_schema.sql)
    CONSTRAINT nav_part_mode_chk CHECK (
        travel_mode IN ('DRIVE', 'TWO_WHEELER', 'TRANSIT', 'WALK')
    ),
    CONSTRAINT nav_part_status_chk CHECK (
        status IN ('COMPLETED', 'CANCELLED', 'IN_PROGRESS')
    ),
    CONSTRAINT nav_part_completion_chk CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL AND actual_minutes > 0) OR
        (status <> 'COMPLETED' AND actual_minutes IS NULL)
    ),
    CONSTRAINT nav_part_metrics_chk CHECK (
        origin_lat BETWEEN -90.0 AND 90.0 AND
        origin_lng BETWEEN -180.0 AND 180.0 AND
        distance_km >= 0.0 AND
        eta_minutes > 0 AND
        rerouted_count >= 0
    )
) PARTITION BY RANGE (started_at);


-- ---------------------------------------------------------------------
-- Section 2: Declarative Partitions (Quarterly Slices 2025 - 2026)
-- ---------------------------------------------------------------------
-- Quarterly intervals provide optimal granularity:
--   - Each partition holds ~50k rows on seed, ~1M rows on large dataset.
--   - Partitions comfortably fit within memory (shared_buffers / OS cache).
--   - Retention policies and maintenance (VACUUM / REINDEX) run per partition.
-- ---------------------------------------------------------------------

-- 2025 Quarters
CREATE TABLE nav_2025_q1 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE nav_2025_q2 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE nav_2025_q3 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE nav_2025_q4 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- 2026 Quarters
CREATE TABLE nav_2026_q1 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE nav_2026_q2 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE nav_2026_q3 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE nav_2026_q4 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Safety partition for boundary outliers or upcoming years
CREATE TABLE nav_default PARTITION OF navigation_sessions_partitioned DEFAULT;


-- ---------------------------------------------------------------------
-- Section 3: Index Propagation
-- ---------------------------------------------------------------------
-- In PostgreSQL 11+, defining an index on the partitioned parent automatically
-- builds identical local indexes across all existing and future child partitions.
-- ---------------------------------------------------------------------

-- Serves: R11 (ETA accuracy per mode in 2026)
CREATE INDEX idx_nav_part_completed_started
    ON navigation_sessions_partitioned (started_at, travel_mode)
    INCLUDE (actual_minutes, eta_minutes)
    WHERE status = 'COMPLETED';

-- Serves: R12 (Trends), R16 (Closed places navigated), R20 (Daily trends)
CREATE INDEX idx_nav_part_started_dest
    ON navigation_sessions_partitioned (started_at, dest_place_id);

-- Serves: R13 (Places never used as origin - Anti-join index)
CREATE INDEX idx_nav_part_origin_place
    ON navigation_sessions_partitioned (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

-- Serves: R18 (Cancellation share by travel mode)
CREATE INDEX idx_nav_part_mode_status
    ON navigation_sessions_partitioned (travel_mode, status);

-- Serves: R17, R19 (Destination lookups)
CREATE INDEX idx_nav_part_dest_place
    ON navigation_sessions_partitioned (dest_place_id);


-- ---------------------------------------------------------------------
-- Section 4: Data Migration
-- ---------------------------------------------------------------------
-- Route all existing rows from `navigation_sessions` into their respective
-- partitions automatically based on `started_at`.
-- ---------------------------------------------------------------------
INSERT INTO navigation_sessions_partitioned
SELECT * FROM navigation_sessions;

-- Gather updated catalog statistics on all child partitions
ANALYZE navigation_sessions_partitioned;


-- ---------------------------------------------------------------------
-- Section 5: Demonstration of Partition Pruning (EXPLAIN Plans)
-- ---------------------------------------------------------------------
-- Partition Pruning allows the PostgreSQL planner to inspect WHERE clause
-- constants against the partition boundary ranges, eliminating irrelevant
-- tables BEFORE disk/buffer access occurs.
-- ---------------------------------------------------------------------

-- Demo 1: June 2026 Navigation Sessions (R20 Workload Pattern)
-- Notice that the planner ONLY scans `nav_2026_q2` and prunes all other 7 partitions!
EXPLAIN (ANALYZE, BUFFERS)
SELECT started_at::date AS day, count(*) AS sessions
FROM navigation_sessions_partitioned
WHERE started_at >= '2026-06-01 00:00:00+05:30'
  AND started_at <  '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY day;

-- Demo 2: ETA Accuracy Error for 2026 (R11 Workload Pattern)
-- The planner scans only `nav_2026_q1` and `nav_2026_q2`, pruning all of 2025.
EXPLAIN (ANALYZE, BUFFERS)
SELECT travel_mode, count(*) AS trips,
       round(avg(actual_minutes - eta_minutes), 2) AS avg_error_min
FROM navigation_sessions_partitioned
WHERE status = 'COMPLETED'
  AND started_at >= '2026-01-01 00:00:00+05:30'
  AND started_at <  '2026-07-01 00:00:00+05:30'
GROUP BY travel_mode;

-- Demo 3: Demonstrating Pruning DISABLED vs ENABLED
-- By turning off enable_partition_pruning, Postgres must scan all 8 partitions.
SET enable_partition_pruning = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM navigation_sessions_partitioned
WHERE started_at >= '2026-06-01 00:00:00+05:30'
  AND started_at <  '2026-07-01 00:00:00+05:30';

-- Re-enable pruning (default production setting)
SET enable_partition_pruning = on;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM navigation_sessions_partitioned
WHERE started_at >= '2026-06-01 00:00:00+05:30'
  AND started_at <  '2026-07-01 00:00:00+05:30';


-- ---------------------------------------------------------------------
-- Section 6: Zero-Cost Archival Lifecycle (DETACH PARTITION)
-- ---------------------------------------------------------------------
-- In an unpartitioned table, purging old data requires:
--   DELETE FROM navigation_sessions WHERE started_at < '2025-04-01';
-- This generates millions of WAL records, bloats the table, and locks writes.
--
-- With partitioning, archival is an instantaneous O(1) metadata operation:
-- ---------------------------------------------------------------------

-- Step 1: Detach old partition (zero locks on active partitions)
-- ALTER TABLE navigation_sessions_partitioned DETACH PARTITION nav_2025_q1;

-- Step 2: Export detached partition to cold storage / Parquet / S3
-- \copy nav_2025_q1 TO 'archive/nav_2025_q1.csv' WITH (FORMAT csv, HEADER true)

-- Step 3: Instant drop without WAL or transaction log overhead
-- DROP TABLE nav_2025_q1;
