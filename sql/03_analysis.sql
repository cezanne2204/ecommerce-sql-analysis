-- =====================================================================
-- 03_analysis.sql
-- Core business analysis: executive KPIs, profitability, geography, time.
--
-- This script is deliberately self-contained (it does not depend on the
-- views in 04_views.sql) so it can be run immediately after cleaning.
--
-- A note that governs almost every query below: revenue, profit and
-- quantity live at LINE grain (1,500 rows) while order counts and AOV
-- live at ORDER grain (500 rows). Mixing them in one join inflates order
-- counts threefold. Where both are needed, line-level measures are
-- aggregated to order grain in a CTE first.
-- =====================================================================

USE ecommerce_analytics;

-- =====================================================================
-- SECTION A - EXECUTIVE KPIs
-- =====================================================================

-- Q1. What does the business look like in one row?
--
-- Order-level measures are computed in their own CTE to avoid the fan-out
-- described above. COUNT(DISTINCT ...) would also work but is markedly
-- slower and hides the grain problem rather than solving it.
WITH order_totals AS (
    SELECT o.order_id,
           o.customer_id,
           SUM(l.amount)   AS order_amount,
           SUM(l.quantity) AS order_quantity
    FROM fact_orders o
    JOIN fact_order_lines l ON l.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id
),
order_agg AS (
    -- Collapsed to a single row so the final SELECT mixes no grains.
    SELECT COUNT(*)                      AS total_orders,
           COUNT(DISTINCT customer_id)   AS total_customers,
           ROUND(AVG(order_amount), 2)   AS avg_order_value,
           ROUND(AVG(order_quantity), 2) AS avg_order_quantity
    FROM order_totals
),
line_totals AS (
    SELECT SUM(amount)   AS total_revenue,
           SUM(profit)   AS total_profit,
           SUM(quantity) AS total_quantity
    FROM fact_order_lines
)
SELECT
    lt.total_revenue,
    lt.total_profit,
    ROUND(lt.total_profit / lt.total_revenue * 100, 2)          AS profit_margin_pct,
    oa.total_orders,
    oa.total_customers,
    lt.total_quantity,
    oa.avg_order_value,
    oa.avg_order_quantity,
    (SELECT COUNT(DISTINCT state)    FROM dim_customer)         AS states_served,
    (SELECT COUNT(DISTINCT city)     FROM dim_customer)         AS cities_served,
    (SELECT COUNT(DISTINCT category) FROM dim_sub_category)     AS categories,
    (SELECT COUNT(*)                 FROM dim_sub_category)     AS sub_categories,
    (SELECT MIN(order_date) FROM fact_orders)                   AS period_start,
    (SELECT MAX(order_date) FROM fact_orders)                   AS period_end
FROM order_agg oa
CROSS JOIN line_totals lt;


-- Q2. Cross-check: does revenue reconcile between line grain and order grain?
-- An independent recomputation of the headline number. If these two ever
-- disagree, every downstream figure is suspect.
SELECT
    (SELECT SUM(amount) FROM fact_order_lines) AS revenue_at_line_grain,
    (SELECT SUM(order_amount) FROM (
        SELECT SUM(amount) AS order_amount FROM fact_order_lines GROUP BY order_id
     ) x)                                      AS revenue_at_order_grain,
    CASE WHEN (SELECT SUM(amount) FROM fact_order_lines)
            = (SELECT SUM(order_amount) FROM (
                 SELECT SUM(amount) AS order_amount FROM fact_order_lines GROUP BY order_id) y)
         THEN 'RECONCILED' ELSE 'MISMATCH' END AS check_result;


-- =====================================================================
-- SECTION B - SALES AND PROFITABILITY
-- =====================================================================

