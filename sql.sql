-- =====================================================================
--  Loan Default — SQL Query Toolkit
--  SELECT / WHERE / ORDER BY / DISTINCT / Aggregates / GROUP BY / HAVING /
--  JOIN / Window Functions / CASE / COALESCE
--  Run against: loan_default_db (raw_loan_default, loan_default_clean)
-- =====================================================================
Show databases;
USE loan_default_db;

-- =====================================================================
-- 1. SELECT + WHERE — filter rows to inspect data quality problems
-- =====================================================================

-- Rows with a missing rate_of_interest (before cleaning)
SELECT ID, loan_amount, rate_of_interest, region
FROM raw_loan_default
WHERE rate_of_interest IS NULL;

-- Rows with an impossible LTV (data-entry outliers)
SELECT ID, LTV, property_value, loan_amount
FROM raw_loan_default
WHERE LTV > 150;

-- Rows with a negative or zero loan amount (should never happen)
SELECT ID, loan_amount, region
FROM raw_loan_default
WHERE loan_amount <= 0;

-- Rows with a known typo value
SELECT ID, Security_Type
FROM raw_loan_default
WHERE Security_Type = 'Indriect';


-- =====================================================================
-- 2. ORDER BY — sort to find extremes worth investigating
-- =====================================================================

-- Largest loans first
SELECT ID, loan_amount, region, status
FROM loan_default_clean
ORDER BY loan_amount DESC
LIMIT 20;

-- Lowest credit scores first (data validity spot-check: should be >= 300)
SELECT ID, credit_score, credit_score_band
FROM loan_default_clean
ORDER BY credit_score ASC
LIMIT 20;


-- =====================================================================
-- 3. DISTINCT — find every unique category (spot inconsistent spellings)
-- =====================================================================

SELECT DISTINCT region FROM raw_loan_default;
SELECT DISTINCT Security_Type FROM raw_loan_default;
SELECT DISTINCT Gender FROM raw_loan_default;
SELECT DISTINCT loan_purpose FROM raw_loan_default;

-- Count how many DISTINCT ID values exist vs. total rows (duplicate check)
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT ID) AS distinct_ids
FROM raw_loan_default;


-- =====================================================================
-- 4. Aggregates: COUNT, SUM, AVG, MIN, MAX
-- =====================================================================

SELECT
    COUNT(*)                       AS total_loans,
    SUM(loan_amount)               AS total_volume,
    AVG(loan_amount)               AS avg_loan_amount,
    MIN(loan_amount)               AS smallest_loan,
    MAX(loan_amount)               AS largest_loan,
    AVG(credit_score)              AS avg_credit_score,
    MIN(credit_score)              AS min_credit_score,
    MAX(credit_score)              AS max_credit_score
FROM loan_default_clean;


-- =====================================================================
-- 5. GROUP BY + HAVING — aggregate per category, then filter the groups
-- =====================================================================

-- Default rate per region
SELECT
    region,
    COUNT(*)                                    AS total_loans,
    SUM(status)                                  AS defaults,
    ROUND(SUM(status) / COUNT(*) * 100, 2)       AS default_rate_pct,
    ROUND(AVG(loan_amount), 0)                   AS avg_loan_amount
FROM loan_default_clean
GROUP BY region
ORDER BY default_rate_pct DESC;

-- HAVING: only show groups with more than 1,000 loans AND a default rate above 25%
SELECT
    loan_purpose,
    COUNT(*)                                     AS total_loans,
    ROUND(SUM(status) / COUNT(*) * 100, 2)        AS default_rate_pct
FROM loan_default_clean
GROUP BY loan_purpose
HAVING COUNT(*) > 1000 AND (SUM(status) / COUNT(*) * 100) > 25
ORDER BY default_rate_pct DESC;

-- HAVING to catch a data-quality issue: categories with suspiciously few rows
SELECT credit_type, COUNT(*) AS n
FROM loan_default_clean
GROUP BY credit_type
HAVING COUNT(*) < 100;


-- =====================================================================
-- 6. JOIN — combine raw vs. cleaned tables to audit what changed
-- =====================================================================

-- INNER JOIN: compare raw vs. cleaned LTV side by side for capped outliers
SELECT
    r.ID,
    r.LTV                    AS raw_ltv,
    c.ltv                    AS cleaned_ltv,
    c.ltv_outlier_capped
FROM raw_loan_default r
INNER JOIN loan_default_clean c ON r.ID = c.ID
WHERE c.ltv_outlier_capped = 1;

-- LEFT JOIN: confirm every raw row has a matching cleaned row (should return 0)
SELECT r.ID
FROM raw_loan_default r
LEFT JOIN loan_default_clean c ON r.ID = c.ID
WHERE c.ID IS NULL;

-- INNER JOIN: audit every imputed rate_of_interest against the raw NULL
SELECT
    r.ID,
    r.rate_of_interest        AS raw_value,
    c.rate_of_interest         AS imputed_value
