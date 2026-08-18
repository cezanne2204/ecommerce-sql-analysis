# Indian E-Commerce Sales Analysis Using SQL

An end-to-end SQL analytics project on a full fiscal year of Indian e-commerce transactions
(FY2018-19): staging and modelling, documented data cleaning, 38 business questions, and a
validation suite that re-derives every headline metric a second way.

**Every query in this repository was executed against MySQL 9.7.1. Every figure quoted in the
documentation is a real query result, and all key results were independently reproduced from the
source CSVs in Python before being written down.**

---

## 1. Project Overview

The dataset is three flat CSVs with no keys, no types and no documentation. This project turns them
into a queryable star-schema warehouse and answers a progression of business questions on it —
from headline KPIs through profitability, geography and time series to RFM segmentation and target
attainment.

The emphasis is on **being right**, not on being elaborate. The dataset contains several traps that
produce plausible-looking but wrong answers — a one-to-many join that silently triples order counts,
a date format that is ambiguous on 39% of rows, a customer key that merges different people, and a
detail table with no natural key where `SELECT DISTINCT` would delete real revenue. Each is
identified, handled, and documented in [`docs/data_quality.md`](docs/data_quality.md).

**Headline results (all verified):**

| Metric | Value |
|---|---|
| Revenue | ₹431,502 |
| Profit | ₹23,955 |
| Profit margin | 5.55% |
| Orders | 500 |
| Customers | 401 |
| Units sold | 5,615 |
| Average order value | ₹863.00 |
| Coverage | 19 states · 24 cities · 3 categories · 17 sub-categories |
| Period | 1 Apr 2018 – 31 Mar 2019 |

---

## 2. Business Problem

The business closed FY2018-19 with a 5.55% profit margin on ₹431,502 of revenue and no view of
where that thin margin came from. This project answers:

- Which products and regions actually make money, and which are subsidised by the rest?
- How concentrated is the business — on how few customers and how few markets does it depend?
- Are the sales targets steering the business anywhere profitable?
- Did performance change over the year, and if so, when and by how much?

The most consequential finding is that the annual margin is a blend of two very different halves:
the business **lost ₹21,795 over the first six months and earned ₹45,750 over the second**, a swing
of roughly 31 margin points. The full-year average describes a business that no longer exists.

---

## 3. Dataset

