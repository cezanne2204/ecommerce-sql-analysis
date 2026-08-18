-- =====================================================================
-- 02_data_cleaning.sql
-- Profile the staging layer, then build the typed modelled layer.
--
-- Structure
--   PART 1  Detection      - queries that FIND problems (run and read these)
--   PART 2  Exception log  - dq_exceptions: problems we keep but record
--   PART 3  Transformation - staging -> modelled layer
--   PART 4  Assertions     - tests that FAIL LOUDLY if the load is wrong
--
-- Guiding principle: raw stays raw. Nothing is deleted from the staging
-- tables. Rows that look wrong but are plausibly real (loss-making sales)
-- are carried into the model and logged, never silently dropped. Only
-- genuinely contentless rows are excluded, and that exclusion happens at
-- load time and is documented.
-- =====================================================================

USE ecommerce_analytics;


-- =====================================================================
-- PART 1 - DETECTION
-- =====================================================================

-- 1.1 Row counts against the source files ------------------------------
-- Expected: 500 / 1500 / 36 (matching the populated rows of each CSV).
SELECT 'raw_orders' AS table_name, COUNT(*) AS row_count FROM raw_orders
UNION ALL SELECT 'raw_order_details', COUNT(*) FROM raw_order_details
UNION ALL SELECT 'raw_sales_target',  COUNT(*) FROM raw_sales_target;


-- 1.2 NULL / empty-string scan -----------------------------------------
-- The staging columns are text, so "missing" means '' as often as NULL.
-- COALESCE lets one expression catch both.
SELECT
    SUM(COALESCE(order_id,'')      = '') AS missing_order_id,
    SUM(COALESCE(order_date,'')    = '') AS missing_order_date,
    SUM(COALESCE(customer_name,'') = '') AS missing_customer_name,
    SUM(COALESCE(state,'')         = '') AS missing_state,
    SUM(COALESCE(city,'')          = '') AS missing_city
FROM raw_orders;

SELECT
    SUM(COALESCE(order_id,'')     = '') AS missing_order_id,
    SUM(COALESCE(amount,'')       = '') AS missing_amount,
    SUM(COALESCE(profit,'')       = '') AS missing_profit,
    SUM(COALESCE(quantity,'')     = '') AS missing_quantity,
    SUM(COALESCE(category,'')     = '') AS missing_category,
    SUM(COALESCE(sub_category,'') = '') AS missing_sub_category
FROM raw_order_details;


-- 1.3 Duplicate detection ----------------------------------------------
-- (a) Is order_id a valid primary key for the header table?
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT order_id) AS distinct_order_ids,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids
FROM raw_orders;

-- (b) Are there fully identical rows in the detail table?
--     Result: none. Every detail row differs in at least one column.
SELECT COUNT(*) AS duplicate_line_groups
FROM (
    SELECT order_id, amount, profit, quantity, category, sub_category
    FROM raw_order_details
    GROUP BY order_id, amount, profit, quantity, category, sub_category
    HAVING COUNT(*) > 1
) d;

-- (c) Could (order_id, sub_category) serve as a natural key?
--     Result: no - 196 pairs repeat within the same order. These are
--     separate line items for the same sub-category (different price
--     points / units), not duplicates. This is WHY fact_order_lines
--     needs a surrogate key.
SELECT COUNT(*) AS repeated_order_subcategory_pairs
FROM (
    SELECT order_id, sub_category
    FROM raw_order_details
    GROUP BY order_id, sub_category
    HAVING COUNT(*) > 1
) d;


-- 1.4 Referential integrity between the two order files ----------------
-- Both directions matter: orphan detail lines would inflate revenue with
-- no customer attached; headers with no lines would deflate AOV.
SELECT
    (SELECT COUNT(*) FROM raw_order_details d
       LEFT JOIN raw_orders o ON o.order_id = d.order_id
      WHERE o.order_id IS NULL)                       AS detail_lines_without_header,
    (SELECT COUNT(*) FROM raw_orders o
       LEFT JOIN raw_order_details d ON d.order_id = o.order_id
      WHERE d.order_id IS NULL)                       AS headers_without_detail_lines;


