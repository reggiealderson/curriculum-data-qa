# Course & award data QA in SQL — CRICOS (University of Sydney)

A small, focused data-quality project on **real, official course and award
data**: the University of Sydney's registrations in the **CRICOS national
register** (the Commonwealth Register of Institutions and Courses for Overseas
Students). It runs a suite of **SQL validation checks** over 655 USYD
course/award records, surfaces genuine data defects, and sets out how the
process would run in practice.

It demonstrates the core of a curriculum data-analyst role directly: develop and
execute SQL for data analysis and quality assurance; maintain **course and award**
data for accuracy and compliance; and design a repeatable QA process — on the
exact kind of reference data the role governs.

- **Real, official, current data** — a bulk government export, no scraping.
- **10 SQL checks** across completeness, uniqueness, conformance, domain,
  spelling, and (bidirectional) cross-source reconciliation.
- **Zero setup:** one `sqlite3` command over CSVs committed to the repo.

---

## Quick start

```bash
git clone https://github.com/reggiealderson/curriculum-data-qa.git
cd curriculum-data-qa
./run.sh                 # builds cricos_qa.db and prints the QA report
# or:  sqlite3 cricos_qa.db < sql/build.sql
```

Only `sqlite3` is needed (pre-installed on macOS/Linux).

---

## Method (how it works)

The idea is deliberately simple and transparent, in three stages:

1. **Source.** Download the national CRICOS export (one file,
   [data.gov.au](https://data.gov.au/data/dataset/cricos)), then extract USYD's
   655 course/award records (`prep/prepare.py`).
2. **Prepare two derived inputs.**
   - *Spelling* — build a word-frequency table over all ~26,000 national course
     names, then flag any *rare* word in a USYD name that has a *common*
     edit-distance-1 neighbour (the suggested correction). This is evidence-based
     typo detection with near-zero false positives — no dictionary, so no
     domain false positives.
   - *Reconciliation* — pull USYD's published course list from its public
     courses sitemap and fuzzy-match it against the CRICOS names
     (`prep/reconcile.py`), to find registered courses with no clear public page.
3. **Validate in SQL.** Load the CSVs into SQLite and run the checks
   (`sql/03_qa_checks.sql`). Each check returns only the records that fail it and
   is documented with what it catches, why it matters, and a severity.

**Reproducibility.** The prep scripts are included, but you never need to run
them: the derived CSVs are committed and the QA layer is pure SQL over them. The
one large file (the national export) is git-ignored and regenerable from the URL
above.

**Framing.** This is a methodology-first demonstration on real reference data,
reported neutrally — not an audit. CRICOS is simply the authoritative public copy
of the course/award data a university maintains internally; these are the checks
you would run on that data before it is trusted.

---

## The checks and what they found

| # | Category | Check | Result | Reading |
|---|----------|-------|--------|---------|
| C1 | Completeness | Missing mandatory fields | **0** ✓ | Every record is fully identified |
| U1 | Uniqueness | Duplicate CRICOS codes | **0** ✓ | The national key is unique |
| U2 | Uniqueness | Duplicate **active** course names | **45** | Same name + level under multiple non-expired codes (e.g. *Graduate Diploma in Computing* ×3) — which registration is current? |
| F1 | Conformance | Non-standard code format | **15** | 7-digit numeric codes vs the classic 6-digit + letter form — a format-consistency flag (the variant is common nationally too) |
| F2 | Conformance | Whitespace / punctuation defects | **3** | Double space, and stray spaces inside parentheses (`( Cotutelle`, `( Honours)`) |
| F3 | Conformance | `&` vs `and` inconsistency | **7** | Same concept written two ways across the register |
| D1 | Domain | Invalid AQF level | **0** ✓ | All course levels are recognised AQF descriptors |
| S1 | Spelling | Likely typos (evidence-based) | **5** | `Techonology`→`Technology`, `Philsophy`→`Philosophy` (×2), `Grauate`→`Graduate`, `Engineeering`→`Engineering`, each backed by frequency evidence |
| R1 | Reconciliation | **CRICOS → website**: registered courses with no website match | **69 candidates** | A **review queue, not errors** — a mix of genuinely superseded / "Exit Only" courses and fuzzy-match misses; adjudication is the real task |
| R2 | Reconciliation | **website → CRICOS**: website courses with no CRICOS match | **46 candidates** (15 pre-flagged) | Expected to be more benign — CRICOS is international-only, so domestic courses (e.g. 15 short *Sydney Professional Certificate*s) legitimately have no entry; the rest are fuzzy-match misses and specialisation sub-pages |

The result is an honest picture. USYD's course/award data is **well-maintained**:
the identity, key, completeness and domain checks pass cleanly. The real defects
are **consistency and accuracy at the margins** — a handful of spelling errors,
some formatting inconsistency, and a set of duplicate active registrations worth
confirming. Distinguishing a true issue from an expected one (the R1/R2 queues,
the code-format variant) is where the judgement is.

**On the reconciliation direction (R1 vs R2).** The two registers are not
symmetric. **CRICOS lists only courses offered to international (student-visa)
students**, so a domestic-only website course legitimately has no CRICOS entry —
which is why R2 is expected to be more benign than R1, and why neither is an
error list. Both queues also carry fuzzy-match noise: matching two systems by
course *name* is fragile (slug quirks like a trailing `0`, single-token names,
and specialisation sub-pages that roll up to one broader registration). The
methodological lesson — worth more than any single candidate — is that robust
reconciliation needs a **shared identifier or a maintained crosswalk**, not name
matching (see Recommendations).

### The spelling and formatting defects, verbatim

- `Bachelor of Information **Techonology** (Honours)`
- `Doctor of **Philsophy** in Engineering (Cotutelle)`
- `Doctor of **Philsophy** in Arts **( Cotutelle)**`  *(two defects on one record)*
- `**Grauate** Diploma in Design Science (Audio and Acoustics)`
- `Graduate Certificate in **Engineeering**`
- `Graduate␠␠Certificate in Health Communication`  *(double space)*

---

## Recommendations

How this would run as a real QA process for course/award data:

1. **Run the suite on every register load**, writing failures to an exceptions
   table stamped with a run date, so new vs. resolved issues are tracked over
   time rather than re-discovered.
2. **Severity-gate the checks.** Treat missing mandatory fields, duplicate keys
   and spelling errors in published award names as blocking; treat formatting and
   `&`/`and` inconsistency as warnings for a cleanup pass.
3. **Own the reference vocabularies.** The AQF levels and accepted code formats
   are themselves data that needs an owner and a change process — F1/D1 make
   drift visible.
4. **Fix the quick wins first.** The 5 spelling errors and the whitespace defects
   are trivial to correct and directly affect how award names appear to students
   and on testamurs.
5. **Operationalise the reconciliation, but match on a key, not a name.** Run
   CRICOS ↔ published-catalogue matching in **both directions** periodically
   (accounting for CRICOS being international-only); every candidate is
   corrected, confirmed intentional (superseded / exit-only / domestic-only), or
   improves the matcher. The durable fix is a **shared course identifier or
   crosswalk** so reconciliation stops depending on fuzzy name matching.
6. **Extend to units of study and course structure** for credit-point
   reconciliation (do a course's units sum to its stated total?) once course
   structure data is available.

---

## Repository layout

```
curriculum-data-qa/
├── README.md
├── run.sh                          # build DB + run checks (sqlite3 only)
├── data/
│   ├── cricos_usyd_courses.csv     # 655 USYD course/award records (committed)
│   ├── spelling_flags.csv          # evidence-based typo flags (committed)
│   ├── reconciliation_candidates.csv      # CRICOS → website candidates
│   ├── reconciliation_candidates_web.csv  # website → CRICOS candidates
│   ├── usyd_website_courses.csv     # USYD published course list (committed)
│   └── cricos-courses-national.csv  # full national export (git-ignored, regenerable)
├── prep/
│   ├── prepare.py                  # extract USYD subset + detect spelling typos
│   └── reconcile.py                # website list + CRICOS↔website matching
├── sql/
│   ├── 01_schema.sql               # staging tables + AQF vocabulary
│   ├── 02_load.sql                 # load the CSVs
│   ├── 03_qa_checks.sql            # the QA suite
│   └── build.sql                   # runs 01→02→03
└── LICENSE
```

---

## Provenance & attribution

Course data from the **CRICOS national register** (Australian Government,
`data.gov.au`, retrieved 2026), and USYD's public course list from its website.
Non-commercial portfolio demonstration of data QA methodology. All code is
original work by Reggie Alderson, MIT-licensed. Findings describe the published
data as extracted and are not an official audit.
