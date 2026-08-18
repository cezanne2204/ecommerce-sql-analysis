# Data Quality Report

Every issue below was found by a query in [`sql/02_data_cleaning.sql`](../sql/02_data_cleaning.sql),
not by inspection. Each is recorded as **Problem → Detection → Treatment → Justification**.

The governing principle: **raw stays raw**. The staging tables are a byte-faithful mirror of the
CSVs. Nothing is deleted. Rows that look wrong but are plausibly real are carried into the model
and logged in `dq_exceptions` so that any judgement call can be reversed by a later reader.

---

## Source files as received

| File | Rows (populated) | Columns | Grain |
|---|---|---|---|
| `List of Orders.csv` | 500 | Order ID, Order Date, CustomerName, State, City | 1 per order |
| `Order Details.csv` | 1,500 | Order ID, Amount, Profit, Quantity, Category, Sub-Category | 1 per order line |
| `Sales target.csv` | 36 | Month of Order Date, Category, Target | 1 per month × category |

Verified totals used as the reconciliation baseline throughout the project:
**revenue 431,502.00 · profit 23,955.00 · quantity 5,615**.

---

## 1. Sixty empty rows in the orders file

**Problem.** `List of Orders.csv` contains 561 lines: a header, 500 populated rows, and 60 rows
consisting only of commas (`,,,,`).

**Detection.** Reading the file with a CSV parser and counting rows where every field is blank.
A naive `wc -l` would have reported 560 data rows and inflated the order count by 12%.

**Treatment.** Excluded at load. `data/seed_raw_data.sql` inserts only the 500 populated rows,
and the exclusion is stated in that file's header.

**Justification.** These rows carry no value in any column, not even an order ID. They are an
export artefact, not missing data — there is nothing to impute and no entity to represent.
Loading them as 60 all-NULL rows would corrupt every count in the project while adding nothing.

---

## 2. Trailing whitespace in the state name

**Problem.** The state `Kerala` is stored as `'Kerala '` with a trailing space, on 16 rows.

**Detection.** `WHERE state <> TRIM(state)`, run across every text column.

**Treatment.** `TRIM()` applied when building `dim_customer`. The untrimmed value is preserved in
staging, and the 16 affected orders are logged as `untrimmed_state` (severity INFO).

**Justification.** Worth being precise about the size of this problem: **all 16** Kerala rows carry
the trailing space, so it does *not* split Kerala into two competing variants within this dataset —
`GROUP BY state` would still have produced one Kerala row. The defect matters because it would break
any join to a clean reference list of Indian states, and because it silently propagates into report
labels. It is corrected, but it is not the "duplicate state" problem it superficially resembles.

---

## 3. `(Order ID, Sub-Category)` is not unique

**Problem.** 196 order/sub-category pairs appear more than once in `Order Details.csv`. The detail
file therefore has **no natural key**.

**Detection.** `GROUP BY order_id, sub_category HAVING COUNT(*) > 1`. Separately, a `GROUP BY` on
*all six* columns returned zero groups — so there are **no fully identical rows**.

**Treatment.** `fact_order_lines` uses a surrogate `order_line_id AUTO_INCREMENT` primary key.
No rows were de-duplicated.

**Justification.** Because no two rows are identical across all columns, these repeats differ in
amount, profit or quantity — they are genuinely distinct line items for the same sub-category
within one order (different products at different price points, which the dataset cannot resolve
further because it has no SKU). Collapsing them would have destroyed real revenue. This is the
single most consequential cleaning decision in the project: a `SELECT DISTINCT` here would have
silently deleted revenue.

---

## 4. Customer identity is ambiguous

**Problem.** The dataset identifies customers by **first name only** — no ID, email or phone.
43 names appear in more than one `(state, city)`. `Pooja` alone spans four states.

**Detection.** `GROUP BY customer_name HAVING COUNT(DISTINCT CONCAT(state,'|',city)) > 1`.

**Treatment.** Customer identity is defined as **`(customer_name, state, city)`**, giving
**401 customers**. Using the bare name would give 332.

**Justification.** The two definitions disagree materially, so the choice cannot be made silently:

| Identity rule | Customers | "Repeat" customers |
|---|---|---|
| Name only | 332 | 103 |
| Name + state + city | **401** | **70** |

Treating the bare name as the customer would manufacture 33 repeat customers out of people who
merely share a common first name — and repeat-purchase rate is a headline metric of this project.
The composite key is the conservative error: it may split a genuinely relocating customer into two
records, which *understates* loyalty, whereas the alternative *invents* loyalty that may not exist.
Understating a metric you are reporting on is the safer failure.

**Residual limitation.** Even the composite key is imperfect — two different people named Pooja in
Simla are still merged. No further disambiguation is possible with the columns available. Every
customer-level figure in this project should be read with that caveat, which is why the customer
identity rule lives in exactly one object (`dim_customer`) and one view (`v_customer_metrics`).

---

## 5. Impossible city/state pairing

**Problem.** The city `Delhi` is recorded under the state `Madhya Pradesh` on 3 orders.
(It appears correctly under `Delhi` on the other 22.)

**Detection.** `GROUP BY city HAVING COUNT(DISTINCT state) > 1`.

**Treatment.** **Retained unchanged**, logged as `impossible_city_state` (severity ERROR).

**Justification.** There is no Delhi in Madhya Pradesh, so one of the two fields is wrong — but the
data does not say which. Reassigning the state would move revenue between two markets on a guess,
and Madhya Pradesh is the largest market in the dataset, so the guess would contaminate the single
most important geographic finding. 3 orders out of 500 (0.6%) cannot change any conclusion drawn
here; a silent correction could. The rows stay, flagged.

