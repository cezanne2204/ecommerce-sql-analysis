-- =====================================================================
-- 04_views.sql
-- Reusable views. Each one exists to remove a specific, repeated risk of
-- getting the analysis wrong - not merely to shorten queries.
--
-- SNAPSHOT DATE
-- Recency needs a "today". The dataset ends on 2019-03-31 and there is no
-- extract timestamp, so the snapshot is fixed at the last order date.
-- Using CURDATE() would make every recency value drift with the clock and
-- make the segmentation irreproducible.
-- =====================================================================

USE ecommerce_analytics;


-- ---------------------------------------------------------------------
-- v_order_summary
-- WHY: collapses the 1,500 line rows to the 500 order rows once, so that
-- downstream queries can use order-level and value measures together
-- without re-deriving the aggregation - the single most common source of
-- triple-counted order totals in this dataset.
-- Grain: 1 row per order.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
    COUNT(*)                              AS line_count,
    SUM(l.amount)                         AS order_revenue,
    SUM(l.profit)                         AS order_profit,
    SUM(l.quantity)                       AS order_quantity
FROM fact_orders o
JOIN fact_order_lines l ON l.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_date;


-- ---------------------------------------------------------------------
-- v_customer_metrics
-- WHY: centralises the customer identity decision. Every customer figure
-- in the project resolves through this view, so if the identity rule is
-- ever revised only one object changes.
-- Grain: 1 row per customer.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_metrics AS
SELECT
    c.customer_id,
    c.customer_name,
    c.state,
    c.city,
    COUNT(*)                                             AS order_count,
    SUM(os.order_revenue)                                AS total_revenue,
    SUM(os.order_profit)                                 AS total_profit,
    SUM(os.order_quantity)                               AS total_quantity,
    ROUND(AVG(os.order_revenue), 2)                      AS avg_order_value,
    MIN(os.order_date)                                   AS first_order_date,
    MAX(os.order_date)                                   AS last_order_date,
    DATEDIFF(MAX(os.order_date), MIN(os.order_date))     AS customer_lifespan_days,
    DATEDIFF('2019-03-31', MAX(os.order_date))           AS days_since_last_order,
    CASE WHEN COUNT(*) = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type
FROM v_order_summary os
JOIN dim_customer c ON c.customer_id = os.customer_id
GROUP BY c.customer_id, c.customer_name, c.state, c.city;


-- ---------------------------------------------------------------------
-- v_monthly_sales
-- WHY: guarantees every monthly query sorts on a real DATE. Sorting on
-- the display label would order the year as Apr, Aug, Dec, Feb...
-- Grain: 1 row per month.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_sales AS
SELECT
    month_start,
    DATE_FORMAT(month_start, '%b %Y')            AS month_label,
    COUNT(*)                                     AS orders,
    SUM(order_revenue)                           AS revenue,
    SUM(order_profit)                            AS profit,
    SUM(order_quantity)                          AS units,
    ROUND(SUM(order_revenue) / COUNT(*), 2)      AS avg_order_value,
    ROUND(SUM(order_profit) / SUM(order_revenue) * 100, 2) AS margin_pct
FROM v_order_summary
GROUP BY month_start;


-- ---------------------------------------------------------------------
-- v_sub_category_performance
-- WHY: the product hierarchy join plus margin arithmetic is repeated in
-- most product questions; doing it once keeps the margin definition
-- (profit / revenue, not profit / cost) identical everywhere.
-- Grain: 1 row per sub-category.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sub_category_performance AS
SELECT
    sc.category,
    l.sub_category,
    COUNT(*)                                          AS line_count,
    COUNT(DISTINCT l.order_id)                        AS order_count,
    SUM(l.amount)                                     AS revenue,
    SUM(l.profit)                                     AS profit,
    SUM(l.quantity)                                   AS units,
    ROUND(SUM(l.profit) / SUM(l.amount) * 100, 2)     AS margin_pct,
    ROUND(AVG(l.amount), 2)                           AS avg_line_value,
    SUM(l.profit < 0)                                 AS loss_making_lines
FROM fact_order_lines l
JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
GROUP BY sc.category, l.sub_category;


-- ---------------------------------------------------------------------
-- v_state_performance
-- WHY: order counts and customer counts must come from order/customer
-- grain while revenue comes from line grain. This view resolves that
-- split once so no downstream query multiplies orders by lines.
-- Grain: 1 row per state.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_state_performance AS
SELECT
    c.state,
    COUNT(*)                                              AS orders,
    COUNT(DISTINCT os.customer_id)                        AS customers,
    SUM(os.order_revenue)                                 AS revenue,
    SUM(os.order_profit)                                  AS profit,
    SUM(os.order_quantity)                                AS units,
    ROUND(SUM(os.order_profit) / SUM(os.order_revenue) * 100, 2) AS margin_pct,
    ROUND(SUM(os.order_revenue) / COUNT(*), 2)            AS avg_order_value,
    ROUND(SUM(os.order_revenue) / COUNT(DISTINCT os.customer_id), 2) AS revenue_per_customer
