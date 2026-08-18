-- =====================================================================
-- 01_schema.sql
-- Indian E-Commerce Sales Analysis  |  MySQL 8.0+
--
-- Builds a two-layer database:
--
--   RAW / STAGING LAYER   raw_orders, raw_order_details, raw_sales_target
--                         Every column is VARCHAR. This layer is a faithful,
--                         untouched mirror of the source CSVs so that all
--                         type casting, trimming and validation is explicit
--                         and auditable in 02_data_cleaning.sql.
--
--   MODELLED LAYER        dim_customer, dim_sub_category,
--                         fact_orders, fact_order_lines, fact_sales_target
--                         Typed, keyed and constrained. All analysis runs here.
--
-- Grain is stated on every table because the single biggest correctness risk
-- in this dataset is fan-out: fact_orders is 1 row per order (500) while
-- fact_order_lines is 1 row per line (1,500, averaging 3.0 lines per order).
-- Aggregating order-level and line-level measures in the same join without
-- care triples order counts. See docs/data_quality.md.
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce_analytics;
CREATE DATABASE ecommerce_analytics
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE ecommerce_analytics;


-- ---------------------------------------------------------------------
-- RAW / STAGING LAYER
-- ---------------------------------------------------------------------

-- Source: data/List of Orders.csv
-- Header: Order ID, Order Date, CustomerName, State, City
-- 500 populated rows (+60 completely empty rows excluded at load time).
DROP TABLE IF EXISTS raw_orders;
CREATE TABLE raw_orders (
    order_id        VARCHAR(20),
    order_date      VARCHAR(20),   -- text 'dd-mm-yyyy', cast in cleaning
    customer_name   VARCHAR(100),
    state           VARCHAR(100),  -- contains 'Kerala ' with a trailing space
    city            VARCHAR(100)
) ENGINE=InnoDB COMMENT='Staging mirror of List of Orders.csv. Grain: 1 row per order.';

-- Source: data/Order Details.csv
-- Header: Order ID, Amount, Profit, Quantity, Category, Sub-Category
-- 1,500 rows. NOTE: (Order ID, Sub-Category) is NOT unique - 196 order/
-- sub-category pairs appear more than once - so this table has no natural
-- key and the modelled layer uses a surrogate order_line_id.
DROP TABLE IF EXISTS raw_order_details;
CREATE TABLE raw_order_details (
    order_id        VARCHAR(20),
    amount          VARCHAR(20),
    profit          VARCHAR(20),
    quantity        VARCHAR(20),
    category        VARCHAR(50),
    sub_category    VARCHAR(50)
) ENGINE=InnoDB COMMENT='Staging mirror of Order Details.csv. Grain: 1 row per order line.';

-- Source: data/Sales target.csv
-- Header: Month of Order Date, Category, Target
-- 36 rows = 12 months (Apr-18 .. Mar-19) x 3 categories. Complete grid.
DROP TABLE IF EXISTS raw_sales_target;
CREATE TABLE raw_sales_target (
    month_of_order_date VARCHAR(20),  -- text 'Mon-YY'
    category            VARCHAR(50),
    target              VARCHAR(20)
) ENGINE=InnoDB COMMENT='Staging mirror of Sales target.csv. Grain: 1 row per month x category.';


-- ---------------------------------------------------------------------
-- MODELLED LAYER
-- ---------------------------------------------------------------------

-- Customer identity.
--
-- DESIGN DECISION: the source carries only a first name - no customer id,
-- email or phone. 43 names appear in more than one (state, city). Treating
-- the bare name as the customer would silently merge distinct people:
-- 'Pooja' alone spans four different states.
--
-- Customer identity is therefore (customer_name, state, city), which yields
-- 401 customers rather than 332. This is the conservative choice: it may
-- still split one relocating customer into two, but it does not invent
-- repeat purchases that never happened. The sensitivity of every customer
-- metric to this choice is quantified in docs/data_quality.md.
--
-- Geography lives here (not on fact_orders) because it is a property of the
-- customer under this identity definition - each (name, state, city) has
-- exactly one location by construction, so no fan-out is possible.
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
    customer_id     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    customer_name   VARCHAR(100)    NOT NULL,
    state           VARCHAR(100)    NOT NULL,
    city            VARCHAR(100)    NOT NULL,
    PRIMARY KEY (customer_id),
    UNIQUE KEY uq_customer_identity (customer_name, state, city),
    KEY idx_customer_state (state),
    KEY idx_customer_city  (city)
) ENGINE=InnoDB COMMENT='Grain: 1 row per (customer_name, state, city).';

