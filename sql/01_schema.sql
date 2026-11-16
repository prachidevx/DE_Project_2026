CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

DROP TABLE IF EXISTS incident_reports CASCADE;
DROP TABLE IF EXISTS navigation_sessions CASCADE;
DROP TABLE IF EXISTS traffic_readings CASCADE;
DROP TABLE IF EXISTS road_segments CASCADE;
DROP TABLE IF EXISTS saved_places CASCADE;
DROP TABLE IF EXISTS place_reviews CASCADE;
DROP TABLE IF EXISTS opening_hours CASCADE;
DROP TABLE IF EXISTS places CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS place_categories CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

CREATE TABLE cities (
    city_id         INTEGER PRIMARY KEY,
    city_name       VARCHAR(100) NOT NULL,
    center_lat      DOUBLE PRECISION NOT NULL,
    center_lng      DOUBLE PRECISION NOT NULL,
    CONSTRAINT cities_lat_lng_chk CHECK (
        center_lat BETWEEN -90.0 AND 90.0 AND
        center_lng BETWEEN -180.0 AND 180.0
    )
);

CREATE TABLE place_categories (
    category_id     INTEGER PRIMARY KEY,
    category_name   VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE users (
    user_id         INTEGER PRIMARY KEY,
    display_name    VARCHAR(150) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    home_city_id    INTEGER REFERENCES cities(city_id) ON DELETE SET NULL,
    is_local_guide  BOOLEAN NOT NULL DEFAULT FALSE,
    guide_level     SMALLINT,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT users_email_format_chk CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    ),
    CONSTRAINT users_guide_level_chk CHECK (
        (is_local_guide = FALSE AND guide_level IS NULL) OR
        (is_local_guide = TRUE AND guide_level BETWEEN 1 AND 10)
    )
);

CREATE TABLE places (
    place_id                INTEGER PRIMARY KEY,
    plus_code               VARCHAR(20) NOT NULL UNIQUE,
    name                    VARCHAR(255) NOT NULL,
    category_id             INTEGER NOT NULL REFERENCES place_categories(category_id) ON DELETE RESTRICT,
    city_id                 INTEGER NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    latitude                DOUBLE PRECISION NOT NULL,
    longitude               DOUBLE PRECISION NOT NULL,
    address                 TEXT NOT NULL,
    phone                   VARCHAR(30),
    website                 TEXT,
    price_level             SMALLINT,
    avg_rating              NUMERIC(3, 1),
    review_count            INTEGER NOT NULL DEFAULT 0,
    is_permanently_closed   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL,
    CONSTRAINT places_plus_code_chk CHECK (
        plus_code ~ '^[0-9A-Z]{8}\+[0-9A-Z]{2}$'
    ),
    CONSTRAINT places_lat_lng_chk CHECK (
        latitude BETWEEN -90.0 AND 90.0 AND
        longitude BETWEEN -180.0 AND 180.0
    ),
    CONSTRAINT places_price_level_chk CHECK (
        price_level IS NULL OR price_level BETWEEN 1 AND 4
    ),
    CONSTRAINT places_rating_count_chk CHECK (
        (avg_rating IS NULL AND review_count = 0) OR
        (avg_rating BETWEEN 1.0 AND 5.0 AND review_count >= 0)
    )
);

CREATE TABLE opening_hours (
    place_id        INTEGER NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    weekday         SMALLINT NOT NULL,
    opens           TIME NOT NULL,
    closes          TIME NOT NULL,
    PRIMARY KEY (place_id, weekday),
    CONSTRAINT opening_hours_weekday_chk CHECK (
        weekday BETWEEN 1 AND 7
    )
);

CREATE TABLE place_reviews (
    review_id       BIGINT PRIMARY KEY,
    place_id        INTEGER NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    rating          SMALLINT NOT NULL,
    review_text     TEXT,
    photo_count     INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT place_reviews_place_user_unique UNIQUE (place_id, user_id),
    CONSTRAINT place_reviews_rating_chk CHECK (
        rating BETWEEN 1 AND 5
    ),
    CONSTRAINT place_reviews_photo_count_chk CHECK (
        photo_count >= 0
    )
);

CREATE TABLE saved_places (
    user_id         INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    place_id        INTEGER NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    list_name       VARCHAR(100) NOT NULL,
    saved_at        TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, place_id, list_name),
    CONSTRAINT saved_places_list_name_chk CHECK (
        list_name IN ('Favourites', 'Travel plans', 'Want to go', 'Starred')
    )
);

CREATE TABLE road_segments (
    segment_id          INTEGER PRIMARY KEY,
    road_name           VARCHAR(200) NOT NULL,
    city_id             INTEGER NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    road_type           VARCHAR(20) NOT NULL,
    start_lat           DOUBLE PRECISION NOT NULL,
    start_lng           DOUBLE PRECISION NOT NULL,
    end_lat             DOUBLE PRECISION NOT NULL,
    end_lng             DOUBLE PRECISION NOT NULL,
    length_m            INTEGER NOT NULL,
    speed_limit_kmph    INTEGER NOT NULL,
    CONSTRAINT road_segments_type_chk CHECK (
        road_type IN ('HIGHWAY', 'ARTERIAL', 'LOCAL')
    ),
    CONSTRAINT road_segments_geometry_chk CHECK (
        start_lat BETWEEN -90.0 AND 90.0 AND
        start_lng BETWEEN -180.0 AND 180.0 AND
        end_lat BETWEEN -90.0 AND 90.0 AND
        end_lng BETWEEN -180.0 AND 180.0 AND
        length_m > 0 AND
        speed_limit_kmph > 0
    )
);

CREATE TABLE traffic_readings (
    reading_id          BIGINT PRIMARY KEY,
    segment_id          INTEGER NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    recorded_at         TIMESTAMPTZ NOT NULL,
    avg_speed_kmph      NUMERIC(5, 1) NOT NULL,
    congestion_level    VARCHAR(20) NOT NULL,
    CONSTRAINT traffic_readings_congestion_chk CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    ),
    CONSTRAINT traffic_readings_speed_chk CHECK (
        avg_speed_kmph >= 0.0
    )
);

CREATE TABLE navigation_sessions (
    session_id          BIGINT PRIMARY KEY,
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
    CONSTRAINT navigation_sessions_mode_chk CHECK (
        travel_mode IN ('DRIVE', 'TWO_WHEELER', 'TRANSIT', 'WALK')
    ),
    CONSTRAINT navigation_sessions_status_chk CHECK (
        status IN ('COMPLETED', 'CANCELLED', 'IN_PROGRESS')
    ),
    CONSTRAINT navigation_sessions_completion_chk CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL AND actual_minutes > 0) OR
        (status <> 'COMPLETED' AND actual_minutes IS NULL)
    ),
    CONSTRAINT navigation_sessions_metrics_chk CHECK (
        origin_lat BETWEEN -90.0 AND 90.0 AND
        origin_lng BETWEEN -180.0 AND 180.0 AND
        distance_km >= 0.0 AND
        eta_minutes > 0 AND
        rerouted_count >= 0
    )
);

CREATE TABLE incident_reports (
    report_id       BIGINT PRIMARY KEY,
    segment_id      INTEGER NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    incident_type   VARCHAR(20) NOT NULL,
    reported_at     TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    upvotes         INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT incident_reports_type_chk CHECK (
        incident_type IN ('ROADWORK', 'BREAKDOWN', 'WATERLOGGING', 'POLICE', 'ACCIDENT', 'CLOSURE')
    ),
    CONSTRAINT incident_reports_validity_chk CHECK (
        expires_at >= reported_at AND
        upvotes >= 0
    )
);
