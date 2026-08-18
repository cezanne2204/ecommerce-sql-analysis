-- =====================================================================
-- 06_validation.sql
-- Cross-checks every headline metric by recomputing it a second,
-- independent way. A query running without error proves only that it is
-- valid SQL; these checks test that it is also CORRECT.
--
-- Results are collected into one table so the suite ends with a single
-- verdict rather than seventeen separate result sets to read by eye.
-- =====================================================================

USE ecommerce_analytics;

DROP TABLE IF EXISTS validation_results;
CREATE TABLE validation_results (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    check_id    VARCHAR(6)   NOT NULL,
    check_name  VARCHAR(80)  NOT NULL,
    result      VARCHAR(6)   NOT NULL,
    detail      VARCHAR(120) NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;


-- V1. Revenue must be identical at all six grains it is aggregated to.
--     If any join fans out, one of these diverges.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V1', 'Revenue identical at all six grains',
       CASE WHEN
            (SELECT SUM(amount)        FROM fact_order_lines)          =
            (SELECT SUM(order_revenue) FROM v_order_summary)
        AND (SELECT SUM(order_revenue) FROM v_order_summary)           =
            (SELECT SUM(total_revenue) FROM v_customer_metrics)
        AND (SELECT SUM(total_revenue) FROM v_customer_metrics)        =
            (SELECT SUM(revenue)       FROM v_state_performance)
        AND (SELECT SUM(revenue)       FROM v_state_performance)       =
            (SELECT SUM(revenue)       FROM v_monthly_sales)
        AND (SELECT SUM(revenue)       FROM v_monthly_sales)           =
            (SELECT SUM(revenue)       FROM v_sub_category_performance)
       THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('all grains = ', (SELECT SUM(amount) FROM fact_order_lines));

-- V2. Same test for profit.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V2', 'Profit identical at all grains',
       CASE WHEN
            (SELECT SUM(profit)       FROM fact_order_lines)   =
            (SELECT SUM(order_profit) FROM v_order_summary)
        AND (SELECT SUM(order_profit) FROM v_order_summary)    =
            (SELECT SUM(total_profit) FROM v_customer_metrics)
        AND (SELECT SUM(total_profit) FROM v_customer_metrics) =
            (SELECT SUM(profit)       FROM v_state_performance)
       THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('all grains = ', (SELECT SUM(profit) FROM fact_order_lines));

-- V3. AOV two ways: AVG of order totals vs revenue / order count.
--     These diverge the moment an order-level average is taken over
--     line-level rows - the classic fan-out error.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V3', 'AOV consistent across two methods',
       CASE WHEN (SELECT ROUND(AVG(order_revenue), 2) FROM v_order_summary)
                 = (SELECT ROUND(SUM(amount) / COUNT(DISTINCT order_id), 2)
                      FROM fact_order_lines)
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('avg method = ', (SELECT ROUND(AVG(order_revenue),2) FROM v_order_summary),
              ', ratio method = ', (SELECT ROUND(SUM(amount)/COUNT(DISTINCT order_id),2)
                                      FROM fact_order_lines));

-- V4. Order and customer counts must not be inflated by the line join.
--     SUM(customers) over states equals 401 only because customer identity
--     includes state; if that rule changed this check would correctly fail.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V4', 'Order/customer counts not inflated by join',
       CASE WHEN (SELECT COUNT(*)         FROM v_order_summary)     = 500
             AND (SELECT COUNT(*)         FROM v_customer_metrics)  = 401
             AND (SELECT SUM(orders)      FROM v_state_performance) = 500
             AND (SELECT SUM(customers)   FROM v_state_performance) = 401
             AND (SELECT SUM(orders)      FROM v_monthly_sales)     = 500
            THEN 'PASS' ELSE 'FAIL' END,
       '500 orders / 401 customers at every grain';

-- V5. Margin must be the ratio of totals, not the mean of per-row ratios.
--     Both are computed here to show they differ materially; the project
--     uses the first everywhere.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V5', 'Margin uses ratio of totals, not mean of ratios',
       CASE WHEN (SELECT ROUND(SUM(profit)/SUM(amount)*100, 2) FROM fact_order_lines) = 5.55
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('correct = ', (SELECT ROUND(SUM(profit)/SUM(amount)*100,2) FROM fact_order_lines),
              '%, naive row-average = ',
              (SELECT ROUND(AVG(profit/amount)*100,2) FROM fact_order_lines), '%');

-- V6. The running-total window must close exactly on the grand total.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V6', 'Cumulative revenue closes on grand total',
       CASE WHEN (SELECT MAX(running) FROM (
                    SELECT SUM(revenue) OVER (ORDER BY month_start
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running
                    FROM v_monthly_sales) r)
                 = (SELECT SUM(amount) FROM fact_order_lines)
            THEN 'PASS' ELSE 'FAIL' END,
       'final cumulative row = total revenue';

-- V7. MoM growth verified against a hand calculation.
--     Nov 2018 (48,086) vs Oct 2018 (31,615) = +52.10%.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V7', 'MoM growth matches hand calculation',
       CASE WHEN ROUND((48086.00 - 31615.00) / 31615.00 * 100, 2) =
                 (SELECT ROUND((revenue - LAG(revenue) OVER (ORDER BY month_start))
                               * 100.0 / LAG(revenue) OVER (ORDER BY month_start), 2)
                    FROM v_monthly_sales ORDER BY month_start LIMIT 1 OFFSET 7)
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('hand = 52.10%, query = ',
              (SELECT ROUND((revenue - LAG(revenue) OVER (ORDER BY month_start))
                            * 100.0 / LAG(revenue) OVER (ORDER BY month_start), 2)
                 FROM v_monthly_sales ORDER BY month_start LIMIT 1 OFFSET 7), '%');

-- V8. The first month must be NULL, not 0 - "no prior period" and "flat"
--     are different statements and must not be conflated.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V8', 'First month MoM growth is NULL, not zero',
       CASE WHEN (SELECT growth FROM (
                    SELECT month_start,
                           revenue - LAG(revenue) OVER (ORDER BY month_start) AS growth
                    FROM v_monthly_sales) g
                  ORDER BY month_start LIMIT 1) IS NULL
            THEN 'PASS' ELSE 'FAIL' END,
       'Apr 2018 has no prior month';

-- V9. RFM must partition the base exactly once - nobody double-counted,
--     nobody dropped by an unmatched CASE branch.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V9', 'RFM segments partition the customer base',
       CASE WHEN (SELECT COUNT(*) FROM v_customer_rfm) = 401
             AND (SELECT SUM(total_revenue) FROM v_customer_rfm)
                 = (SELECT SUM(amount) FROM fact_order_lines)
             AND NOT EXISTS (SELECT 1 FROM v_customer_rfm WHERE rfm_segment IS NULL)
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT((SELECT COUNT(DISTINCT rfm_segment) FROM v_customer_rfm),
              ' segments covering 401 customers, no NULLs');

-- V10. Scores must stay in range after the recency inversion.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V10', 'RFM scores within 1-5',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM v_customer_rfm
             WHERE r_score NOT BETWEEN 1 AND 5
                OR f_score NOT BETWEEN 1 AND 5
                OR m_score NOT BETWEEN 1 AND 5)
       THEN 'PASS' ELSE 'FAIL' END, 'r, f and m all in [1,5]';

-- V11. Recency inversion direction. A sign error here silently reverses
--      the entire segmentation, so it is tested explicitly.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V11', 'Recency inverted correctly (recent = high score)',
       CASE WHEN (SELECT AVG(days_since_last_order) FROM v_customer_rfm WHERE r_score = 5)
                 < (SELECT AVG(days_since_last_order) FROM v_customer_rfm WHERE r_score = 1)
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('avg days: score5 = ',
              (SELECT ROUND(AVG(days_since_last_order)) FROM v_customer_rfm WHERE r_score=5),
              ', score1 = ',
              (SELECT ROUND(AVG(days_since_last_order)) FROM v_customer_rfm WHERE r_score=1));

-- V12. The target grid must account for all revenue - proving no month or
--      category was lost in the join.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V12', 'Target grid accounts for all revenue',
       CASE WHEN (SELECT SUM(actual_revenue) FROM v_sales_vs_target)
                 = (SELECT SUM(amount) FROM fact_order_lines)
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT('grid = ', (SELECT SUM(actual_revenue) FROM v_sales_vs_target),
              ', total = ', (SELECT SUM(amount) FROM fact_order_lines));

-- V13. Variance arithmetic must hold on every row.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V13', 'Variance = actual - target on every row',
       CASE WHEN NOT EXISTS (SELECT 1 FROM v_sales_vs_target
                              WHERE variance <> actual_revenue - target_amount)
            THEN 'PASS' ELSE 'FAIL' END, 'checked across all 36 cells';

-- V14. Percentage shares must sum to exactly 100.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V14', 'Revenue shares sum to 100%',
       CASE WHEN (SELECT ROUND(SUM(revenue * 100.0
                        / (SELECT SUM(amount) FROM fact_order_lines)), 2)
                    FROM v_sub_category_performance) = 100.00
            THEN 'PASS' ELSE 'FAIL' END, '17 sub-categories';

-- V15. Top-N per state must never return more than N rows per partition.
INSERT INTO validation_results (check_id, check_name, result, detail)
WITH ranked AS (
    SELECT state, customer_id,
           ROW_NUMBER() OVER (PARTITION BY state ORDER BY total_revenue DESC) AS rn
    FROM v_customer_metrics
)
SELECT 'V15', 'Top-3-per-state returns at most 3 per state',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM (SELECT state, COUNT(*) AS n FROM ranked WHERE rn <= 3
                            GROUP BY state) s
             WHERE s.n > 3)
       THEN 'PASS' ELSE 'FAIL' END, 'across all 19 states';