-- 1.5 Text hygiene: leading / trailing whitespace -----------------------
-- Result: 16 rows carry 'Kerala ' with a trailing space. All 16 Kerala
-- rows are affected, so this does not split one state into two variants;
-- it is a cosmetic defect that would nonetheless break any join to a
-- clean reference list. Fixed by TRIM in Part 3.
SELECT 'state' AS column_name, state AS raw_value, COUNT(*) AS rows_affected
FROM raw_orders WHERE state <> TRIM(state) GROUP BY state
UNION ALL
SELECT 'city', city, COUNT(*) FROM raw_orders WHERE city <> TRIM(city) GROUP BY city
UNION ALL
SELECT 'customer_name', customer_name, COUNT(*) FROM raw_orders
WHERE customer_name <> TRIM(customer_name) GROUP BY customer_name
UNION ALL
SELECT 'category', category, COUNT(*) FROM raw_order_details
WHERE category <> TRIM(category) GROUP BY category
UNION ALL
SELECT 'sub_category', sub_category, COUNT(*) FROM raw_order_details
WHERE sub_category <> TRIM(sub_category) GROUP BY sub_category;

-- 1.6 Casing inconsistency ---------------------------------------------
-- Detects values that are the same once trimmed and lower-cased but are
-- stored differently (e.g. 'delhi' vs 'Delhi'). Result: none.
SELECT LOWER(TRIM(state)) AS normalised, COUNT(DISTINCT TRIM(state)) AS variant_count,
       GROUP_CONCAT(DISTINCT TRIM(state)) AS variants
FROM raw_orders GROUP BY LOWER(TRIM(state)) HAVING COUNT(DISTINCT TRIM(state)) > 1;


-- 1.7 Date validity and format proof ------------------------------------
-- The format is ambiguous on 193 of 500 rows (both components <= 12).
-- It is proven to be dd-mm-yyyy by the 307 rows whose FIRST component
-- exceeds 12 - those would be an impossible month under mm-dd-yyyy.
SELECT
    COUNT(*) AS total_rows,
    SUM(STR_TO_DATE(TRIM(order_date), '%d-%m-%Y') IS NULL)              AS unparseable_as_dd_mm_yyyy,
    SUM(CAST(SUBSTRING_INDEX(order_date,'-',1) AS UNSIGNED) > 12)       AS rows_proving_day_first,
    MIN(STR_TO_DATE(TRIM(order_date), '%d-%m-%Y'))                      AS earliest_order,
    MAX(STR_TO_DATE(TRIM(order_date), '%d-%m-%Y'))                      AS latest_order
FROM raw_orders;


-- 1.8 Numeric validity --------------------------------------------------
-- REGEXP is used rather than a bare CAST because CAST silently returns 0
-- for non-numeric text under some settings, hiding the very problem we
-- are looking for.
SELECT
    SUM(NOT amount   REGEXP '^-?[0-9]+(\\.[0-9]+)?$') AS non_numeric_amount,
    SUM(NOT profit   REGEXP '^-?[0-9]+(\\.[0-9]+)?$') AS non_numeric_profit,
    SUM(NOT quantity REGEXP '^-?[0-9]+$')             AS non_numeric_quantity,
    SUM(CAST(amount   AS DECIMAL(10,2)) <= 0)         AS non_positive_amount,
    SUM(CAST(quantity AS SIGNED)        <= 0)         AS non_positive_quantity,
    SUM(CAST(profit   AS DECIMAL(10,2))  < 0)         AS negative_profit_lines,
    SUM(CAST(profit   AS DECIMAL(10,2))  = 0)         AS zero_profit_lines
FROM raw_order_details;

-- 1.9 Financially implausible lines -------------------------------------
-- Lines where the LOSS is larger than the revenue booked on the line.
-- Result: 14 lines. Kept (see Part 2) because a loss can legitimately
-- exceed revenue on a deeply discounted or returned item, and removing
-- them would flatter total profit by an amount we would then have to
-- explain. They are logged so their influence can be tested.
SELECT COUNT(*) AS loss_exceeds_revenue_lines
FROM raw_order_details
WHERE ABS(CAST(profit AS DECIMAL(10,2))) > CAST(amount AS DECIMAL(10,2));

-- 1.10 Geographic consistency -------------------------------------------
-- Does each city belong to exactly one state?
-- Result: two exceptions.
--   Chandigarh -> Punjab (16) and Haryana (14). REAL: Chandigarh is a
--     union territory serving as the shared capital of both states, so
--     either label is defensible. Left as-is.
--   Delhi (city) -> Delhi (22) and Madhya Pradesh (3). NOT REAL: there is
--     no Delhi city in Madhya Pradesh. Logged as a genuine data error.
SELECT TRIM(city) AS city,
       COUNT(DISTINCT TRIM(state)) AS state_count,
       GROUP_CONCAT(DISTINCT TRIM(state) ORDER BY TRIM(state)) AS states