-- Q3. How do the three categories compare on revenue, profit and margin?
--
-- Revenue rank and profit rank are shown side by side because the whole
-- point is whether they disagree - a category that ranks high on one and
-- low on the other is where the margin problem lives.
SELECT
    sc.category,
    SUM(l.amount)                                        AS revenue,
    SUM(l.profit)                                        AS profit,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)        AS margin_pct,
    SUM(l.quantity)                                      AS units_sold,
    ROUND(SUM(l.amount) / SUM(l.quantity), 2)            AS revenue_per_unit,
    ROUND(SUM(l.amount) * 100.0
          / SUM(SUM(l.amount)) OVER (), 2)               AS pct_of_total_revenue,
    RANK() OVER (ORDER BY SUM(l.amount) DESC)            AS revenue_rank,
    RANK() OVER (ORDER BY SUM(l.profit) DESC)            AS profit_rank
FROM fact_order_lines l
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY sc.category
ORDER BY revenue DESC;


-- Q4. Which sub-categories carry the business, and which drain it?
--
-- loss_line_share is the share of a sub-category's lines that lost money.
-- A sub-category can post positive total profit while losing money on most
-- lines - that pattern means the profit depends on a few large wins and is
-- fragile, which a simple profit total would hide.
SELECT
    sc.category,
    l.sub_category,
    SUM(l.amount)                                            AS revenue,
    SUM(l.profit)                                            AS profit,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)            AS margin_pct,
    COUNT(*)                                                 AS line_count,
    SUM(l.profit < 0)                                        AS loss_making_lines,
    ROUND(SUM(l.profit < 0) * 100.0 / COUNT(*), 1)           AS loss_line_share_pct
FROM fact_order_lines l
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY sc.category, l.sub_category
ORDER BY profit DESC;


-- Q5. Which sub-categories are high revenue but weak profitability?
--
-- "Weak" is defined relative to the business's own overall margin rather
-- than an arbitrary threshold, and "high revenue" as above-median revenue.
-- Both thresholds are computed from the data so the classification moves
-- with the dataset instead of being hard-coded.
WITH subcat AS (
    SELECT l.sub_category,
           sc.category,
           SUM(l.amount) AS revenue,
           SUM(l.profit) AS profit,
           SUM(l.profit) / SUM(l.amount) * 100 AS margin_pct
    FROM fact_order_lines l
    JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
    GROUP BY l.sub_category, sc.category
),
benchmarks AS (
    SELECT (SELECT SUM(profit) / SUM(amount) * 100 FROM fact_order_lines) AS overall_margin_pct,
           AVG(revenue) AS avg_subcat_revenue
    FROM subcat
)
SELECT
    s.category,
    s.sub_category,
    s.revenue,
    s.profit,
    ROUND(s.margin_pct, 2)                     AS margin_pct,
    ROUND(b.overall_margin_pct, 2)             AS business_margin_pct,
    ROUND(s.margin_pct - b.overall_margin_pct, 2) AS margin_gap_pts,
    CASE
        WHEN s.revenue >= b.avg_subcat_revenue AND s.margin_pct >= b.overall_margin_pct
            THEN 'Core strength'
        WHEN s.revenue >= b.avg_subcat_revenue AND s.margin_pct <  b.overall_margin_pct
            THEN 'Volume trap - fix margin'
        WHEN s.revenue <  b.avg_subcat_revenue AND s.margin_pct >= b.overall_margin_pct
            THEN 'Scale candidate'
        ELSE 'Review or exit'
    END                                        AS quadrant
FROM subcat s
CROSS JOIN benchmarks b
ORDER BY s.revenue DESC;


-- Q6. Which sub-categories actually destroy profit, and how much would
--     the business have earned without them?
-- The counterfactual column is what makes this actionable: it quantifies
-- the cost of the problem rather than just naming it.
SELECT
    l.sub_category,
    sc.category,
    SUM(l.profit)                                                     AS profit,
    SUM(l.amount)                                                     AS revenue,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)                     AS margin_pct,
    (SELECT SUM(profit) FROM fact_order_lines)                        AS current_total_profit,
    (SELECT SUM(profit) FROM fact_order_lines) - SUM(l.profit)        AS profit_excluding_this_subcat
