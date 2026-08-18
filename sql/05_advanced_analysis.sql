-- =====================================================================
-- 05_advanced_analysis.sql
-- Customer analytics, RFM, rankings and target attainment.
-- Depends on the views created in 04_views.sql.
-- =====================================================================

USE ecommerce_analytics;

-- =====================================================================
-- SECTION E - CUSTOMER BASE STRUCTURE
-- =====================================================================

-- Q17. How much of the business rests on customers who never came back?
--
-- The window is a single fiscal year, so "one-time" means one purchase
-- within these 12 months - it is not proof the customer never returned.
-- That caveat is why this is framed as concentration risk rather than
-- churn.
SELECT
    customer_type,
    COUNT(*)                                                        AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)              AS pct_of_customers,
    SUM(total_revenue)                                              AS revenue,
    ROUND(SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER (), 1) AS pct_of_revenue,
    SUM(total_profit)                                               AS profit,
    ROUND(SUM(total_profit) / SUM(total_revenue) * 100, 2)          AS margin_pct,
    ROUND(AVG(total_revenue), 2)                                    AS avg_customer_spend,
    ROUND(AVG(avg_order_value), 2)                                  AS avg_order_value
FROM v_customer_metrics
GROUP BY customer_type;


-- Q18. Purchase frequency distribution, with the revenue each tier carries.
SELECT
    order_count                                                     AS orders_placed,
    COUNT(*)                                                        AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)              AS pct_of_customers,
    SUM(total_revenue)                                              AS revenue,
    ROUND(SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER (), 1) AS pct_of_revenue,
    ROUND(AVG(total_revenue), 2)                                    AS avg_spend
FROM v_customer_metrics
GROUP BY order_count
ORDER BY order_count;


-- Q19. Customer revenue concentration - how few customers make the first
--      half of the money?
--
-- A running total ordered by descending spend, then the smallest set whose
-- cumulative share reaches 50%. The outer query returns the boundary rows
-- so the answer is a count, not a chart to eyeball.
WITH ranked AS (
    SELECT
        customer_id, customer_name, state, total_revenue,
        ROW_NUMBER() OVER (ORDER BY total_revenue DESC)             AS revenue_rank,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)      AS running_revenue,
        SUM(total_revenue) OVER ()                                  AS total_revenue_all
    FROM v_customer_metrics
),
with_pct AS (
    SELECT ranked.*,
           ROUND(running_revenue * 100.0 / total_revenue_all, 2) AS cumulative_pct
    FROM ranked
)
SELECT
    MIN(CASE WHEN cumulative_pct >= 50 THEN revenue_rank END)       AS customers_for_50pct_revenue,
    MIN(CASE WHEN cumulative_pct >= 80 THEN revenue_rank END)       AS customers_for_80pct_revenue,
    MAX(revenue_rank)                                               AS total_customers,
    ROUND(MIN(CASE WHEN cumulative_pct >= 50 THEN revenue_rank END)
          * 100.0 / MAX(revenue_rank), 1)                           AS pct_of_base_for_half_revenue
FROM with_pct;


-- Q20. Top customers, with their profit contribution shown alongside.
-- Revenue rank and profit rank are both displayed because the interesting
-- customers are the ones where the two disagree.
SELECT
    RANK() OVER (ORDER BY total_revenue DESC)          AS revenue_rank,
    customer_name, city, state,
    order_count, total_revenue, total_profit,
    ROUND(total_profit / total_revenue * 100, 2)       AS margin_pct,
    RANK() OVER (ORDER BY total_profit DESC)           AS profit_rank
FROM v_customer_metrics
ORDER BY total_revenue DESC
LIMIT 15;


-- Q21. Which customers spend heavily but earn the business nothing?
--
-- Restricted to above-average spenders so the list is commercially
-- meaningful rather than a list of tiny loss-making orders. The
-- subquery threshold is computed from the data.
SELECT
    customer_name, city, state,
    order_count, total_revenue, total_profit,
    ROUND(total_profit / total_revenue * 100, 2)       AS margin_pct,
    ROUND((SELECT AVG(total_revenue) FROM v_customer_metrics), 2) AS avg_customer_spend
FROM v_customer_metrics
WHERE total_revenue > (SELECT AVG(total_revenue) FROM v_customer_metrics)
  AND total_profit  <= 0
ORDER BY total_revenue DESC
LIMIT 15;