**Source:** [E-Commerce Data — Kaggle (`benroshan/ecommerce-data`)](https://www.kaggle.com/datasets/benroshan/ecommerce-data)
· 3 CSV files, included in [`data/`](data/).

| File | Rows | Columns |
|---|---|---|
| `List of Orders.csv` | 500 | Order ID, Order Date, CustomerName, State, City |
| `Order Details.csv` | 1,500 | Order ID, Amount, Profit, Quantity, Category, Sub-Category |
| `Sales target.csv` | 36 | Month of Order Date, Category, Target |

Schema was determined by profiling the actual files — no column was assumed. Note the two things
the dataset does **not** contain, which bound every conclusion drawn from it:

- **No product identifiers.** The finest product grain is *sub-category* (17 values). "Product
  analysis" here means sub-category analysis.
- **No cost, price or discount columns.** Margin can be measured but never explained.

Full limitations are listed in [`docs/data_quality.md`](docs/data_quality.md#known-limitations-of-the-dataset-itself).

---

## 4. Tools & Technologies

| Tool | Use |
|---|---|
| **MySQL 9.7.1** (8.0+ syntax) | Database, all analysis. `ONLY_FULL_GROUP_BY` and `STRICT_TRANS_TABLES` enabled throughout — no relaxed `sql_mode` |
| **SQL** | CTEs, window functions, conditional aggregation, views, `CHECK` constraints |
| **Python 3 (stdlib `csv`)** | Independent verification only — never used to produce a reported figure |

---

## 5. Database Schema

Two layers. Staging is an untouched text mirror of the CSVs; the modelled layer is typed, keyed and
constrained. All analysis runs on the modelled layer.

```
                        ┌──────────────────────┐
                        │     dim_customer     │
                        │──────────────────────│
                        │ customer_id     (PK) │
                        │ customer_name  ┐     │
                        │ state          ├ UQ  │   401 rows
                        │ city           ┘     │
                        └──────────┬───────────┘
                                   │ 1
                                   │
                                   │ N
                        ┌──────────┴───────────┐
                        │     fact_orders      │
                        │──────────────────────│
                        │ order_id        (PK) │   500 rows
                        │ customer_id     (FK) │   grain: 1 per order
                        │ order_date           │
                        └──────────┬───────────┘
                                   │ 1
                                   │
                                   │ N   ← fan-out lives here (avg 3.0)
                        ┌──────────┴───────────┐
                        │   fact_order_lines   │
                        │──────────────────────│
                        │ order_line_id   (PK) │   1,500 rows
                        │ order_id        (FK) │   grain: 1 per line
                        │ sub_category    (FK) │
                        │ amount, profit, qty  │
                        └──────────┬───────────┘
                                   │ N
                                   │
                                   │ 1
                        ┌──────────┴───────────┐
                        │   dim_sub_category   │
                        │──────────────────────│
                        │ sub_category    (PK) │   17 rows
                        │ category             │
                        └──────────┬───────────┘
                                   │
                          category │ (not a FK — see note)
                                   │
                        ┌──────────┴───────────┐
                        │  fact_sales_target   │
                        │──────────────────────│
                        │ target_month    (PK) │   36 rows
                        │ category        (PK) │   grain: 1 per month × category
                        │ target_amount        │
                        └──────────────────────┘
```

**Relationships shown are only those that exist in the data**, each verified before it was declared:

- `dim_customer 1—N fact_orders` — every order has exactly one customer.
- `fact_orders 1—N fact_order_lines` — verified in both directions: **no orphan lines and no
  order without lines**. 500 orders, 1,500 lines, 1–12 lines per order.
- `dim_sub_category 1—N fact_order_lines` — `Sub-Category → Category` was verified to be a true
  functional dependency, which is what makes this a valid dimension rather than a denormalised
  column.
- `fact_sales_target.category` is deliberately **not** a foreign key: `category` is not unique in
  `dim_sub_category` (it is the parent side of the hierarchy). Consistency between the two is
  asserted as a test in `02_data_cleaning.sql` instead.

**Grain is the central design concern.** Order-level measures (order count, AOV) and line-level
measures (revenue, profit, quantity) live in different tables. Joining them and aggregating
carelessly triples order counts — the most common way to get this dataset wrong. `v_order_summary`
exists specifically to resolve that once.

---

## 6. Data Cleaning

Detection queries, an exception log and assertions live in
[`sql/02_data_cleaning.sql`](sql/02_data_cleaning.sql); the reasoning is in
[`docs/data_quality.md`](docs/data_quality.md). Raw tables are never modified.

| # | Problem | Treatment | Why |
|---|---|---|---|
| 1 | 60 completely empty rows in the orders CSV | Excluded at load | No value in any column; would have inflated order count 12% |
| 2 | `'Kerala '` with trailing space (16 rows) | `TRIM()`, logged | Breaks joins to clean reference data |
| 3 | `(Order ID, Sub-Category)` not unique (196 pairs) | **Surrogate key**, nothing deleted | No two rows are identical across all columns — these are real distinct line items. `DISTINCT` would delete revenue |
| 4 | Customer is a first name only; 43 names span multiple cities | Identity = `(name, state, city)` → **401** customers, not 332 | Bare name would invent 33 repeat customers out of shared first names |
| 5 | City `Delhi` recorded in `Madhya Pradesh` (3 orders) | **Kept**, flagged ERROR | One field is wrong but the data doesn't say which; guessing would move revenue between the two largest markets |
| 6 | `Chandigarh` under both Punjab and Haryana (30 orders) | **Kept**, flagged INFO | Not an error — Chandigarh is the shared capital of both states |
| 7 | `ABS(profit) > amount` on 14 lines | **Kept**, flagged WARN | Plausible (discounting/returns); deleting would flatter the exact problem being analysed |
| 8 | 503 lines with negative profit | **Kept**, not flagged | Loss-making sales are the subject of the analysis, not noise |
| 9 | Ambiguous date format (`01-04-2018`) | Proven `dd-mm-yyyy`, cast to `DATE` | 307 rows have a first component > 12 — impossible as a month. Corroborated by an exact Apr–Mar fiscal year in both files |

Nine assertions at the end of the script confirm the load preserved row counts, revenue, profit and
quantity exactly, and that no join fanned out. **All nine pass.**

---

## 7. Analytical Framework

```
  Raw CSVs
     │
     ▼
  Data Validation ......... profile every column; verify keys, types, ranges
     │
     ▼
  Data Cleaning ........... detect → log → treat, with raw preserved
     │
     ▼
  Database Design ......... staging + star schema; grain fixed per table
     │
     ▼
  Exploratory Analysis .... executive KPIs, reconciliation checks
     │
     ▼
  Product / Geographic / Customer / Time-series analysis
     │
     ▼
  Advanced SQL ............ window functions, RFM, ranking, attainment
     │
     ▼
  Validation .............. every metric recomputed a second, independent way
     │
     ▼
  Business Insights ....... finding → why it matters → recommendation
     │
     ▼
  Recommendations ......... prioritised, with caveats stated
```

---

## 8. Business Questions

38 questions across seven sections. Sections A–D are in
[`03_analysis.sql`](sql/03_analysis.sql), E–H in
[`05_advanced_analysis.sql`](sql/05_advanced_analysis.sql).

**A · Executive KPIs**
1. Full KPI summary in one row
2. Does revenue reconcile between line grain and order grain?

**B · Sales & Profitability**
3. How do the three categories compare on revenue, profit and margin?
4. Which sub-categories carry the business, and which drain it?
5. Which sub-categories are high revenue but weak profitability? *(quadrants from data-derived thresholds)*
6. Which sub-categories destroy profit, and what would profit be without them?
7. How concentrated is revenue across the product range? *(Pareto)*
8. Which sub-categories command the highest value per line?

**C · Geographic**
9. Full state scorecard — revenue, profit, margin, orders, customers, AOV
10. Market classification: strong / high-revenue-weak-profit / growth / underperforming
11. City-level performance, with a sample-size floor
12. Which states lose money outright?

**D · Time series**
13. Monthly performance with MoM growth and running cumulative totals
14. Quarterly performance on the Indian fiscal year
15. Day-of-week pattern, normalised by active days
16. Does the category mix shift over the year?

**E · Customer base**
17. How much revenue rests on customers who never came back?
18. Purchase-frequency distribution and the revenue each tier holds
19. How few customers make the first 50% of revenue?
20. Top customers, revenue rank vs profit rank
21. Which customers spend heavily but earn nothing?
22. How much revenue sits with above-average spenders?

**F · RFM segmentation**
23. **Why frequency is *not* scored with `NTILE`** — a query that demonstrates the artefact
24. Segment scorecard
25. The At Risk working list
26. Do repeat customers spend more on later orders?
27. First vs latest purchase — who is growing, who is fading?
28. Top 3 customers in every state

**G · Product ranking**
29. Top 3 sub-categories per category, with `ROW_NUMBER`/`RANK`/`DENSE_RANK` side by side
30. Profitability quartiles across sub-categories

**H · Target attainment**
31. Attainment by category
32. Attainment by month
33. The full category × month grid
34. Is attainment improving or deteriorating? *(H1 vs H2)*
35. **Does hitting the revenue target actually produce profit?**

**I · Order composition**
36. Does order size predict order profitability? *(tests — and refutes — the "big baskets are bad" hypothesis)*
37. Which category combinations drag an order down?
38. Isolating the Furniture effect at order level

---

## 9. SQL Techniques Demonstrated

Techniques were used where they were the right tool, not to fill a checklist.

| Technique | Where, and why it was needed |
|---|---|
| **CTEs / multiple CTEs** | Q1, Q5, Q10, Q19, Q26, Q34 — separating grains before combining them |
| **`ROW_NUMBER`** | Q28 top-3 per state (exactly 3 rows needed, so not `RANK`) |
| **`RANK`** | Q3, Q9, Q20 — showing revenue rank against profit rank |
| **`DENSE_RANK`** | Q29 top-3 per category, where ties should both be kept |
| **`NTILE`** | Q30 margin quartiles; R and M scores in `v_customer_rfm` — and **Q23 shows where `NTILE` is the wrong choice** |
| **`LAG` / `LEAD`** | Q13 MoM growth; Q26 order-to-order change and time to next order |
| **`SUM() OVER`** | Running cumulative revenue/profit (Q13), share-of-total (Q3, Q7, Q9, Q17) |
| **Window frames** | `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` for running totals |
| **Conditional aggregation** | Q16 category pivot; Q27 first/last order values; Q34 H1-vs-H2; Q37 collapsing an order's lines into a basket-mix label |
| **`CASE`** | Quadrant/segment classification against data-derived thresholds |
| **`HAVING`** | Q6 loss-making sub-categories; Q12 loss-making states |
| **Joins** | `INNER` throughout the star; `LEFT JOIN` in `v_sales_vs_target` so a target with no sales still appears |
| **Subqueries** | Scalar benchmarks (business margin, average spend) computed from the data |
| **`COALESCE` / `NULLIF`** | Empty-string detection; `NULLIF` guards division by zero in MoM growth |
| **Date functions** | `STR_TO_DATE`, `DATE_FORMAT`, `DAYNAME`, `DATEDIFF`, `QUARTER`, `DATE_SUB` |
| **Views** | Seven, each documented with the specific error it prevents |
| **Constraints** | PK, FK, `UNIQUE`, and `CHECK` on positive amount/quantity |
| **`REGEXP`** | Numeric validation — `CAST` would silently return 0 and hide the problem |

**Deliberate omissions.** No stored procedures, triggers or recursive CTEs — nothing in this
dataset needs them, and adding them would be decoration.

---

## 10. Key Insights

Full analysis with supporting tables in [`docs/business_insights.md`](docs/business_insights.md).

1. **The year contains two different businesses.** Loss-making every month Apr–Sep 2018 (−₹21,795),
   profitable every month Oct 2018–Mar 2019 (+₹45,750). Cumulative profit only crossed zero in
   January 2019. Q1 margin −14.73% → Q3 +17.05%. *The 5.55% annual margin describes neither half.*
2. **Two sub-categories cost 22% of annual profit.** Tables (−₹4,011, −17.74%, loss-making on 65%
   of lines) and Electronic Games (−₹1,236). Without them profit would have been ₹29,202.
3. **Saree is the largest hidden margin problem.** 3rd-biggest revenue line (₹53,511) returning
   **0.66%** margin — it passes every loss filter because its total is positive. T-shirt earns
   4.3× Saree's profit on 13.8% of its revenue.
4. **Clothing out-earns Electronics on 16% less revenue** (₹11,163 vs ₹10,494) — revenue rank and
   profit rank invert. Furniture takes 29.5% of revenue for 9.6% of profit.
5. **Margin varies more within states than across the country.** Pune returns 13.56% and the
   highest AOV in the dataset (₹1,522); Mumbai, in the same state and twice the size, returns
   2.65%. Udaipur +18.15% vs Jaipur −7.47%. *State-level reporting hides the real unit of
   performance.*
6. **Targets are mis-set, and penalise the most profitable category.** Clothing carries the largest
   target (₹174,000) and misses it 9 months of 12 (79.9%); Electronics carries the smallest and
   beats it by 28%.
7. **Revenue-target hits coincide with profit** — 11.83% margin on hit cells vs **−3.92% on missed
   cells**. Real validation of the incentive, but confounded by finding 1.
8. **82.5% of customers ordered once**, contributing 67.1% of revenue; **59 customers (14.7%)
   generate half of all revenue.** First→second order takes 281 days; second→third only 37.
9. **The At Risk segment holds 19.8% of revenue and lost ₹10,345** — the standard win-back play
   would deepen the loss.
10. **Weekend orders are larger but less profitable.** Sunday has the highest AOV (₹1,145) and a
    2.42% margin; Saturday the lowest AOV (₹652) and 13.77%.
11. **But "big baskets are bad" is false — and testing it changed the recommendation.** Orders of
    7+ lines are the *most* profitable group in the business (8.84% margin, 47.5% of all profit).
    The real driver is category mix: **Electronics sold alone loses money (−5.79%)** while
    Electronics sold with Clothing returns **+9.23%**.

---

## 11. Business Recommendations

1. **Establish what changed in October 2018.** A 31-point margin swing is the largest fact in the
   dataset and its cause is not recorded anywhere in it. Nothing else should be prioritised above
   knowing whether the recovery is repeatable.
2. **Run one margin review across Saree, Tables and Electronic Games.** Combined, roughly
   **₹9,000 of recoverable profit against a ₹23,955 base — a ~38% uplift with no revenue growth.**
   Saree is the largest prize and the least obvious.
3. **Rebase FY2019-20 targets on H2 run-rate, rebalance across categories, and add a margin
   target.** Current targets misfire in both directions and steer only on revenue.
4. **Move geographic management to city level** and diagnose Pune's economics for replication in
   Mumbai.
5. **Focus retention entirely on the first→second order transition**, and split the At Risk segment
   by profitability before spending anything on win-back.

---

## 12. Project Structure

```
ecommerce-sql-analysis/
├── README.md
├── data/
│   ├── List of Orders.csv          # source, unmodified
│   ├── Order Details.csv           # source, unmodified
│   ├── Sales target.csv            # source, unmodified
│   └── seed_raw_data.sql           # portable loader (2,036 INSERT rows)
├── sql/
│   ├── 01_schema.sql               # database, staging + star schema
│   ├── 02_data_cleaning.sql        # detection → exception log → transform → 9 assertions
│   ├── 03_analysis.sql             # Q1–Q16  KPIs, profitability, geography, time
│   ├── 04_views.sql                # 7 documented views
│   ├── 05_advanced_analysis.sql    # Q17–Q38 customers, RFM, ranking, targets, baskets
│   └── 06_validation.sql           # 17 independent correctness checks + single verdict
└── docs/
    ├── data_quality.md             # every cleaning decision, with justification
    └── business_insights.md        # 10 insights: finding → why → recommendation
```

---

## 13. How to Run

Requires MySQL 8.0+. From the project root:

```bash
mysql -u root -p < sql/01_schema.sql && mysql -u root -p < data/seed_raw_data.sql && mysql -u root -p < sql/02_data_cleaning.sql && mysql -u root -p < sql/04_views.sql
```

Then run the analysis and the validation suite:

```bash
mysql -u root -p --table < sql/03_analysis.sql
```

```bash
mysql -u root -p --table < sql/05_advanced_analysis.sql
```

```bash
mysql -u root -p --table < sql/06_validation.sql
```

**Notes**

- `01_schema.sql` begins with `DROP DATABASE IF EXISTS ecommerce_analytics` — it is safe to re-run
  from scratch at any point.
- Data loads via plain `INSERT` statements in `data/seed_raw_data.sql`, so **no server
  configuration is required**. `LOAD DATA LOCAL INFILE` is disabled by default in MySQL 8+ and is
  deliberately not used.
- `04_views.sql` must run before `05_advanced_analysis.sql` and `06_validation.sql`.
  `03_analysis.sql` is self-contained and can run immediately after cleaning.
- Run with `--table` to get formatted output.
- `06_validation.sql` ends with a single verdict row — `ALL CHECKS PASSED` or an explicit
  failure — so correctness can be confirmed at a glance rather than by reading 17 result sets.

---

## 14. Conclusion

The dataset is small — 500 orders — but it is not simple, and most of the work in this project went
into not being wrong: proving the date format rather than assuming it, choosing a customer key that
understates loyalty rather than inventing it, keeping a surrogate line key so that `DISTINCT` could
not silently delete revenue, and re-deriving every headline metric a second way before writing it
down. **17/17 validation checks and 9/9 load assertions pass** on a clean rebuild, and all key results
were reproduced independently in Python from the raw CSVs.

The analysis itself argues that the headline annual margin is misleading — the business changed
character halfway through the year — and that the largest available profit improvement is not in
the obviously loss-making products but in **Saree**, a high-volume line whose 0.66% margin is
concealed by a positive total. It also tests its own most intuitive conclusion — that large baskets
are unprofitable — and reports that the data refutes it. Where the data cannot support a conclusion — why the October
turnaround happened, whether one-time customers really churned, whether day-of-week margin
differences are real at this sample size — that is stated rather than papered over.

---

*Dataset: [E-Commerce Data, Kaggle](https://www.kaggle.com/datasets/benroshan/ecommerce-data). Analysis, schema design, and documentation are original work.*
