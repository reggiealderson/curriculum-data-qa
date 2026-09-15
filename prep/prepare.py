#!/usr/bin/env python3
"""
Prepare the CRICOS course/award QA inputs from the national register.

Inputs  : data/cricos-courses-national.csv   (bulk download from data.gov.au)
Outputs : data/cricos_usyd_courses.csv        (University of Sydney course/award records)
          data/spelling_flags.csv             (data-driven likely typos in course names)

Spelling method (no external dictionary, so no domain false positives):
  1. Build a word-frequency table over ALL national course names (~26k courses).
     Legitimate academic words ("Biostatistics", "Nanotechnology") occur many
     times; a genuine typo occurs once or twice.
  2. For each rare word (national frequency <= RARE_MAX) in a USYD course name,
     generate its edit-distance-1 neighbours and keep any neighbour that is
     COMMON (frequency >= COMMON_MIN). That common neighbour is the suggested
     correction. This flags "Techonology" -> "Technology" with strong evidence
     and almost no false positives.
"""
from __future__ import annotations

import csv
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NATIONAL = ROOT / "data" / "cricos-courses-national.csv"
OUT_USYD = ROOT / "data" / "cricos_usyd_courses.csv"
OUT_FLAGS = ROOT / "data" / "spelling_flags.csv"

USYD_PROVIDER = "00026A"
RARE_MAX = 2       # a word seen this many times or fewer nationally is "rare"
COMMON_MIN = 50    # a correction candidate must be seen at least this often
LETTERS = "abcdefghijklmnopqrstuvwxyz"

# Map the verbose source headers to tidy column names we keep.
COLUMNS = {
    "CRICOS Provider Code": "provider_code",
    "Institution Name": "institution_name",
    "CRICOS Course Code": "cricos_course_code",
    "Course Name": "course_name",
    "Dual Qualification": "dual_qualification",
    "Field of Education 1 Broad Field": "foe_broad",
    "Field of Education 1 Narrow Field": "foe_narrow",
    "Field of Education 1 Detailed Field": "foe_detailed",
    "Course Level": "course_level",
    "Foundation Studies": "foundation_studies",
    "Work Component": "work_component",
    "Duration (Weeks)": "duration_weeks",
    "Course Language": "course_language",
    "Tuition Fee": "tuition_fee",
    "Expired": "expired",
}

WORD_RE = re.compile(r"[A-Za-z]+")


def words(name: str):
    return [w.lower() for w in WORD_RE.findall(name) if len(w) >= 4]


def edits1(word: str):
    splits = [(word[:i], word[i:]) for i in range(len(word) + 1)]
    deletes = [a + b[1:] for a, b in splits if b]
    transposes = [a + b[1] + b[0] + b[2:] for a, b in splits if len(b) > 1]
    replaces = [a + c + b[1:] for a, b in splits if b for c in LETTERS]
    inserts = [a + c + b for a, b in splits for c in LETTERS]
    return set(deletes + transposes + replaces + inserts)


def main() -> None:
    rows = list(csv.DictReader(NATIONAL.open(encoding="utf-8-sig")))
    print(f"national courses: {len(rows)}")

    # 1. national word frequency
    freq: Counter[str] = Counter()
    for r in rows:
        freq.update(words(r["Course Name"]))

    # 2. USYD subset (tidy columns)
    usyd = [r for r in rows if r["CRICOS Provider Code"] == USYD_PROVIDER]
    with OUT_USYD.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(COLUMNS.values()))
        w.writeheader()
        for r in usyd:
            w.writerow({tidy: r.get(src, "") for src, tidy in COLUMNS.items()})
    print(f"USYD course/award records: {len(usyd)} -> {OUT_USYD.name}")

    # 3. data-driven spelling flags on USYD names
    flags = []
    for r in usyd:
        name = r["Course Name"]
        for w_ in dict.fromkeys(words(name)):
            if freq[w_] > RARE_MAX:
                continue
            best = None
            for cand in edits1(w_):
                if freq.get(cand, 0) >= COMMON_MIN and (best is None or freq[cand] > freq[best]):
                    best = cand
            if best:
                flags.append(
                    {
                        "cricos_course_code": r["CRICOS Course Code"],
                        "course_name": name,
                        "suspect_word": w_,
                        "suggested_correction": best,
                        "suspect_freq": freq[w_],
                        "suggestion_freq": freq[best],
                    }
                )
    with OUT_FLAGS.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["cricos_course_code", "course_name", "suspect_word",
                        "suggested_correction", "suspect_freq", "suggestion_freq"],
        )
        w.writeheader()
        w.writerows(flags)
    print(f"spelling flags: {len(flags)} -> {OUT_FLAGS.name}")
    for fl in flags:
        print(f"   {fl['cricos_course_code']}: '{fl['suspect_word']}' -> "
              f"'{fl['suggested_correction']}' "
              f"(seen {fl['suspect_freq']} vs {fl['suggestion_freq']})")


if __name__ == "__main__":
    main()