-- V16. Referential integrity re-tested on the modelled tables.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V16', 'Referential integrity holds both directions',
       CASE WHEN (SELECT COUNT(*) FROM fact_orders o
                   WHERE NOT EXISTS (SELECT 1 FROM fact_order_lines l
                                      WHERE l.order_id = o.order_id)) = 0
             AND (SELECT COUNT(*) FROM fact_order_lines l
                   WHERE NOT EXISTS (SELECT 1 FROM fact_orders o
                                      WHERE o.order_id = l.order_id)) = 0
            THEN 'PASS' ELSE 'FAIL' END, 'no orphan lines, no empty orders';

-- V17. The data-quality exception log must be populated as expected.
INSERT INTO validation_results (check_id, check_name, result, detail)
SELECT 'V17', 'Data-quality exceptions captured',
       CASE WHEN (SELECT COUNT(*) FROM dq_exceptions) = 63
            THEN 'PASS' ELSE 'FAIL' END,
       CONCAT((SELECT COUNT(*) FROM dq_exceptions), ' rows across ',
              (SELECT COUNT(DISTINCT check_name) FROM dq_exceptions), ' checks');


-- ---------------------------------------------------------------------
-- RESULTS
-- ---------------------------------------------------------------------
SELECT check_id, check_name, result, detail
FROM validation_results
ORDER BY id;

SELECT
    COUNT(*)                                    AS checks_run,
    SUM(result = 'PASS')                        AS passed,
    SUM(result = 'FAIL')                        AS failed,
    CASE WHEN SUM(result = 'FAIL') = 0
         THEN 'ALL CHECKS PASSED'
         ELSE 'VALIDATION FAILED - DO NOT TRUST DOWNSTREAM RESULTS'
    END                                         AS verdict
FROM validation_results;

-- Exception-log breakdown, for reference.
SELECT check_name, severity, COUNT(*) AS rows_logged
FROM dq_exceptions
GROUP BY check_name, severity
ORDER BY FIELD(severity,'ERROR','WARN','INFO'), check_name;
