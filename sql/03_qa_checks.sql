-- ============================================================================
-- 03_qa_checks.sql — course & award data-quality suite (CRICOS, USYD)
--
-- Each check returns only the records that FAIL it, and is documented with what
-- it catches, why it matters, and a severity. Checks are grouped: completeness,
-- uniqueness, conformance, domain, and (as an extension) cross-source
-- reconciliation. Neutral, methodology-first: findings describe the published
-- data as extracted.
-- ============================================================================
.mode column
.headers on

.print ''
.print '========================================================================'
.print ' DATASET SUMMARY  (USYD course/award records in the CRICOS register)'
.print '========================================================================'
SELECT COUNT(*) AS usyd_courses,
       COUNT(DISTINCT cricos_course_code) AS distinct_codes,
       SUM(CASE WHEN expired='Yes' THEN 1 ELSE 0 END) AS expired
FROM cricos_courses;


-- ----------------------------------------------------------------------------
-- COMPLETENESS
-- ----------------------------------------------------------------------------
.print ''
.print '== C1  Missing mandatory fields ===================================='
-- WHAT: records with a blank course name, code, level or field of education.
-- WHY:  these identify and classify the award; a blank breaks reporting and
--       compliance. SEVERITY: high. Clean = every record is fully identified.
SELECT cricos_course_code, course_name
FROM cricos_courses
WHERE TRIM(COALESCE(course_name,''))='' OR TRIM(COALESCE(cricos_course_code,''))=''
   OR TRIM(COALESCE(course_level,''))='' OR TRIM(COALESCE(foe_broad,''))='';


-- ----------------------------------------------------------------------------
-- UNIQUENESS
-- ----------------------------------------------------------------------------
.print ''
.print '== U1  Duplicate CRICOS course codes ==============================='
-- WHAT: a CRICOS code used by more than one record.
-- WHY:  the code is the national key for the course; duplicates break every
--       downstream reference. SEVERITY: high. Clean = the key is unique.
SELECT cricos_course_code, COUNT(*) AS n
FROM cricos_courses GROUP BY cricos_course_code HAVING COUNT(*) > 1;

.print ''
.print '== U2  Duplicate active course names ==============================='
-- WHAT: the same course name at the same level, registered under more than one
--       (non-expired) CRICOS code.
-- WHY:  two active registrations for one course raise the question of which is
--       current, and risk inconsistent details or double-counting. Not always
--       an error (a genuine re-registration may be mid-transition), so these are
--       flagged for review. SEVERITY: medium.
SELECT LOWER(TRIM(course_name)) AS course_name, course_level,
       COUNT(*) AS active_registrations,
       GROUP_CONCAT(cricos_course_code, ', ') AS codes
FROM cricos_courses
WHERE expired <> 'Yes'
GROUP BY LOWER(TRIM(course_name)), course_level
HAVING COUNT(*) > 1
ORDER BY active_registrations DESC, course_name
LIMIT 20;
.print '   (row count:)'
SELECT COUNT(*) AS duplicate_active_name_groups FROM (
  SELECT 1 FROM cricos_courses WHERE expired <> 'Yes'
  GROUP BY LOWER(TRIM(course_name)), course_level HAVING COUNT(*) > 1);


-- ----------------------------------------------------------------------------
-- CONFORMANCE (format / consistency)
-- ----------------------------------------------------------------------------
.print ''
.print '== F1  Non-standard CRICOS code format ============================='
-- WHAT: codes not matching the classic 6-digit + 1-letter CRICOS format
--       (e.g. 000515F), validated with GLOB.
-- WHY:  a mix of code formats complicates validation and matching against other
--       systems. NOTE: a 7-digit numeric variant also occurs widely across the
--       national register, so this is a format-consistency flag to confirm the
--       accepted formats, not necessarily an error. SEVERITY: low.
SELECT cricos_course_code, course_name
FROM cricos_courses
WHERE cricos_course_code NOT GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][A-Z]'
ORDER BY cricos_course_code
LIMIT 20;
.print '   (row count:)'
SELECT COUNT(*) AS non_standard_code_format
FROM cricos_courses
WHERE cricos_course_code NOT GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][A-Z]';