-- Q22. Customers above average spend - how large is that group and what
--      share of revenue does it hold?
WITH benchmark AS (
    SELECT AVG(total_revenue) AS avg_spend FROM v_customer_metrics
)
SELECT
    CASE WHEN cm.total_revenue > b.avg_spend
         THEN 'Above average' ELSE 'At or below average' END        AS spend_group,
    COUNT(*)                                                        AS customers,
    ROUND(AVG(cm.total_revenue), 2)                                 AS avg_spend,
    SUM(cm.total_revenue)                                           AS revenue,
    ROUND(SUM(cm.total_revenue) * 100.0
          / SUM(SUM(cm.total_revenue)) OVER (), 1)                  AS pct_of_revenue
FROM v_customer_metrics cm
CROSS JOIN benchmark b
GROUP BY CASE WHEN cm.total_revenue > b.avg_spend
              THEN 'Above average' ELSE 'At or below average' END;


-- =====================================================================
-- SECTION F - RFM SEGMENTATION
-- =====================================================================

-- Q23. Why frequency is NOT scored with NTILE.
--
-- This query is the evidence for the design decision documented in
-- 04_views.sql. It applies NTILE(5) to order_count and shows that
-- customers with an IDENTICAL number of orders are handed different
-- scores, purely because NTILE fills buckets by row position when the
-- underlying value is heavily tied.
SELECT
    order_count                                    AS actual_orders,
    COUNT(*)                                       AS customers,
    MIN(ntile_score)                               AS lowest_ntile_score,
    MAX(ntile_score)                               AS highest_ntile_score,
    CASE WHEN MIN(ntile_score) <> MAX(ntile_score)
         THEN 'SPLIT - identical behaviour scored differently'
         ELSE 'consistent' END                     AS ntile_verdict
FROM (
    SELECT order_count, NTILE(5) OVER (ORDER BY order_count ASC) AS ntile_score
    FROM v_customer_metrics
) x
GROUP BY order_count
ORDER BY order_count;


-- Q24. Segment scorecard - the commercial shape of the customer base.
SELECT
    rfm_segment,
    COUNT(*)                                                        AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)              AS pct_of_customers,
    SUM(total_revenue)                                              AS revenue,
    ROUND(SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER (), 1) AS pct_of_revenue,
    SUM(total_profit)                                               AS profit,
    ROUND(SUM(total_profit) / SUM(total_revenue) * 100, 2)          AS margin_pct,
    ROUND(AVG(total_revenue), 0)                                    AS avg_spend,
    ROUND(AVG(order_count), 2)                                      AS avg_orders,
    ROUND(AVG(days_since_last_order), 0)                            AS avg_days_since_order
FROM v_customer_rfm
GROUP BY rfm_segment
ORDER BY revenue DESC;


-- Q25. The At Risk list - high spenders who have gone quiet.
-- This is the segment with the clearest, most immediate commercial action,
-- so it is output as a working list rather than a summary.
SELECT
    customer_name, city, state,
    total_revenue, total_profit, order_count,
    last_order_date,
    days_since_last_order,
    rfm_cell
FROM v_customer_rfm
WHERE rfm_segment = 'At Risk'
ORDER BY total_revenue DESC
LIMIT 15;


-- Q26. Do repeat customers spend more or less on their later orders?
--
-- LAG/LEAD need at least two orders, so this is restricted to the 70
-- repeat customers. With a maximum of four orders per customer the result
-- is directional, not a robust trend - stated plainly rather than
-- presented as a growth curve.
WITH ordered_orders AS (
    SELECT
        os.customer_id,
        os.order_date,
        os.order_revenue,
        ROW_NUMBER() OVER (PARTITION BY os.customer_id ORDER BY os.order_date) AS seq,
        COUNT(*)    OVER (PARTITION BY os.customer_id)                         AS lifetime_orders,
        LAG(os.order_revenue)  OVER (PARTITION BY os.customer_id ORDER BY os.order_date) AS prev_order_revenue,
        LEAD(os.order_date)    OVER (PARTITION BY os.customer_id ORDER BY os.order_date) AS next_order_date
    FROM v_order_summary os
)
SELECT
    seq                                                     AS order_sequence,
    COUNT(*)                                                AS orders_at_this_sequence,
    ROUND(AVG(order_revenue), 2)                            AS avg_order_value,
    ROUND(AVG(order_revenue - prev_order_revenue), 2)       AS avg_change_vs_previous,
    ROUND(AVG(DATEDIFF(next_order_date, order_date)), 1)    AS avg_days_to_next_order