FROM raw_loan_default r
INNER JOIN loan_default_clean c ON r.ID = c.ID
WHERE c.rate_of_interest_imputed = 1
ORDER BY r.ID
LIMIT 20;


-- =====================================================================
-- 7. Window Functions — ROW_NUMBER, RANK, SUM() OVER()
-- =====================================================================

-- ROW_NUMBER: identify duplicate loans by (loan_amount, region, credit_score)
-- combination — keep only the first occurrence
SELECT
    ID, region, loan_amount,
    (SELECT COUNT(*) FROM loan_default_clean t2
     WHERE t2.ID <= t1.ID) AS row_num
FROM loan_default_clean t1
ORDER BY ID;
SELECT
    ID, loan_amount,
    (SELECT COUNT(*) FROM loan_default_clean t2
     WHERE t2.loan_amount > t1.loan_amount) + 1 AS rank_by_amount
FROM loan_default_clean t1
ORDER BY rank_by_amount;
-- RANK: rank loans by amount within each region (ties share a rank)
SELECT
    ID, region, loan_amount,
    (SELECT COUNT(*) FROM loan_default_clean t2
     WHERE t2.region = t1.region
       AND t2.loan_amount > t1.loan_amount) + 1 AS rank_in_region
FROM loan_default_clean t1
ORDER BY region, rank_in_region;

-- SUM() OVER(): running total of loan volume ordered by ID (cumulative exposure)
SELECT
    ID, loan_amount,
    (SELECT SUM(t2.loan_amount) FROM loan_default_clean t2
     WHERE t2.ID <= t1.ID) AS running_total
FROM loan_default_clean t1
ORDER BY ID;
-- AVG() OVER(): compare each loan's amount to its region's average (no GROUP BY needed)
SELECT
    c.ID, c.region, c.loan_amount, r.region_avg,
    c.loan_amount - r.region_avg AS diff_from_region_avg
FROM loan_default_clean c
JOIN (
    SELECT region, AVG(loan_amount) AS region_avg
    FROM loan_default_clean
    GROUP BY region
) r ON c.region = r.region
ORDER BY diff_from_region_avg DESC;

-- =====================================================================
-- 8. CASE — conditional logic / recoding during cleaning
-- =====================================================================

-- Recreate the credit_score_band logic explicitly (used during cleaning)
SELECT
    ID, credit_score,
    CASE
        WHEN credit_score < 580 THEN 'Poor'
        WHEN credit_score < 670 THEN 'Fair'
        WHEN credit_score < 740 THEN 'Good'
        WHEN credit_score < 800 THEN 'Very Good'
        ELSE 'Exceptional'
    END AS credit_score_band
FROM loan_default_clean
LIMIT 20;

-- Flag risk tier using multiple conditions
SELECT
    ID, ltv, dtir1,
    CASE
        WHEN ltv > 95 OR dtir1 > 43 THEN 'High Risk'
        WHEN ltv > 80 OR dtir1 > 36 THEN 'Moderate Risk'
        ELSE 'Low Risk'
    END AS risk_tier
FROM loan_default_clean
LIMIT 20;


-- =====================================================================
-- 9. COALESCE — handle NULLs / provide fallback values
-- =====================================================================

-- Fallback text for any category that's still NULL/blank
SELECT
    ID,
    COALESCE(NULLIF(loan_purpose, ''), 'Unknown') AS loan_purpose_clean
FROM raw_loan_default
LIMIT 20;

-- Fallback numeric value: use property_value, or income*4 if missing, or 0 as last resort
SELECT
    ID,
    COALESCE(property_value, income * 4, 0) AS estimated_property_value
FROM raw_loan_default
LIMIT 20;

-- COALESCE inside an aggregate to avoid NULL skewing an AVG
SELECT
    region,
    AVG(COALESCE(dtir1, 0)) AS avg_dti_treating_null_as_zero,   -- for comparison only
    AVG(dtir1) AS avg_dti_ignoring_nulls                        -- AVG already skips NULLs
FROM raw_loan_default
GROUP BY region;


-- =====================================================================
-- 10. Everything combined — one realistic "cleaning audit" query
-- =====================================================================

SELECT
    c.region,c.credit_score_band,
    COUNT(*)                                                   AS total_loans,
    SUM(c.status)                                              AS defaults,
    ROUND(SUM(c.status) / COUNT(*) * 100, 2)                   AS default_rate_pct,
    ROUND(AVG(c.loan_amount), 0)                               AS avg_loan_amount
FROM loan_default_clean c
INNER JOIN raw_loan_default r ON r.ID = c.ID
WHERE c.loan_amount > 0
GROUP BY c.region, c.credit_score_band
HAVING COUNT(*) > 50
ORDER BY c.region, risk_rank_in_region;