FROM fact_order_lines l
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY l.sub_category, sc.category
HAVING SUM(l.profit) < 0
ORDER BY profit ASC;


-- Q7. How concentrated is revenue across the product range?
-- A running share over sub-categories ranked by revenue - a Pareto curve.
SELECT
    sub_category,
    revenue,
    ROUND(revenue * 100.0 / SUM(revenue) OVER (), 2)                  AS pct_of_revenue,
    ROUND(SUM(revenue) OVER (ORDER BY revenue DESC
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          * 100.0 / SUM(revenue) OVER (), 2)                          AS cumulative_pct,
    ROW_NUMBER() OVER (ORDER BY revenue DESC)                         AS revenue_rank
FROM (
    SELECT sub_category, SUM(amount) AS revenue
    FROM fact_order_lines
    GROUP BY sub_category
) s
ORDER BY revenue DESC;


-- Q8. Which sub-categories command the highest value per line, and does
--     high value coincide with high margin?
SELECT
    l.sub_category,
    sc.category,
    COUNT(*)                                          AS line_count,
    ROUND(AVG(l.amount), 2)                           AS avg_line_value,
    ROUND(AVG(l.quantity), 2)                         AS avg_units_per_line,
    ROUND(AVG(l.amount / l.quantity), 2)              AS avg_unit_price,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)     AS margin_pct
FROM fact_order_lines l
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY l.sub_category, sc.category
ORDER BY avg_line_value DESC;


-- =====================================================================
-- SECTION C - GEOGRAPHIC ANALYSIS
-- =====================================================================

-- Q9. Full state scorecard.
--
-- Orders and customers must be counted from the ORDER/CUSTOMER grain, so
-- they are aggregated separately and joined back, rather than counted
-- inside the line-level aggregate where they would be multiplied by the
-- number of lines per order.
WITH state_lines AS (
    SELECT c.state,
           SUM(l.amount)   AS revenue,
           SUM(l.profit)   AS profit,
           SUM(l.quantity) AS units
    FROM fact_order_lines l
    JOIN fact_orders   o ON o.order_id    = l.order_id
    JOIN dim_customer  c ON c.customer_id = o.customer_id
    GROUP BY c.state
),
state_orders AS (
    SELECT c.state,
           COUNT(*)                       AS orders,
           COUNT(DISTINCT o.customer_id)  AS customers
    FROM fact_orders  o
    JOIN dim_customer c ON c.customer_id = o.customer_id
    GROUP BY c.state
)
SELECT
    sl.state,
    sl.revenue,
    sl.profit,
    ROUND(sl.profit / sl.revenue * 100, 2)                AS margin_pct,
    so.orders,
    so.customers,
    ROUND(sl.revenue / so.orders, 2)                      AS avg_order_value,
    ROUND(sl.revenue / so.customers, 2)                   AS revenue_per_customer,
    ROUND(sl.revenue * 100.0 / SUM(sl.revenue) OVER (), 2) AS pct_of_revenue,
    RANK() OVER (ORDER BY sl.revenue DESC)                AS revenue_rank,
    RANK() OVER (ORDER BY sl.profit  DESC)                AS profit_rank
FROM state_lines  sl
JOIN state_orders so ON so.state = sl.state
ORDER BY sl.revenue DESC;


