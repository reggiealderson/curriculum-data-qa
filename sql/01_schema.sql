-- ============================================================================
-- 01_schema.sql — Course & award data QA (CRICOS national register, USYD)
--
-- Staging tables hold the data exactly as published. No keys or constraints are
-- enforced on load, so the QA checks (03) find the problems the schema does not
-- prevent. Reference tables hold the controlled vocabularies the checks validate
-- against.
-- ============================================================================

DROP TABLE IF EXISTS cricos_courses;
DROP TABLE IF EXISTS spelling_flags;
DROP TABLE IF EXISTS reconciliation_candidates;
DROP TABLE IF EXISTS reconciliation_candidates_web;
DROP TABLE IF EXISTS ref_course_level;

-- USYD's course/award registrations, extracted from the national CRICOS export.
CREATE TABLE cricos_courses (
    provider_code       TEXT,
    institution_name    TEXT,
    cricos_course_code  TEXT,
    course_name         TEXT,
    dual_qualification  TEXT,
    foe_broad           TEXT,   -- Field of Education (broad)
    foe_narrow          TEXT,
    foe_detailed        TEXT,
    course_level        TEXT,   -- AQF level descriptor
    foundation_studies  TEXT,
    work_component      TEXT,
    duration_weeks      TEXT,
    course_language     TEXT,
    tuition_fee         TEXT,
    expired             TEXT
);

-- Likely spelling errors in course names, produced by prep/prepare.py
-- (a rare word with a common edit-distance-1 neighbour in the national corpus).
CREATE TABLE spelling_flags (
    cricos_course_code    TEXT,
    course_name           TEXT,
    suspect_word          TEXT,
    suggested_correction  TEXT,
    suspect_freq          TEXT,
    suggestion_freq       TEXT
);

-- Cross-source reconciliation queue, produced by prep/reconcile.py: AQF courses
-- in CRICOS with no confident match on the USYD website. CANDIDATES for review.
CREATE TABLE reconciliation_candidates (
    cricos_course_code  TEXT,
    course_name         TEXT,
    course_level        TEXT,
    best_website_match  TEXT,
    match_score         TEXT
);

-- Reverse-direction reconciliation queue: website courses with no confident
-- CRICOS match (from prep/reconcile.py). CANDIDATES for review.
CREATE TABLE reconciliation_candidates_web (
    slug               TEXT,
    inferred_name      TEXT,
    best_cricos_match  TEXT,
    match_score        TEXT,
    note               TEXT
);

-- Controlled vocabulary: valid AQF course-level descriptors used by CRICOS.
CREATE TABLE ref_course_level (course_level TEXT PRIMARY KEY);
INSERT INTO ref_course_level (course_level) VALUES
    ('Bachelor Degree'), ('Bachelor Honours Degree'),
    ('Masters Degree (Coursework)'), ('Masters Degree (Research)'),
    ('Masters Degree (Extended)'), ('Graduate Diploma'),
    ('Graduate Certificate'), ('Doctoral Degree'), ('Diploma'),
    ('Advanced Diploma'), ('Certificate I'), ('Certificate II'),
    ('Certificate III'), ('Certificate IV'), ('Non AQF Award');