FROM v_order_summary os
JOIN dim_customer c ON c.customer_id = os.customer_id
GROUP BY c.state;


-- ---------------------------------------------------------------------
-- v_customer_rfm
-- WHY: RFM scoring is the most methodologically opinionated part of the
-- project, so the scoring rules live in exactly one place.
--
-- SCORING METHOD - and why it is not three NTILEs.
--
-- Recency and Monetary are close to continuous across 401 customers, so
-- NTILE(5) splits them into genuine quintiles.
--
-- Frequency cannot be scored that way. It takes only four distinct values
-- in this dataset (1, 2, 3, 4 orders) and 331 of 401 customers - 82.5% -
-- sit on the value 1. NTILE fills buckets by row position, so it would
-- hand different frequency scores to customers who made exactly the same
-- number of purchases, purely by sort order. That is an artefact, not a
-- signal. Frequency is therefore scored with explicit rules on the actual
-- purchase count. Query 5.2 in 05_advanced_analysis.sql demonstrates the
-- artefact rather than asking the reader to take this on trust.
--
-- Recency is inverted: NTILE ascending on days-since-last-order puts the
-- most recent customers in bucket 1, so the score is 6 - bucket.
-- Grain: 1 row per customer.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_rfm AS
WITH scored AS (
    SELECT
        cm.customer_id,
        cm.customer_name,
        cm.state,
        cm.city,
        cm.days_since_last_order,
        cm.order_count,
        cm.total_revenue,
        cm.total_profit,
        cm.first_order_date,
        cm.last_order_date,
        6 - NTILE(5) OVER (ORDER BY cm.days_since_last_order ASC)  AS r_score,
        CASE
            WHEN cm.order_count >= 4 THEN 5
            WHEN cm.order_count  = 3 THEN 4
            WHEN cm.order_count  = 2 THEN 3
            ELSE 1
        END                                                        AS f_score,
        NTILE(5) OVER (ORDER BY cm.total_revenue ASC)              AS m_score
    FROM v_customer_metrics cm
)
SELECT
    s.*,
    CONCAT(s.r_score, s.f_score, s.m_score) AS rfm_cell,
    -- Segment rules are ordered most-specific first; the CASE stops at the
    -- first match. Thresholds are calibrated to this dataset's reality:
    -- repeat purchase is rare, so requiring 3+ orders for "Champions"
    -- keeps that segment genuinely selective rather than aspirational.
    -- A recent single purchase is labelled "Recent High Spenders" rather
    -- than "New": the window opens on 2018-04-01, so we cannot tell a
    -- genuinely new customer from one whose earlier orders predate it.
    CASE
        WHEN s.f_score >= 4 AND s.r_score >= 4 AND s.m_score >= 4 THEN 'Champions'
        WHEN s.f_score >= 3 AND s.m_score >= 3                    THEN 'Loyal Customers'
        WHEN s.f_score >= 3                                       THEN 'Potential Loyalists'
        WHEN s.m_score >= 4 AND s.r_score <= 2                    THEN 'At Risk'
        WHEN s.m_score >= 4 AND s.r_score >= 4                    THEN 'Recent High Spenders'
        WHEN s.r_score <= 2 AND s.m_score <= 2                    THEN 'Hibernating'
        WHEN s.r_score >= 4                                       THEN 'Promising'
        WHEN s.m_score >= 3                                       THEN 'Needs Attention'
        ELSE 'Low Value'
    END AS rfm_segment
FROM scored s;


-- ---------------------------------------------------------------------
-- v_sales_vs_target
-- WHY: the target file is keyed on 'Mon-YY' text and the orders on a real
-- date. This view performs that reconciliation once, on the DATE column,
-- and uses a LEFT JOIN from targets so that a month/category with a
-- target but no sales still appears with zero rather than vanishing.
-- Grain: 1 row per month x category.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sales_vs_target AS
SELECT
    t.target_month,
    DATE_FORMAT(t.target_month, '%b %Y')                    AS month_label,
    t.category,
    t.target_amount,
    COALESCE(a.actual_revenue, 0)                           AS actual_revenue,
    COALESCE(a.actual_profit, 0)                            AS actual_profit,
    COALESCE(a.actual_revenue, 0) - t.target_amount         AS variance,
    ROUND((COALESCE(a.actual_revenue, 0) - t.target_amount)
          / t.target_amount * 100, 2)                       AS variance_pct,
    ROUND(COALESCE(a.actual_revenue, 0) / t.target_amount * 100, 2) AS achievement_pct,
    CASE WHEN COALESCE(a.actual_revenue, 0) >= t.target_amount
         THEN 'Hit' ELSE 'Miss' END                         AS status
FROM fact_sales_target t
LEFT JOIN (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
           sc.category,
           SUM(l.amount) AS actual_revenue,
           SUM(l.profit) AS actual_profit
    FROM fact_orders o
    JOIN fact_order_lines l  ON l.order_id      = o.order_id
    JOIN dim_sub_category sc ON sc.sub_category = l.sub_category
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01'), sc.category
) a ON a.month_start = t.target_month AND a.category = t.category;
