-- ============================================================================
-- 02_load.sql — load the prepared CSVs. Run from the repo root (see build.sql).
-- ============================================================================
.mode csv
.import --csv --skip 1 data/cricos_usyd_courses.csv cricos_courses
.import --csv --skip 1 data/spelling_flags.csv spelling_flags
.import --csv --skip 1 data/reconciliation_candidates.csv reconciliation_candidates
.import --csv --skip 1 data/reconciliation_candidates_web.csv reconciliation_candidates_web