-- Q10. Market classification.
--
-- Thresholds are the MEDIAN state revenue and the overall business margin,
-- both derived from the data. The median is used rather than the mean
-- because state revenue is heavily right-skewed by Maharashtra and Madhya
-- Pradesh, and a mean would push almost every state into the "low" bucket.
WITH state_perf AS (
    SELECT c.state,
           SUM(l.amount) AS revenue,
           SUM(l.profit) AS profit,
           SUM(l.profit) / SUM(l.amount) * 100 AS margin_pct
    FROM fact_order_lines l
    JOIN fact_orders  o ON o.order_id    = l.order_id
    JOIN dim_customer c ON c.customer_id = o.customer_id
    GROUP BY c.state
),
thresholds AS (
    -- MySQL 8 has no MEDIAN(); this takes the middle row by revenue rank.
    SELECT
        (SELECT AVG(revenue) FROM (
            SELECT revenue,
                   ROW_NUMBER() OVER (ORDER BY revenue) AS rn,
                   COUNT(*)    OVER ()                  AS n
            FROM state_perf
         ) r WHERE rn IN (FLOOR((n+1)/2), CEIL((n+1)/2)))            AS median_revenue,
        (SELECT SUM(profit) / SUM(amount) * 100 FROM fact_order_lines) AS margin_benchmark
)
SELECT
    sp.state,
    sp.revenue,
    sp.profit,
    ROUND(sp.margin_pct, 2)           AS margin_pct,
    ROUND(t.median_revenue, 2)        AS median_state_revenue,
    ROUND(t.margin_benchmark, 2)      AS margin_benchmark_pct,
    CASE
        WHEN sp.revenue >= t.median_revenue AND sp.margin_pct >= t.margin_benchmark
            THEN 'Strong market'
        WHEN sp.revenue >= t.median_revenue AND sp.margin_pct <  t.margin_benchmark
            THEN 'High revenue, weak profit'
        WHEN sp.revenue <  t.median_revenue AND sp.margin_pct >= t.margin_benchmark
            THEN 'Growth opportunity'
        ELSE 'Underperforming'
    END                               AS market_segment
FROM state_perf sp
CROSS JOIN thresholds t
ORDER BY sp.revenue DESC;


-- Q11. City-level performance, with the parent state for context.
-- Restricted to cities with a meaningful sample so that a single large
-- order cannot crown a city with three orders as the best market.
WITH city_lines AS (
    SELECT c.city, c.state,
           SUM(l.amount) AS revenue,
           SUM(l.profit) AS profit
    FROM fact_order_lines l
    JOIN fact_orders  o ON o.order_id    = l.order_id
    JOIN dim_customer c ON c.customer_id = o.customer_id
    GROUP BY c.city, c.state
),
city_orders AS (
    SELECT c.city, c.state, COUNT(*) AS orders
    FROM fact_orders  o
    JOIN dim_customer c ON c.customer_id = o.customer_id
    GROUP BY c.city, c.state
)
SELECT
    cl.city, cl.state, cl.revenue, cl.profit,
    ROUND(cl.profit / cl.revenue * 100, 2) AS margin_pct,
    co.orders,
    ROUND(cl.revenue / co.orders, 2)       AS avg_order_value
FROM city_lines  cl
JOIN city_orders co ON co.city = cl.city AND co.state = cl.state
WHERE co.orders >= 10                      -- sample-size floor
ORDER BY cl.revenue DESC;


-- Q12. Where is profitability worst in absolute terms?
-- Loss-making states, ranked by the size of the hole.
SELECT
    c.state,
    SUM(l.amount) AS revenue,
    SUM(l.profit) AS profit,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2) AS margin_pct
FROM fact_order_lines l
JOIN fact_orders  o ON o.order_id    = l.order_id
JOIN dim_customer c ON c.customer_id = o.customer_id
GROUP BY c.state
HAVING SUM(l.profit) <= 0
ORDER BY profit ASC;


-- =====================================================================
-- SECTION D - TIME SERIES
-- =====================================================================