-- Product hierarchy.
-- The dataset has NO product names or SKUs. The finest available product
-- grain is Sub-Category (17 values). Sub-category -> category was verified
-- to be a true functional dependency (no sub-category spans two categories),
-- so this is a valid dimension rather than a denormalised attribute.
DROP TABLE IF EXISTS dim_sub_category;
CREATE TABLE dim_sub_category (
    sub_category    VARCHAR(50)     NOT NULL,
    category        VARCHAR(50)     NOT NULL,
    PRIMARY KEY (sub_category),
    KEY idx_subcat_category (category)
) ENGINE=InnoDB COMMENT='Grain: 1 row per sub-category. 17 rows across 3 categories.';

-- Order header. Grain: 1 row per order (500 rows).
-- Order-level measures (order counts, AOV) must be computed from THIS table.
DROP TABLE IF EXISTS fact_orders;
CREATE TABLE fact_orders (
    order_id        VARCHAR(20)     NOT NULL,
    customer_id     INT UNSIGNED    NOT NULL,
    order_date      DATE            NOT NULL,
    PRIMARY KEY (order_id),
    KEY idx_orders_date (order_date),
    KEY idx_orders_customer (customer_id),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES dim_customer (customer_id)
) ENGINE=InnoDB COMMENT='Grain: 1 row per order. 500 rows, Apr 2018 - Mar 2019.';

-- Order lines. Grain: 1 row per line (1,500 rows).
-- Revenue, profit and quantity live ONLY here.
--
-- amount / profit are DECIMAL(10,2): the source has 2dp and a maximum
-- magnitude of 5,729.00, so this is comfortably sized and avoids the
-- floating-point drift that would make margin percentages irreproducible.
--
-- A surrogate key is required because the source has no unique line
-- identifier - see the note on raw_order_details above.
DROP TABLE IF EXISTS fact_order_lines;
CREATE TABLE fact_order_lines (
    order_line_id   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    order_id        VARCHAR(20)     NOT NULL,
    sub_category    VARCHAR(50)     NOT NULL,
    amount          DECIMAL(10,2)   NOT NULL,
    profit          DECIMAL(10,2)   NOT NULL,  -- legitimately negative on 503 lines
    quantity        INT             NOT NULL,
    PRIMARY KEY (order_line_id),
    KEY idx_lines_order (order_id),
    KEY idx_lines_subcat (sub_category),
    CONSTRAINT fk_lines_order
        FOREIGN KEY (order_id) REFERENCES fact_orders (order_id),
    CONSTRAINT fk_lines_subcat
        FOREIGN KEY (sub_category) REFERENCES dim_sub_category (sub_category),
    CONSTRAINT chk_lines_amount_positive   CHECK (amount > 0),
    CONSTRAINT chk_lines_quantity_positive CHECK (quantity > 0)
) ENGINE=InnoDB COMMENT='Grain: 1 row per order line. 1,500 rows, avg 3.0 lines per order.';

-- Monthly category targets. Grain: 1 row per (month, category).
-- target_month is stored as the first day of the month (a DATE) rather than
-- the source's 'Mon-YY' text, so that it sorts and joins chronologically.
DROP TABLE IF EXISTS fact_sales_target;
CREATE TABLE fact_sales_target (
    target_month    DATE            NOT NULL,
    category        VARCHAR(50)     NOT NULL,
    target_amount   DECIMAL(12,2)   NOT NULL,
    PRIMARY KEY (target_month, category),
    CONSTRAINT chk_target_positive CHECK (target_amount > 0)
) ENGINE=InnoDB COMMENT='Grain: 1 row per month x category. 36 rows.';

-- Note: fact_sales_target.category is intentionally NOT a foreign key to
-- dim_sub_category.category, because that column is not unique there
-- (it is the parent side of the hierarchy). Category consistency between
-- the two is asserted as a test in 02_data_cleaning.sql instead.
