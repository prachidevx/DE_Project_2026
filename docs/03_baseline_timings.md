# Baseline Benchmark Timings

## 1. Overview

The baseline benchmark measures the execution time of all 30 workload queries
before applying any database optimizations.

Each query was executed three times. The execution times are recorded in
milliseconds (ms).

## 2. Benchmark Results

| Query ID | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---:|---:|---:|---:|
| R01 | 6.986 | 5.467 | 5.112 | 5.855 |
| R02 | 0.090 | 0.077 | 0.079 | 0.082 |
| R03 | 27.220 | 27.336 | 28.080 | 27.545 |
| R04 | 17.248 | 15.786 | 15.691 | 16.242 |
| R05 | 0.307 | 0.337 | 0.287 | 0.310 |
| R06 | 0.219 | 0.143 | 0.137 | 0.166 |
| R07 | 18.002 | 17.800 | 17.762 | 17.855 |
| R08 | 14.997 | 14.755 | 14.944 | 14.899 |
| R09 | 8.788 | 8.904 | 8.646 | 8.779 |
| R10 | 1.523 | 1.555 | 1.661 | 1.580 |
| R11 | 45.846 | 43.812 | 43.111 | 44.256 |
| R12 | 19.412 | 19.643 | 23.065 | 20.707 |
| R13 | 37.158 | 37.951 | 39.864 | 38.324 |
| R14 | 17.603 | 18.393 | 17.660 | 17.885 |
| R15 | 58.755 | 57.526 | 56.485 | 57.589 |
| R16 | 26.435 | 27.089 | 27.335 | 26.953 |
| R17 | 64.199 | 62.150 | 62.310 | 62.886 |
| R18 | 27.383 | 26.737 | 26.334 | 26.818 |
| R19 | 26291.227 | 26045.417 | 26443.660 | 26260.101 |
| R20 | 17.661 | 18.885 | 17.908 | 18.151 |
| R21 | 39.476 | 40.447 | 40.424 | 40.116 |
| R22 | 31.232 | 30.873 | 31.735 | 31.280 |
| R23 | 0.044 | 0.041 | 0.042 | 0.042 |
| R24 | 9.045 | 9.245 | 9.122 | 9.137 |
| R25 | 58.393 | 53.575 | 49.995 | 53.988 |
| W01 | 1.264 | 1.136 | 0.977 | 1.126 |
| W02 | 1.083 | 0.866 | 0.920 | 0.956 |
| W03 | 1.073 | 0.963 | 1.031 | 1.022 |
| W04 | 73.701 | 59.887 | 60.914 | 64.834 |
| W05 | 4.893 | 4.267 | 4.425 | 4.528 |

## 3. Initial Observation

Query R19 has the highest average execution time at approximately
26,260.101 ms (26.26 seconds).

This makes it an important candidate for investigation during the
optimization phase.

## 4. Source of Measurements

The measurements were collected from the raw execution plans stored in
`benchmarks/results/baseline/`.

The average timings are also recorded in
`benchmarks/results/baseline/summary.csv`.

## 5. Query Scan Types and Performance Observations

The execution plans show how PostgreSQL accesses the tables while executing each query.
The following observations summarize the scan types and the main factors affecting execution time.

| Query ID | Scan Type | Performance Observation |
|---|---|---|
| R01 | Sequential Scan | PostgreSQL scans the places table and filters approximately 40,026 rows before sorting the matching restaurants by distance. |
| R02 | Index Scan | Primary key indexes are used to retrieve the place and its opening hours efficiently. |
| R03 | Sequential Scan | The places table is scanned to search for names containing "biryani". The substring search requires checking many rows. |
| R04 | Sequential Scan | Opening hours and places are scanned to identify restaurants open at the specified late-night time. |
| R05 | Bitmap Heap Scan, Bitmap Index Scan, Index Scan | Indexes help locate reviews for the selected place and retrieve the related user records efficiently. |
| R06 | Index Scan | Primary key indexes are used to retrieve saved places and their corresponding place records. |
| R07 | Sequential Scan | Traffic readings and road segments are scanned to identify the latest traffic reading for each segment. |
| R08 | Sequential Scan, Index Scan | Traffic readings require scanning, while an index helps retrieve matching road segments. |
| R09 | Sequential Scan | The traffic readings table is scanned to calculate average speed grouped by hour. |
| R10 | Sequential Scan | Incident reports and road segments are scanned to identify incidents matching the specified date and location. |
| R11 | Sequential Scan | Navigation sessions are scanned to calculate average ETA error grouped by travel mode and month. |
| R12 | Sequential Scan | Navigation sessions and places are scanned to identify the most frequently visited Mumbai destinations. |
| R13 | Sequential Scan | Places and navigation sessions are scanned to identify places that have never been used as navigation origins. |
| R14 | Sequential Scan | Reviews and users are scanned to calculate the leaderboard based on review activity and photos. |
| R15 | Sequential Scan | Reviews and places are scanned to compare stored ratings and review counts with calculated values. |
| R16 | Sequential Scan | Navigation sessions and places are scanned to identify permanently closed places that were still navigated to. |
| R17 | Sequential Scan | Navigation sessions are scanned to calculate average rerouting counts for destinations. |
| R18 | Sequential Scan | Navigation sessions are scanned to calculate cancellation percentages grouped by travel mode. |
| R19 | Sequential Scan | Two correlated subqueries repeatedly scan the large navigation_sessions table for each hospital, resulting in very high execution time. |
| R20 | Sequential Scan | Navigation sessions are scanned to calculate daily navigation counts and running totals. |
| R21 | Sequential Scan | Opening hours, places and categories are scanned to identify places without opening-hour records. |
| R22 | Sequential Scan | The reviews table is scanned to retrieve a deep page of results using OFFSET 50000, increasing the amount of data PostgreSQL must process. |
| R23 | Index Scan | The unique Plus Code index allows PostgreSQL to find the matching place very quickly. |
| R24 | Sequential Scan | The places table is scanned to find restaurants with matching names located within the specified distance. |
| R25 | Sequential Scan | Traffic readings and road segments are scanned to calculate the percentage of readings exceeding speed limits. |
| W01 | No Scan (Direct INSERT) | A new navigation session is inserted directly without scanning existing table rows. |
| W02 | No Scan (INSERT with conflict handling) | A review is inserted using ON CONFLICT DO NOTHING, avoiding a separate table scan for the insert operation. |
| W03 | No Scan (INSERT with conflict handling) | A saved-place record is inserted using ON CONFLICT DO NOTHING. |
| W04 | Sequential Scan | Places and reviews are scanned to recalculate ratings and review counts for all places. |
| W05 | Sequential Scan | Incident reports are scanned to identify and delete expired records. |

### Overall Observation

Most queries use sequential scans because they process or filter records across larger tables.

Queries R02, R05, R06 and R23 benefit from indexes and have very low execution times.

R19 is the slowest query, with an average execution time of 26,260.101 ms (approximately 26.26 seconds). Its correlated subqueries repeatedly scan the navigation_sessions table, making it an important optimization candidate for a later phase.