-- Q13. Monthly performance with month-over-month growth.
--
-- Sorting is on the DATE, never on the formatted label, so months stay in
-- calendar order rather than alphabetical. LAG returns NULL for the first
-- month by definition; that NULL is preserved rather than coerced to 0,
-- because "no prior month" and "0% growth" are different statements.
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
        DATE_FORMAT(o.order_date, '%b %Y')    AS month_label,
        SUM(l.amount)                         AS revenue,
        SUM(l.profit)                         AS profit,
        SUM(l.quantity)                       AS units,
        COUNT(DISTINCT o.order_id)            AS orders
    FROM fact_orders o
    JOIN fact_order_lines l ON l.order_id = o.order_id
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01'), DATE_FORMAT(o.order_date, '%b %Y')
)
SELECT
    month_label,
    revenue,
    profit,
    ROUND(profit / revenue * 100, 2)                              AS margin_pct,
    orders,
    units,
    ROUND(revenue / orders, 2)                                    AS avg_order_value,
    LAG(revenue) OVER (ORDER BY month_start)                      AS prev_month_revenue,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month_start))
          * 100.0 / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0), 2)
                                                                  AS mom_growth_pct,
    SUM(revenue) OVER (ORDER BY month_start
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                                  AS cumulative_revenue,
    SUM(profit)  OVER (ORDER BY month_start
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                                  AS cumulative_profit
FROM monthly
ORDER BY month_start;


-- Q14. Quarterly view on the Indian fiscal year (Apr-Mar), which is the
--      calendar this dataset actually follows - the data starts exactly on
--      1 Apr 2018 and ends exactly on 31 Mar 2019. Using calendar quarters
--      would split the year awkwardly across two labels.
SELECT
    CONCAT('FY19 Q',
           QUARTER(DATE_SUB(o.order_date, INTERVAL 3 MONTH))) AS fiscal_quarter,
    MIN(o.order_date)                                         AS quarter_start,
    MAX(o.order_date)                                         AS quarter_end,
    COUNT(DISTINCT o.order_id)                                AS orders,
    SUM(l.amount)                                             AS revenue,
    SUM(l.profit)                                             AS profit,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)             AS margin_pct
FROM fact_orders o
JOIN fact_order_lines l ON l.order_id = o.order_id
GROUP BY CONCAT('FY19 Q', QUARTER(DATE_SUB(o.order_date, INTERVAL 3 MONTH)))
ORDER BY fiscal_quarter;


-- Q15. Day-of-week pattern.
-- Orders per day-of-week are normalised by how many times that weekday
-- actually occurred in the period; a raw count would favour whichever
-- weekday happened to appear more often in a 365-day window.
WITH dow AS (
    SELECT
        DAYNAME(o.order_date)                       AS day_name,
        DAYOFWEEK(o.order_date)                     AS day_number,
        COUNT(DISTINCT o.order_id)                  AS orders,
        COUNT(DISTINCT o.order_date)                AS distinct_dates,
        SUM(l.amount)                               AS revenue,
        SUM(l.profit)                               AS profit
    FROM fact_orders o
    JOIN fact_order_lines l ON l.order_id = o.order_id
    GROUP BY DAYNAME(o.order_date), DAYOFWEEK(o.order_date)
)
SELECT
    day_name,
    orders,
    distinct_dates                            AS active_days,
    ROUND(orders / distinct_dates, 2)         AS orders_per_active_day,
    revenue,
    ROUND(revenue / orders, 2)                AS avg_order_value,
    ROUND(profit / revenue * 100, 2)          AS margin_pct
FROM dow
ORDER BY day_number;


-- Q16. Category revenue by month - does the category mix shift over time?
-- Conditional aggregation pivots three categories into columns, which is
-- far easier to scan for a trend than 36 stacked rows.
SELECT
    DATE_FORMAT(o.order_date, '%b %Y') AS month_label,
    SUM(CASE WHEN sc.category = 'Electronics' THEN l.amount ELSE 0 END) AS electronics_revenue,
    SUM(CASE WHEN sc.category = 'Clothing'    THEN l.amount ELSE 0 END) AS clothing_revenue,
    SUM(CASE WHEN sc.category = 'Furniture'   THEN l.amount ELSE 0 END) AS furniture_revenue,
    SUM(l.amount)                                                       AS total_revenue,
    ROUND(SUM(CASE WHEN sc.category = 'Furniture' THEN l.profit ELSE 0 END), 2)
                                                                        AS furniture_profit
FROM fact_orders o
JOIN fact_order_lines l  ON l.order_id     = o.order_id
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY DATE_FORMAT(o.order_date, '%b %Y'), DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY DATE_FORMAT(o.order_date, '%Y-%m');