---

## 6. Chandigarh appears under two states

**Problem.** `Chandigarh` is recorded under both `Punjab` (16 orders) and `Haryana` (14 orders).

**Detection.** Same query as issue 5.

**Treatment.** **Retained unchanged**, logged as `shared_capital_city` (severity INFO).

**Justification.** Unlike issue 5 this is **not an error**. Chandigarh is a union territory that
serves as the shared capital of both Punjab and Haryana, so either label is geographically
defensible. Merging them would erase a real distinction.

**And it may be a real distinction.** The two labels perform very differently:

| Label | Orders | Revenue | Margin |
|---|---|---|---|
| Chandigarh, Punjab | 16 | 12,279 | **−9.39%** |
| Chandigarh, Haryana | 14 | 8,863 | **+14.95%** |

A 24-point margin gap in one city across two labels is either a genuine operational difference
(different fulfilment or pricing) or evidence that the label is arbitrary. On 30 orders this cannot
be resolved statistically, and it is flagged as a question for the business rather than presented
as a finding.

---

## 7. Losses larger than the revenue on the same line

**Problem.** On 14 lines, `ABS(profit) > amount` — the loss exceeds the money taken.

**Detection.** `WHERE ABS(profit) > amount`.

**Treatment.** **Retained**, logged as `loss_exceeds_revenue` (severity WARN).

**Justification.** This is unusual but not impossible: a deeply discounted item, a returned item
whose costs were still incurred, or an allocated overhead can all produce a loss larger than the
line's revenue. More importantly, removing them would *improve* reported profit by an amount that
would then need explaining, and the loss-making pattern they belong to is one of this project's
central findings — 503 of 1,500 lines (33.5%) lose money. Deleting the most extreme 14 would
flatter exactly the problem the analysis exists to surface.

---

## 8. Negative and zero profit (not a defect)

503 lines carry negative profit and 47 carry exactly zero. These are **not** treated as errors and
are not flagged. Amount and quantity are strictly positive on all 1,500 lines (enforced by
`CHECK` constraints), so there is no reason to doubt the transactions themselves. Loss-making sales
are the substance of the analysis, not noise in it.

---

## 9. Date format ambiguity — resolved by proof, not assumption

**Problem.** Dates are text like `01-04-2018`. Under `dd-mm-yyyy` that is 1 April; under
`mm-dd-yyyy` it is 4 January. 193 of 500 dates are ambiguous (both components ≤ 12). Choosing
wrongly would scramble every monthly and seasonal finding.

**Detection & proof.** 307 rows have a first component **greater than 12**, which is an impossible
month. The format is therefore `dd-mm-yyyy`, and all 500 rows parse cleanly under it with zero
failures.

**Corroboration.** The parsed range is exactly **2018-04-01 to 2019-03-31** — a precise Indian
fiscal year, with no gaps and no dates outside it. The target file independently spans exactly
`Apr-18` to `Mar-19`. Two independent sources agreeing on the same fiscal-year boundary confirms
the interpretation.

**Treatment.** `STR_TO_DATE(order_date, '%d-%m-%Y')` into a real `DATE` column.

---

## 10. Everything that was checked and found clean

Reporting only the problems would overstate how dirty this dataset is. The following checks
returned zero exceptions:

- No NULLs or empty strings in any column of any of the three files
- No duplicate `Order ID` in the header file (500 rows, 500 distinct — a valid primary key)
- No fully duplicated rows in the detail file
- **Perfect referential integrity in both directions** — no detail line lacks a header, no header
  lacks a detail line
- No non-numeric values in `Amount`, `Profit`, `Quantity`
- No zero or negative `Amount` or `Quantity`
- No casing inconsistencies (`delhi` vs `Delhi`) in any categorical column
- `Sub-Category → Category` is a true functional dependency — no sub-category spans two categories,
  which is what makes `dim_sub_category` a valid dimension
- The target grid is complete: 12 months × 3 categories = 36 rows, with no month or category
  present in one file and missing from the other

---

## Exception log summary

`dq_exceptions` after a full rebuild:

| Check | Severity | Rows |
|---|---|---|
| `loss_exceeds_revenue` | WARN | 14 |
| `impossible_city_state` | ERROR | 3 |
| `shared_capital_city` | INFO | 30 |
| `untrimmed_state` | INFO | 16 |

---

## Known limitations of the dataset itself

These are not defects to be cleaned — they are hard ceilings on what any analysis of this data can
claim, and they are restated in the README so no reader over-reads a finding.

1. **No product identifiers.** The finest product grain is *sub-category* (17 values). Anything
   described as "product performance" here is sub-category performance. True SKU-level analysis is
   impossible.
2. **No cost, discount or price columns.** Margin can be measured but never explained. The project
   can say *that* Furniture loses money; it cannot say whether the cause is discounting, freight,
   returns or procurement.
3. **No customer demographics or acquisition date.** "New vs returning" cannot be determined —
   a customer whose first order falls in April 2018 may have been buying for years before the
   window opens. This is why the RFM segment is named *Recent High Spenders* rather than *New
   Customers*.
4. **One fiscal year, no prior period.** Year-over-year comparison is impossible, and seasonality
   cannot be separated from trend. The strong Q4 could be a seasonal peak or a genuine turnaround;
   one year of data cannot distinguish them.
5. **Small sample for repeat behaviour.** Only 70 customers ordered more than once and the maximum
   is 4 orders, so purchase-frequency findings are directional rather than robust.
6. **Revenue-only targets.** The target file sets no profit goal, which the analysis shows to be a
   meaningful gap (see Insight 7 in `business_insights.md`).
