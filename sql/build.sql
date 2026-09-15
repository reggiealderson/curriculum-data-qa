-- Build the database and run every QA check.
-- Usage (from the repo root):   sqlite3 cricos_qa.db < sql/build.sql
.read sql/01_schema.sql
.read sql/02_load.sql
.read sql/03_qa_checks.sql