.print ''
.print '== F2  Whitespace / punctuation defects in course names ============'
-- WHAT: names with leading/trailing spaces, double spaces, or a stray space
--       inside parentheses ("( Cotutelle").
-- WHY:  invisible/mechanical defects break exact matching and look unprofessional
--       on transcripts and testamurs. SEVERITY: low (but trivially fixable).
SELECT cricos_course_code, '[' || course_name || ']' AS course_name_bracketed
FROM cricos_courses
WHERE course_name <> TRIM(course_name)
   OR course_name LIKE '%  %'
   OR course_name LIKE '%( %'
   OR course_name LIKE '% )%';

.print ''
.print '== F3  Ampersand-vs-"and" inconsistency ==========================='
-- WHAT: course names using "&" where the register overwhelmingly uses "and".
-- WHY:  inconsistent representation of the same concept fragments search and
--       grouping. SEVERITY: low.
SELECT cricos_course_code, course_name
FROM cricos_courses
WHERE course_name LIKE '%&%'
ORDER BY course_name;


-- ----------------------------------------------------------------------------
-- DOMAIN
-- ----------------------------------------------------------------------------
.print ''
.print '== D1  Course level not a recognised AQF descriptor ================'
-- WHAT: a course_level value not in the AQF vocabulary.
-- WHY:  level drives fee category, duration expectations and reporting; an
--       unknown value is unclassifiable. SEVERITY: medium. Clean = all valid.
SELECT DISTINCT course_level
FROM cricos_courses
WHERE course_level NOT IN (SELECT course_level FROM ref_course_level);


-- ----------------------------------------------------------------------------
-- SPELLING  (evidence-based, from prep/prepare.py)
-- ----------------------------------------------------------------------------
.print ''
.print '== S1  Likely spelling errors in course names ======================'
-- WHAT: a rare word in a course name that has a common edit-distance-1
--       neighbour in the national corpus (the suggested correction).
-- WHY:  a misspelt award name is a visible accuracy/compliance defect. The
--       frequency evidence (rare word vs common correction) makes each flag
--       defensible with near-zero false positives. SEVERITY: high.
SELECT cricos_course_code, suspect_word, suggested_correction,
       suspect_freq  AS seen_x, suggestion_freq AS correction_seen_x, course_name
FROM spelling_flags
ORDER BY cricos_course_code;


-- ----------------------------------------------------------------------------
-- CROSS-SOURCE RECONCILIATION  (extension — a REVIEW QUEUE, not an error list)
-- ----------------------------------------------------------------------------
.print ''
.print '== R1  CRICOS -> website: registered courses with no website match =='
-- WHAT: AQF award registrations in CRICOS with no confident match among the
--       courses USYD publishes on its website (from prep/reconcile.py).
-- WHY:  a registered course with no public page may be superseded, exit-only,
--       or simply named differently online — a representation/compliance
--       question. The fuzzy match is imperfect, so this is a queue to
--       adjudicate, NOT an error count. SEVERITY: informational.
SELECT cricos_course_code, course_level, course_name, match_score
FROM reconciliation_candidates
ORDER BY match_score DESC, course_name
LIMIT 15;
.print '   (total candidates to adjudicate:)'
SELECT COUNT(*) AS cricos_to_website_candidates FROM reconciliation_candidates;

.print ''
.print '== R2  website -> CRICOS: website courses with no CRICOS match ======'
-- WHAT: courses USYD publishes on its website with no confident CRICOS match.
-- WHY:  ASYMMETRY MATTERS. CRICOS registers only courses offered to INTERNATIONAL
--       (student-visa) students, so a domestic-only website course legitimately
--       has NO CRICOS entry — this direction is expected to contain more benign
--       cases than R1. The `note` column pre-flags short professional
--       certificates (typically domestic/CPD). The rest are a mix of fuzzy-match
--       misses (slug quirks, single-token names) and specialisation sub-pages
--       that roll up to a broader CRICOS registration. Still a review queue, NOT
--       an error list. SEVERITY: informational.
SELECT slug, match_score, note
FROM reconciliation_candidates_web
ORDER BY (note = '') DESC, match_score DESC
LIMIT 15;
.print '   (total, and how many are pre-flagged professional certificates:)'
SELECT COUNT(*) AS website_to_cricos_candidates,
       SUM(CASE WHEN note <> '' THEN 1 ELSE 0 END) AS likely_domestic_prof_certs
FROM reconciliation_candidates_web;
