-- TB_TURNINFO validation report queries
-- Usage examples:
--   sqlite3 nav_database.db ".read backend/src/turninfo_report.sql"
--   psql "$DATABASE_URL" -f backend/src/turninfo_report.sql

-- ---------------------------------------------------------------------
-- 1) Summary: one-row-per-check counts
-- ---------------------------------------------------------------------

SELECT 'total_rows' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO;

SELECT 'transition_rows(prev+next not null)' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO
WHERE PREV_LINK_ID IS NOT NULL
  AND NEXT_LINK_ID IS NOT NULL;

SELECT 'dictionary_rows(prev/next null)' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO
WHERE PREV_LINK_ID IS NULL
   OR NEXT_LINK_ID IS NULL;

SELECT 'orphan_prev_link' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO t
LEFT JOIN links p ON p.id = t.PREV_LINK_ID
WHERE t.PREV_LINK_ID IS NOT NULL
  AND t.NEXT_LINK_ID IS NOT NULL
  AND p.id IS NULL;

SELECT 'orphan_next_link' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO t
LEFT JOIN links n ON n.id = t.NEXT_LINK_ID
WHERE t.PREV_LINK_ID IS NOT NULL
  AND t.NEXT_LINK_ID IS NOT NULL
  AND n.id IS NULL;

SELECT 'junction_mismatch(prev.end_node != next.start_node)' AS check_name,
       COUNT(*) AS issue_count
FROM TB_TURNINFO t
JOIN links p ON p.id = t.PREV_LINK_ID
JOIN links n ON n.id = t.NEXT_LINK_ID
WHERE t.PREV_LINK_ID IS NOT NULL
  AND t.NEXT_LINK_ID IS NOT NULL
  AND p.end_node <> n.start_node;

SELECT 'duplicate_transition_pairs' AS check_name,
       COALESCE(SUM(d.cnt - 1), 0) AS issue_count
FROM (
  SELECT PREV_LINK_ID, NEXT_LINK_ID, COUNT(*) AS cnt
  FROM TB_TURNINFO
  WHERE PREV_LINK_ID IS NOT NULL
    AND NEXT_LINK_ID IS NOT NULL
  GROUP BY PREV_LINK_ID, NEXT_LINK_ID
  HAVING COUNT(*) > 1
) d;

SELECT 'invalid_turn_type_code' AS check_name, COUNT(*) AS issue_count
FROM TB_TURNINFO
WHERE TURN_TYPE NOT IN ('001', '002', '003', '011', '012', '101', '102', '103');

-- ---------------------------------------------------------------------
-- 2) Detail: rows that should be fixed
-- ---------------------------------------------------------------------

-- 2-1) Rows with orphan links
SELECT t.*
FROM TB_TURNINFO t
LEFT JOIN links p ON p.id = t.PREV_LINK_ID
LEFT JOIN links n ON n.id = t.NEXT_LINK_ID
WHERE t.PREV_LINK_ID IS NOT NULL
  AND t.NEXT_LINK_ID IS NOT NULL
  AND (p.id IS NULL OR n.id IS NULL)
ORDER BY t.ID;

-- 2-2) Rows whose transition does not pass through the same junction node
SELECT t.ID,
       t.PREV_LINK_ID,
       t.NEXT_LINK_ID,
       t.TURN_TYPE,
       p.start_node AS prev_start_node,
       p.end_node AS prev_end_node,
       n.start_node AS next_start_node,
       n.end_node AS next_end_node
FROM TB_TURNINFO t
JOIN links p ON p.id = t.PREV_LINK_ID
JOIN links n ON n.id = t.NEXT_LINK_ID
WHERE t.PREV_LINK_ID IS NOT NULL
  AND t.NEXT_LINK_ID IS NOT NULL
  AND p.end_node <> n.start_node
ORDER BY t.ID;

-- 2-3) Duplicate transition pairs (all rows)
SELECT t.*
FROM TB_TURNINFO t
JOIN (
  SELECT PREV_LINK_ID, NEXT_LINK_ID
  FROM TB_TURNINFO
  WHERE PREV_LINK_ID IS NOT NULL
    AND NEXT_LINK_ID IS NOT NULL
  GROUP BY PREV_LINK_ID, NEXT_LINK_ID
  HAVING COUNT(*) > 1
) d
  ON d.PREV_LINK_ID = t.PREV_LINK_ID
 AND d.NEXT_LINK_ID = t.NEXT_LINK_ID
ORDER BY t.PREV_LINK_ID, t.NEXT_LINK_ID, t.ID;

-- 2-4) Invalid TURN_TYPE values
SELECT t.*
FROM TB_TURNINFO t
WHERE t.TURN_TYPE NOT IN ('001', '002', '003', '011', '012', '101', '102', '103')
ORDER BY t.ID;

-- 2-5) Dictionary rows (metadata-only rows, not transition constraints)
SELECT t.*
FROM TB_TURNINFO t
WHERE t.PREV_LINK_ID IS NULL
   OR t.NEXT_LINK_ID IS NULL
ORDER BY t.ID;
