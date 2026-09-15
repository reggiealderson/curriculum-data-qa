#!/usr/bin/env bash
# Build the SQLite database from the committed CSVs and run every QA check.
# No network access and no Python required — pure sqlite3 over checked-in data.
#   ./run.sh            print the QA report
#   ./run.sh report.txt also write it to a file
set -euo pipefail
cd "$(dirname "$0")"
command -v sqlite3 >/dev/null || { echo "sqlite3 is required but not found." >&2; exit 1; }
DB=cricos_qa.db
rm -f "$DB"
if [ "${1:-}" != "" ]; then sqlite3 "$DB" < sql/build.sql | tee "$1"; echo "Report written to $1";
else sqlite3 "$DB" < sql/build.sql; fi