FROM ordered_orders
WHERE lifetime_orders > 1
GROUP BY seq
ORDER BY seq;


-- Q27. First versus latest purchase for repeat customers - who is growing
--      and who is fading?
WITH bounds AS (
    SELECT
        os.customer_id,
        MIN(os.order_date) AS first_date,
        MAX(os.order_date) AS last_date,
        COUNT(*)           AS orders
    FROM v_order_summary os
    GROUP BY os.customer_id
    HAVING COUNT(*) > 1
),
values_at_bounds AS (
    SELECT
        b.customer_id, b.orders,
        b.first_date, b.last_date,
        MAX(CASE WHEN os.order_date = b.first_date THEN os.order_revenue END) AS first_order_value,
        MAX(CASE WHEN os.order_date = b.last_date  THEN os.order_revenue END) AS last_order_value
    FROM bounds b
    JOIN v_order_summary os ON os.customer_id = b.customer_id
    GROUP BY b.customer_id, b.orders, b.first_date, b.last_date
)
SELECT
    CASE
        WHEN last_order_value > first_order_value * 1.20 THEN 'Growing (>20% up)'
        WHEN last_order_value < first_order_value * 0.80 THEN 'Declining (>20% down)'
        ELSE 'Stable (within +/-20%)'
    END                                                   AS spend_trend,
    COUNT(*)                                              AS customers,
    ROUND(AVG(first_order_value), 2)                      AS avg_first_order,
    ROUND(AVG(last_order_value), 2)                       AS avg_latest_order,
    ROUND(AVG(DATEDIFF(last_date, first_date)), 0)        AS avg_days_between
FROM values_at_bounds
GROUP BY CASE
        WHEN last_order_value > first_order_value * 1.20 THEN 'Growing (>20% up)'
        WHEN last_order_value < first_order_value * 0.80 THEN 'Declining (>20% down)'
        ELSE 'Stable (within +/-20%)'
    END
ORDER BY customers DESC;


-- Q28. Top 3 customers in every state.
-- ROW_NUMBER rather than RANK: the requirement is exactly three names per
-- state for an account-management list, and RANK would return four rows
-- on a tie.
WITH ranked AS (
    SELECT
        state, customer_name, city, order_count, total_revenue, total_profit,
        ROW_NUMBER() OVER (PARTITION BY state ORDER BY total_revenue DESC) AS rn
    FROM v_customer_metrics
)
SELECT state, rn AS rank_in_state, customer_name, city,
       order_count, total_revenue, total_profit
FROM ranked
WHERE rn <= 3
ORDER BY state, rn;


-- =====================================================================
-- SECTION G - PRODUCT RANKING
-- =====================================================================

-- Q29. Top 3 sub-categories by profit within each category, showing the
--      three ranking functions side by side so the difference is explicit.
--      DENSE_RANK is the filter because ties should both be kept here.
WITH ranked AS (
    SELECT
        category, sub_category, revenue, profit, margin_pct,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit DESC) AS row_num,
        RANK()       OVER (PARTITION BY category ORDER BY profit DESC) AS rank_pos,
        DENSE_RANK() OVER (PARTITION BY category ORDER BY profit DESC) AS dense_pos
    FROM v_sub_category_performance
)
SELECT category, sub_category, revenue, profit, margin_pct,
       row_num, rank_pos, dense_pos
FROM ranked
WHERE dense_pos <= 3
ORDER BY category, dense_pos;


-- Q30. Profitability percentiles across sub-categories.
-- NTILE(4) is appropriate here - 17 sub-categories with well-spread
-- margins, unlike the tied frequency data in Q23.
SELECT
    sub_category, category, revenue, profit, margin_pct,
    NTILE(4) OVER (ORDER BY margin_pct DESC)          AS margin_quartile,
    CASE NTILE(4) OVER (ORDER BY margin_pct DESC)
         WHEN 1 THEN 'Q1 - most profitable'
         WHEN 2 THEN 'Q2'
         WHEN 3 THEN 'Q3'
         ELSE        'Q4 - least profitable'
    END                                               AS quartile_label
FROM v_sub_category_performance
ORDER BY margin_pct DESC;


-- =====================================================================
-- SECTION H - TARGET ATTAINMENT
-- =====================================================================