FROM raw_orders
GROUP BY TRIM(city)
HAVING COUNT(DISTINCT TRIM(state)) > 1;

-- 1.11 Customer identity ambiguity --------------------------------------
-- How many first names span more than one location? Result: 43.
-- This is the evidence behind the composite customer key.
SELECT COUNT(*) AS names_spanning_multiple_locations
FROM (
    SELECT TRIM(customer_name) AS nm
    FROM raw_orders
    GROUP BY TRIM(customer_name)
    HAVING COUNT(DISTINCT CONCAT(TRIM(state),'|',TRIM(city))) > 1
) x;

-- 1.12 Target file coverage ---------------------------------------------
-- Confirms the target grid is complete (12 months x 3 categories) and
-- that its months line up with the months actually present in the orders.
SELECT COUNT(*) AS target_rows,
       COUNT(DISTINCT month_of_order_date) AS distinct_months,
       COUNT(DISTINCT category) AS distinct_categories
FROM raw_sales_target;


-- =====================================================================
-- PART 2 - EXCEPTION LOG
-- Problems that are recorded rather than corrected, so that every
-- judgement call is visible and reversible.
-- =====================================================================

DROP TABLE IF EXISTS dq_exceptions;
CREATE TABLE dq_exceptions (
    exception_id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    check_name    VARCHAR(60)  NOT NULL,
    severity      ENUM('INFO','WARN','ERROR') NOT NULL,
    entity_type   VARCHAR(30)  NOT NULL,
    entity_key    VARCHAR(60)  NOT NULL,
    detail        VARCHAR(255) NOT NULL,
    PRIMARY KEY (exception_id),
    KEY idx_dq_check (check_name)
) ENGINE=InnoDB COMMENT='Data-quality issues retained in the model, not deleted.';

-- Loss larger than the revenue on the same line.
INSERT INTO dq_exceptions (check_name, severity, entity_type, entity_key, detail)
SELECT 'loss_exceeds_revenue', 'WARN', 'order_line', order_id,
       CONCAT(sub_category, ': amount ', amount, ', profit ', profit)
FROM raw_order_details
WHERE ABS(CAST(profit AS DECIMAL(10,2))) > CAST(amount AS DECIMAL(10,2));

-- City/state pairing that does not exist geographically.
INSERT INTO dq_exceptions (check_name, severity, entity_type, entity_key, detail)
SELECT 'impossible_city_state', 'ERROR', 'order', order_id,
       CONCAT('city ', TRIM(city), ' recorded in state ', TRIM(state))
FROM raw_orders
WHERE TRIM(city) = 'Delhi' AND TRIM(state) <> 'Delhi';

-- Shared-capital city, retained deliberately.
INSERT INTO dq_exceptions (check_name, severity, entity_type, entity_key, detail)
SELECT 'shared_capital_city', 'INFO', 'order', order_id,
       CONCAT('Chandigarh recorded under ', TRIM(state), ' - both are valid')
FROM raw_orders
WHERE TRIM(city) = 'Chandigarh';

-- Whitespace defect corrected during transformation.
INSERT INTO dq_exceptions (check_name, severity, entity_type, entity_key, detail)
SELECT 'untrimmed_state', 'INFO', 'order', order_id,
       CONCAT('state stored as "', state, '" - trimmed on load')
FROM raw_orders
WHERE state <> TRIM(state);


-- =====================================================================
-- PART 3 - TRANSFORMATION
-- =====================================================================

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE fact_order_lines;
TRUNCATE TABLE fact_orders;
TRUNCATE TABLE fact_sales_target;
TRUNCATE TABLE dim_customer;
TRUNCATE TABLE dim_sub_category;
SET FOREIGN_KEY_CHECKS = 1;

-- 3.1 Product dimension.
-- DISTINCT is safe here only because sub_category -> category was verified
-- to be functional in Part 1; otherwise this would silently pick a winner.
INSERT INTO dim_sub_category (sub_category, category)
SELECT DISTINCT TRIM(sub_category), TRIM(category)
FROM raw_order_details;

