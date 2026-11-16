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