-- Q31. Target attainment by category across the full year.
SELECT
    category,
    SUM(target_amount)                                          AS total_target,
    SUM(actual_revenue)                                         AS total_actual,
    SUM(actual_revenue) - SUM(target_amount)                    AS variance,
    ROUND((SUM(actual_revenue) - SUM(target_amount))
          / SUM(target_amount) * 100, 2)                        AS variance_pct,
    ROUND(SUM(actual_revenue) / SUM(target_amount) * 100, 2)    AS achievement_pct,
    SUM(status = 'Hit')                                         AS months_hit,
    SUM(status = 'Miss')                                        AS months_missed
FROM v_sales_vs_target
GROUP BY category
ORDER BY achievement_pct DESC;


-- Q32. Month-by-month attainment for the business as a whole.
SELECT
    month_label,
    SUM(target_amount)                                          AS target,
    SUM(actual_revenue)                                         AS actual,
    SUM(actual_revenue) - SUM(target_amount)                    AS variance,
    ROUND(SUM(actual_revenue) / SUM(target_amount) * 100, 2)    AS achievement_pct,
    SUM(status = 'Hit')                                         AS categories_hit_of_3
FROM v_sales_vs_target
GROUP BY target_month, month_label
ORDER BY target_month;


-- Q33. The full category x month grid - where exactly are the gaps?
SELECT
    month_label, category, target_amount, actual_revenue,
    variance, achievement_pct, status
FROM v_sales_vs_target
ORDER BY target_month, category;


-- Q34. Is attainment improving or deteriorating?
--
-- Compares the first half of the fiscal year (Apr-Sep) with the second
-- (Oct-Mar). A half-on-half comparison is used rather than a month-level
-- trend line because 12 points per category is too few to fit a trend
-- that anyone should act on.
WITH halves AS (
    SELECT
        category,
        CASE WHEN target_month < '2018-10-01' THEN 'H1 Apr-Sep' ELSE 'H2 Oct-Mar' END AS half,
        SUM(target_amount)  AS target,
        SUM(actual_revenue) AS actual
    FROM v_sales_vs_target
    GROUP BY category,
             CASE WHEN target_month < '2018-10-01' THEN 'H1 Apr-Sep' ELSE 'H2 Oct-Mar' END
)
SELECT
    category,
    MAX(CASE WHEN half = 'H1 Apr-Sep' THEN ROUND(actual / target * 100, 2) END) AS h1_achievement_pct,
    MAX(CASE WHEN half = 'H2 Oct-Mar' THEN ROUND(actual / target * 100, 2) END) AS h2_achievement_pct,
    ROUND(MAX(CASE WHEN half = 'H2 Oct-Mar' THEN actual / target * 100 END)
        - MAX(CASE WHEN half = 'H1 Apr-Sep' THEN actual / target * 100 END), 2) AS change_in_pts,
    CASE WHEN MAX(CASE WHEN half = 'H2 Oct-Mar' THEN actual / target END)
            > MAX(CASE WHEN half = 'H1 Apr-Sep' THEN actual / target END)
         THEN 'Improving' ELSE 'Deteriorating' END                              AS direction
FROM halves
GROUP BY category
ORDER BY change_in_pts DESC;


-- Q35. Does hitting the revenue target actually produce profit?
--
-- The targets are revenue-only. This joins attainment to the profit
-- actually earned in the same month/category to test whether the target
-- is steering the business somewhere worth going.
SELECT
    status                                                      AS target_status,
    COUNT(*)                                                    AS month_category_cells,
    SUM(actual_revenue)                                         AS revenue,
    SUM(actual_profit)                                          AS profit,
    ROUND(SUM(actual_profit) / SUM(actual_revenue) * 100, 2)    AS margin_pct,
    ROUND(AVG(achievement_pct), 2)                              AS avg_achievement_pct
FROM v_sales_vs_target
GROUP BY status;


-- =====================================================================
-- SECTION I - ORDER COMPOSITION
--
-- Three findings elsewhere in this project point the same direction:
-- Tables has the highest line value and the worst margin (Q4/Q8), Sunday
-- has the highest AOV and nearly the worst margin (Q15), and Saree turns
-- over heavily at 0.66% (Q4). Each suggests that BIGGER ORDERS ARE WORSE
-- ORDERS. The queries below test that directly rather than leaving it as
-- three coincidences.
-- =====================================================================