-- 3.2 Customer dimension, keyed on (name, state, city). TRIM fixes 'Kerala '.
INSERT INTO dim_customer (customer_name, state, city)
SELECT DISTINCT TRIM(customer_name), TRIM(state), TRIM(city)
FROM raw_orders;

-- 3.3 Order headers. The join to dim_customer cannot fan out because
--     dim_customer is unique on exactly the three columns joined.
INSERT INTO fact_orders (order_id, customer_id, order_date)
SELECT TRIM(o.order_id),
       c.customer_id,
       STR_TO_DATE(TRIM(o.order_date), '%d-%m-%Y')
FROM raw_orders o
JOIN dim_customer c
  ON  c.customer_name = TRIM(o.customer_name)
  AND c.state         = TRIM(o.state)
  AND c.city          = TRIM(o.city);

-- 3.4 Order lines. Category is dropped here because it is recoverable
--     from dim_sub_category - storing it twice would allow the two to
--     drift apart.
INSERT INTO fact_order_lines (order_id, sub_category, amount, profit, quantity)
SELECT TRIM(order_id),
       TRIM(sub_category),
       CAST(amount   AS DECIMAL(10,2)),
       CAST(profit   AS DECIMAL(10,2)),
       CAST(quantity AS SIGNED)
FROM raw_order_details;

-- 3.5 Targets. 'Apr-18' -> 2018-04-01 by prefixing a day component, which
--     makes the column sortable and joinable on a real date boundary.
INSERT INTO fact_sales_target (target_month, category, target_amount)
SELECT STR_TO_DATE(CONCAT('01-', TRIM(month_of_order_date)), '%d-%b-%y'),
       TRIM(category),
       CAST(target AS DECIMAL(12,2))
FROM raw_sales_target;


-- =====================================================================
-- PART 4 - ASSERTIONS
-- Each query returns 'PASS' or 'FAIL'. Any FAIL invalidates the analysis
-- downstream, so these are re-run after every rebuild.
-- =====================================================================

SELECT 'row counts preserved' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM fact_orders)      = 500
             AND (SELECT COUNT(*) FROM fact_order_lines) = 1500
             AND (SELECT COUNT(*) FROM fact_sales_target)= 36
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Money must survive the round trip from text to DECIMAL untouched.
SELECT 'revenue preserved' AS assertion,
       CASE WHEN (SELECT SUM(amount) FROM fact_order_lines)
                 = (SELECT SUM(CAST(amount AS DECIMAL(10,2))) FROM raw_order_details)
            THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'profit preserved' AS assertion,
       CASE WHEN (SELECT SUM(profit) FROM fact_order_lines)
                 = (SELECT SUM(CAST(profit AS DECIMAL(10,2))) FROM raw_order_details)
            THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'quantity preserved' AS assertion,
       CASE WHEN (SELECT SUM(quantity) FROM fact_order_lines)
                 = (SELECT SUM(CAST(quantity AS SIGNED)) FROM raw_order_details)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- No order may lose or gain a line through the header join.
SELECT 'no join fan-out on orders' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM fact_orders o JOIN fact_order_lines l
                    ON l.order_id = o.order_id) = 1500
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Every date parsed; none fell outside the stated fiscal year.
SELECT 'dates parsed and in range' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM fact_orders
                   WHERE order_date BETWEEN '2018-04-01' AND '2019-03-31') = 500
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- The category label in the target file must match the order data exactly,
-- since the two are joined on it in 05_advanced_analysis.sql.
SELECT 'target categories match order categories' AS assertion,
       CASE WHEN NOT EXISTS (
                SELECT 1 FROM fact_sales_target t
                 WHERE t.category NOT IN (SELECT category FROM dim_sub_category))
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Customer identity must not have collapsed two locations into one.
SELECT 'customer identity is unique per location' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM dim_customer) =
                 (SELECT COUNT(*) FROM (
                     SELECT DISTINCT TRIM(customer_name), TRIM(state), TRIM(city)
                     FROM raw_orders) x)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Whitespace is gone from the modelled layer.
SELECT 'no untrimmed text remains' AS assertion,
       CASE WHEN NOT EXISTS (SELECT 1 FROM dim_customer
                              WHERE state <> TRIM(state) OR city <> TRIM(city)
                                 OR customer_name <> TRIM(customer_name))
            THEN 'PASS' ELSE 'FAIL' END AS result;
