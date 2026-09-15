#!/usr/bin/env python3
"""
Cross-source reconciliation input: match USYD's CRICOS course registrations
against the courses USYD publishes on its own website.

  CRICOS  (data/cricos_usyd_courses.csv)  = what USYD is registered to offer
  Website (public courses sitemap)        = what USYD advertises

Outputs:
  data/usyd_website_courses.csv            (course slugs + inferred names, from sitemap)
  data/reconciliation_candidates.csv       (CRICOS -> website: AQF CRICOS courses
                                            with no confident website match)
  data/reconciliation_candidates_web.csv   (website -> CRICOS: website courses with
                                            no confident CRICOS match)

Both directions are CANDIDATE lists a person must adjudicate, not error lists.
Note the asymmetry: CRICOS registers only courses offered to INTERNATIONAL
(student-visa) students, so a domestic-only website course legitimately has no
CRICOS entry. The fuzzy match is also imperfect (slug quirks, single-token
names, specialisation sub-pages), which is itself a finding: matching two systems
by name is fragile — a shared identifier or crosswalk is the real fix.
"""
from __future__ import annotations

import csv
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
USYD_CRICOS = ROOT / "data" / "cricos_usyd_courses.csv"
OUT_WEB = ROOT / "data" / "usyd_website_courses.csv"
OUT_CAND = ROOT / "data" / "reconciliation_candidates.csv"
OUT_CAND_WEB = ROOT / "data" / "reconciliation_candidates_web.csv"

SITEMAP = "https://www.sydney.edu.au/courses/sitemap.xml"
USER_AGENT = "reggie-alderson-portfolio-scraper (contact fromrussiawithreg@gmail.com)"
MATCH_THRESHOLD = 0.5  # below this Jaccard = no confident match

STOP = {"of", "in", "the", "and", "a", "with", "for"}


def norm(s: str) -> frozenset[str]:
    s = re.sub(r"[^a-z0-9 ]", " ", s.lower())
    return frozenset(t for t in s.split() if t and t not in STOP)


def fetch_website_courses():
    req = urllib.request.Request(SITEMAP, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=40) as resp:
        xml = resp.read().decode("utf-8", "replace")
    locs = re.findall(r"<loc>\s*(.*?)\s*</loc>", xml, re.S)
    seen, out = set(), []
    for u in locs:
        m = re.search(r"/courses/courses/[a-z]{2}/([a-z0-9-]+)\.html", u)
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            out.append({"slug": m.group(1),
                        "inferred_name": m.group(1).replace("-", " "),
                        "url": u})
    return out


def main() -> None:
    web = fetch_website_courses()
    with OUT_WEB.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["slug", "inferred_name", "url"])
        w.writeheader()
        w.writerows(web)
    print(f"website course pages: {len(web)} -> {OUT_WEB.name}")

    web_tokens = [(c["slug"], norm(c["inferred_name"])) for c in web]
    cricos = list(csv.DictReader(USYD_CRICOS.open(encoding="utf-8")))

    candidates = []
    for r in cricos:
        if r["course_level"] == "Non AQF Award":   # exchange/foundation/etc: not comparable
            continue
        t = norm(r["course_name"])
        best_slug, best_j = "", 0.0
        for slug, wt in web_tokens:
            if not t or not wt:
                continue
            j = len(t & wt) / len(t | wt)
            if j > best_j:
                best_j, best_slug = j, slug
        if best_j < MATCH_THRESHOLD:
            candidates.append({
                "cricos_course_code": r["cricos_course_code"],
                "course_name": r["course_name"],
                "course_level": r["course_level"],
                "best_website_match": best_slug,
                "match_score": round(best_j, 2),
            })

    with OUT_CAND.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["cricos_course_code", "course_name",
                                          "course_level", "best_website_match", "match_score"])
        w.writeheader()
        w.writerows(candidates)
    print(f"CRICOS->website candidates (AQF, no confident match): {len(candidates)} -> {OUT_CAND.name}")

    # Reverse direction: website courses with no confident CRICOS match.
    cricos_tokens = [(r["course_name"], norm(r["course_name"])) for r in cricos]
    web_candidates = []
    for c in web:
        t = norm(c["inferred_name"])
        best_name, best_j = "", 0.0
        for name, ct in cricos_tokens:
            if not t or not ct:
                continue
            j = len(t & ct) / len(t | ct)
            if j > best_j:
                best_j, best_name = j, name
        if best_j < MATCH_THRESHOLD:
            # Light heuristic: short professional certificates are typically
            # domestic/CPD and not expected in CRICOS.
            note = ("professional certificate (likely domestic/CPD)"
                    if c["slug"].startswith("sydney-professional-certificate") else "")
            web_candidates.append({
                "slug": c["slug"],
                "inferred_name": c["inferred_name"],
                "best_cricos_match": best_name,
                "match_score": round(best_j, 2),
                "note": note,
            })

    with OUT_CAND_WEB.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["slug", "inferred_name",
                                          "best_cricos_match", "match_score", "note"])
        w.writeheader()
        w.writerows(web_candidates)
    print(f"website->CRICOS candidates (no confident match): {len(web_candidates)} -> {OUT_CAND_WEB.name}")


if __name__ == "__main__":
    main()