-- Q36. Does order size predict order profitability?
--
-- Orders are bucketed by how many lines they contain, then margin is
-- computed per bucket. Because line_count and revenue both live on
-- v_order_summary at order grain, no fan-out is possible here.
SELECT
    CASE
        WHEN line_count = 1      THEN '1 line'
        WHEN line_count = 2      THEN '2 lines'
        WHEN line_count BETWEEN 3 AND 4 THEN '3-4 lines'
        WHEN line_count BETWEEN 5 AND 6 THEN '5-6 lines'
        ELSE                          '7+ lines'
    END                                                     AS order_size,
    COUNT(*)                                                AS orders,
    SUM(order_revenue)                                      AS revenue,
    SUM(order_profit)                                       AS profit,
    ROUND(SUM(order_profit) / SUM(order_revenue) * 100, 2)  AS margin_pct,
    ROUND(AVG(order_revenue), 2)                            AS avg_order_value,
    SUM(order_profit < 0)                                   AS loss_making_orders,
    ROUND(SUM(order_profit < 0) * 100.0 / COUNT(*), 1)      AS loss_order_share_pct
FROM v_order_summary
GROUP BY
    CASE
        WHEN line_count = 1      THEN '1 line'
        WHEN line_count = 2      THEN '2 lines'
        WHEN line_count BETWEEN 3 AND 4 THEN '3-4 lines'
        WHEN line_count BETWEEN 5 AND 6 THEN '5-6 lines'
        ELSE                          '7+ lines'
    END,
    CASE
        WHEN line_count = 1 THEN 1 WHEN line_count = 2 THEN 2
        WHEN line_count BETWEEN 3 AND 4 THEN 3
        WHEN line_count BETWEEN 5 AND 6 THEN 4 ELSE 5
    END
ORDER BY MIN(line_count);


-- Q37. Which category combinations drag an order down?
--
-- Conditional aggregation collapses each order's lines into a single
-- "category mix" label, which is then joined back to the order's
-- profitability. This answers a question no single-table query can:
-- whether Furniture's weak margin (1.81%, Q3) contaminates whole orders
-- or is confined to its own lines.
WITH order_mix AS (
    SELECT
        o.order_id,
        MAX(sc.category = 'Electronics') AS has_electronics,
        MAX(sc.category = 'Clothing')    AS has_clothing,
        MAX(sc.category = 'Furniture')   AS has_furniture
    FROM fact_orders o
    JOIN fact_order_lines l  ON l.order_id      = o.order_id
    JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
    GROUP BY o.order_id
),
labelled AS (
    SELECT
        om.order_id,
        CONCAT_WS(' + ',
            CASE WHEN om.has_electronics THEN 'Electronics' END,
            CASE WHEN om.has_clothing    THEN 'Clothing'    END,
            CASE WHEN om.has_furniture   THEN 'Furniture'   END
        )                                    AS category_mix,
        om.has_electronics + om.has_clothing + om.has_furniture AS categories_in_order,
        os.order_revenue,
        os.order_profit
    FROM order_mix om
    JOIN v_order_summary os ON os.order_id = om.order_id
)
SELECT
    category_mix,
    categories_in_order,
    COUNT(*)                                                AS orders,
    SUM(order_revenue)                                      AS revenue,
    SUM(order_profit)                                       AS profit,
    ROUND(SUM(order_profit) / SUM(order_revenue) * 100, 2)  AS margin_pct,
    ROUND(AVG(order_revenue), 2)                            AS avg_order_value
FROM labelled
GROUP BY category_mix, categories_in_order
HAVING COUNT(*) >= 10          -- sample-size floor
ORDER BY margin_pct DESC;


-- Q38. Isolating the Furniture effect at order level.
-- A direct two-group comparison of orders that contain Furniture against
-- those that do not.
WITH flagged AS (
    SELECT
        os.order_id, os.order_revenue, os.order_profit,
        MAX(sc.category = 'Furniture') AS has_furniture
    FROM v_order_summary os
    JOIN fact_order_lines l  ON l.order_id      = os.order_id
    JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
    GROUP BY os.order_id, os.order_revenue, os.order_profit
)
SELECT
    CASE WHEN has_furniture THEN 'Order contains Furniture'
         ELSE 'No Furniture in order' END                   AS order_type,
    COUNT(*)                                                AS orders,
    SUM(order_revenue)                                      AS revenue,
    SUM(order_profit)                                       AS profit,
    ROUND(SUM(order_profit) / SUM(order_revenue) * 100, 2)  AS margin_pct,
    ROUND(AVG(order_revenue), 2)                            AS avg_order_value,
    ROUND(SUM(order_profit < 0) * 100.0 / COUNT(*), 1)      AS loss_order_share_pct
FROM flagged
GROUP BY has_furniture;
