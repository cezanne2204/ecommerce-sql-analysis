# Business Insights

Every number below was produced by a query in this repository and cross-checked against an
independent recomputation from the source CSVs. Each insight follows
**Finding → Why it matters → Recommendation**, and each names the query it comes from.

**Period:** 1 April 2018 – 31 March 2019 (FY2018-19) · **Revenue:** ₹431,502 ·
**Profit:** ₹23,955 · **Margin:** 5.55% · **Orders:** 500 · **Customers:** 401

---

## 1. The business was loss-making for half the year, then turned decisively

*Source: Q13, Q14 (`03_analysis.sql`)*

**Finding.** Profit was negative in **every one of the first six months** (Apr–Sep 2018),
accumulating a loss of **₹21,795**. From October 2018 onward it was positive in all six months,
earning **₹45,750**. Cumulative profit did not cross zero until **January 2019** — ten months in.
By fiscal quarter:

| Quarter | Revenue | Profit | Margin |
|---|---|---|---|
| Q1 Apr–Jun | 84,929 | −12,514 | −14.73% |
| Q2 Jul–Sep | 70,493 | −9,281 | −13.17% |
| Q3 Oct–Dec | 117,280 | +19,996 | **+17.05%** |
| Q4 Jan–Mar | 158,800 | +25,754 | **+16.22%** |

The swing is **~31 margin points**, and it is not a volume story: Q3 revenue was only 38% above
Q1, while profit moved by ₹32,510.

**Why it matters.** The headline 5.55% margin is a blend of two businesses that no longer exist in
the same form — a badly loss-making one and a healthily profitable one. Any forecast, valuation or
target built on the full-year average will be wrong in both directions. The relevant run-rate is
the **16–17% margin of the second half**, not 5.55%.

**Recommendation.** Restate the operating baseline on H2 only, and treat the full-year figure as
historical. The immediate priority is to establish *what changed in October* — pricing, discounting
policy, supplier terms or product mix — because that mechanism is the single most valuable piece of
knowledge the business has, and this dataset does not record it. Until it is identified, there is no
way to know whether the recovery is durable or a seasonal artefact.

---

## 2. Two loss-making sub-categories cost 22% of the year's profit

*Source: Q6 (`03_analysis.sql`)*

**Finding.** Only two of 17 sub-categories are loss-making, but their losses are large:

| Sub-category | Revenue | Profit | Margin | Loss-making lines |
|---|---|---|---|---|
| Tables | 22,614 | **−4,011** | −17.74% | 11 of 17 (64.7%) |
| Electronic Games | 39,168 | **−1,236** | −3.16% | 40 of 79 (50.6%) |

Together they destroyed **₹5,247**. Total profit was ₹23,955 — so without them profit would have
been **₹29,202, or 21.9% higher**.

Tables is the sharper problem. It has the **highest average line value of any sub-category
(₹1,330)** yet loses money on nearly two-thirds of its lines, and it did so on just 17 lines all
year — an average loss of ₹236 per line.

**Why it matters.** These are not marginal products being carried for range: Tables sells at the
highest price point in the catalogue and still loses on most transactions. That pattern points to
pricing or cost, not to demand.

**Recommendation.** Tables should be repriced or withdrawn pending review — with only 17 lines a
year, the revenue at risk (₹22,614, 5.2% of total) is small against a certain ₹4,011 profit gain.
Electronic Games needs a different treatment: at 79 lines and ₹39,168 it is a real volume line, so
withdrawal would leave a visible revenue hole; the loss is shallow (−3.16%) and a modest price or
cost correction would flip it. **Before either action**, confirm the loss is not an artefact of the
H1 period identified in Insight 1 — if these products were only unprofitable before October, the
problem may already be solved.

---

## 3. Saree is the largest hidden margin problem

*Source: Q4, Q5, Q7 (`03_analysis.sql`)*

**Finding.** Saree is the **third-largest revenue line in the business** (₹53,511, 12.4% of
revenue) and returns **₹352 of profit — a 0.66% margin**. Nearly half its lines (98 of 210, 46.7%)
lose money. For comparison, **T-shirt earns 4.3× Saree's profit (₹1,500) on 13.8% of its revenue**
(₹7,382). Saree also carries more order lines than any other sub-category (210 of 1,500).

Because it posts *positive* total profit, Saree passes every loss-making filter and never appears
on a problem list — it hides behind its own volume.

**Why it matters.** Saree ties up more working capital, inventory and fulfilment capacity than
almost any other line while contributing essentially nothing to the bottom line. Its profit is also
fragile: it depends on a handful of large wins offsetting 98 losing lines, so a small adverse shift
in mix turns it negative.

**Recommendation.** Treat Saree as the highest-value margin investigation in the catalogue, ahead
of Tables — the upside is larger. Moving Saree from 0.66% to the Clothing category average of 8.03%
would add roughly **₹3,900 of profit** on existing volume, more than eliminating Tables entirely,
with no revenue sacrificed. Start by segmenting its 210 lines into profitable and unprofitable
groups to establish whether the losses cluster by price point, geography, or period.

---

## 4. Clothing out-earns Electronics on 16% less revenue

*Source: Q3 (`03_analysis.sql`)*

**Finding.** Revenue rank and profit rank invert between the two largest categories:

| Category | Revenue | Rank | Profit | Rank | Margin | Units | Revenue/unit |
|---|---|---|---|---|---|---|---|
| Electronics | 165,267 | **1** | 10,494 | 2 | 6.35% | 1,154 | 143.21 |
| Clothing | 139,054 | 2 | **11,163** | **1** | **8.03%** | 3,516 | 39.55 |
| Furniture | 127,181 | 3 | 2,298 | 3 | **1.81%** | 945 | 134.58 |

Clothing generates more profit than Electronics on ₹26,213 less revenue. Furniture takes 29.5% of
revenue and returns 9.6% of profit.

**Why it matters.** Electronics is the natural focus of a revenue-led organisation — it is the
biggest line and beats its target by the widest margin (Insight 6). But Clothing is the better
business per rupee sold, and Furniture is close to unprofitable at 1.81%, a margin thin enough that
a modest cost movement would erase it.

**Recommendation.** Stop steering the category mix on revenue alone. Clothing warrants the larger
share of marketing and inventory investment on the strength of its margin — but note it is also the
category that **misses its target most consistently** (79.9% attainment, 9 of 12 months missed),
which suggests the target itself is mis-set rather than the category underperforming. See Insight 6.
Furniture needs a margin plan before it receives further volume investment: growing a 1.81% line
adds risk faster than profit.

---

## 5. Revenue concentration is geographic, and the largest market is the weakest earner

*Source: Q9, Q10, Q11 (`03_analysis.sql`)*

**Finding.** Two states — **Madhya Pradesh and Maharashtra — hold 46.5% of revenue** (₹200,488 of
₹431,502). The remaining 17 states share 53.5%. But the top market is the weaker earner:

| State | Revenue | Margin | Classification |
|---|---|---|---|
| Madhya Pradesh | 105,140 (24.4%) | **5.28%** | High revenue, weak profit |
| Maharashtra | 95,348 (22.1%) | 6.48% | Strong market |
| West Bengal | 14,086 | **17.75%** | Strong market |
| Uttar Pradesh | 22,359 | 14.48% | Strong market |
| Haryana | 8,863 | **14.95%** | Growth opportunity |
| Tamil Nadu | 6,087 | **−36.41%** | Underperforming |

Four states lose money outright: Tamil Nadu (−2,216), Punjab (−609), Andhra Pradesh (−496) and
Bihar (−321).

The sharpest contrast is **within** states, not between them. In Maharashtra, **Pune returns 13.56%
on ₹33,481 while Mumbai returns 2.65% on ₹61,867** — Pune earns ₹4,539 of profit against Mumbai's
₹1,637 on barely half the revenue, and has the **highest average order value of any city
(₹1,522 vs ₹910)**. In Rajasthan, Udaipur returns 18.15% while Jaipur returns −7.47%.

**Why it matters.** The two headline markets are being managed as one success story when they are
not comparable: Madhya Pradesh sells the most and earns a below-average margin. And the
Pune/Mumbai and Udaipur/Jaipur splits show that state-level reporting is hiding the actual unit of
performance — margin varies more *within* a state than across the country.

**Recommendation.** Move geographic reporting and target-setting to **city level**; state
aggregates are averaging away the signal that matters. Investigate Pune specifically — its
combination of the highest AOV and a 13.56% margin is the best customer economics in the dataset,
and if the cause is order mix rather than geography it is replicable in Mumbai, which is twice the
size. Tamil Nadu (−36.41% on only 8 orders) should be treated as a diagnostic case, not a market
decision: the sample is too small to justify exit, but large enough to warrant asking what went
wrong on eight orders.

---

## 6. Targets are set on last year's shape, and Clothing is being penalised for it

*Source: Q31, Q32, Q34 (`05_advanced_analysis.sql`)*

**Finding.** Full-year attainment diverges sharply by category:

| Category | Target | Actual | Achievement | Months hit |
|---|---|---|---|---|
| Electronics | 129,000 | 165,267 | **128.11%** | 9 of 12 |
| Furniture | 132,900 | 127,181 | 95.70% | 4 of 12 |
| Clothing | 174,000 | 139,054 | **79.92%** | **3 of 12** |

Clothing carries the **largest target of the three (₹174,000, 40% of total)** despite being the
second-largest category by revenue, and misses it in 9 months of 12. Electronics carries the
smallest target (₹129,000) and beats it by 28%.

Attainment is **improving in all three categories** H1→H2 (Furniture +59.8 pts, Electronics
+40.3 pts, Clothing +11.7 pts) — consistent with the turnaround in Insight 1. The worst month was
**July 2018 at 38.4% attainment**, when no category hit target.

**Why it matters.** A target that is missed 9 times out of 12 has stopped functioning as a target:
it no longer signals under-performance, because it signals it every month. Meanwhile Electronics'
target is soft enough that beating it by 28% carries no information either. The variance is telling
us more about how the targets were set than about how the categories performed — particularly
since Clothing is the **most profitable category** (Insight 4) and is the one being marked down.

**Recommendation.** Rebase targets for FY2019-20 on H2 FY2018-19 run-rate rather than on the full
year, and rebalance the split across categories — Clothing's target should fall relative to
Electronics'. Add a **profit or margin target alongside the revenue target**; see Insight 7 for why
this matters more than it appears.

---

## 7. Hitting the revenue target does coincide with profit — which is worth knowing, not assuming

*Source: Q35 (`05_advanced_analysis.sql`)*

**Finding.** Across the 36 month × category cells:

| Target status | Cells | Revenue | Profit | Margin |
|---|---|---|---|---|
| Hit | 16 | 259,474 | **+30,706** | **+11.83%** |
| Miss | 20 | 172,028 | **−6,751** | **−3.92%** |

Cells that hit their revenue target earned an 11.83% margin. Cells that missed **lost money
outright**. The gap is nearly 16 margin points.

**Why it matters.** The targets are revenue-only, so there was no guarantee they pointed anywhere
profitable — a revenue target can easily be met by discounting into a loss, and this is exactly how
revenue-only incentives fail. The data shows that did **not** happen here: chasing this revenue
target happened to produce profit. That is a genuine, testable validation of the existing incentive
structure rather than an assumption.

**Recommendation.** The relationship holds in aggregate but is **correlation on 36 observations
within a single year**, and it is confounded by Insight 1 — most target hits fall in H2, which was
profitable for reasons that may have nothing to do with targets. Do not treat revenue attainment as
a profit proxy going forward. Add an explicit margin target, which costs nothing and removes the
dependence on a relationship that could break the moment discounting is used to close a gap.

---

## 8. The customer base is wide, shallow and dangerously concentrated

*Source: Q17, Q18, Q19, Q22 (`05_advanced_analysis.sql`)*

**Finding.** **82.5% of customers (331 of 401) ordered exactly once**, and they account for
**67.1% of revenue**. Only 70 customers ordered more than once; the maximum in the entire year is
four orders.

Concentration is severe: **59 customers — 14.7% of the base — generate 50% of revenue**, and 146
(36.4%) generate 80%. The 139 above-average spenders account for 78.4% of revenue.

Repeat customers are **not** more profitable per rupee (5.08% margin vs 5.78% for one-time buyers),
though they spend 2.3× more in total (₹2,030 vs ₹874).

Among the 70 repeat customers, **35 are declining and 32 growing** — spend falls as often as it
rises. The typical gap between a first and second order is **281 days**, but between second and
third only **37 days**: customers who return a second time re-order quickly.

**Why it matters.** Two-thirds of revenue comes from customers with no demonstrated intention of
returning, and half of it from 59 people. Losing a handful of top customers would be material.
The 281-day-then-37-day pattern is the most actionable finding here: **the second order is the
bottleneck**. Once a customer places it, the third follows quickly.

**Recommendation.** Concentrate retention spend entirely on converting the **first order to a
second**, within a window far shorter than 281 days — that single transition is where the base is
leaking. Note the caveat: with one year of data, a "one-time customer" may simply have ordered
before the window opened, so this over-states churn to an unknown degree; a second year would
resolve it. Do not build a loyalty programme on the assumption that repeat customers are more
profitable — at 5.08% vs 5.78% they are not.

---

## 9. The highest-spending lapsed customers were also the least profitable

*Source: Q24, Q25 (`05_advanced_analysis.sql`)*

**Finding.** The RFM segmentation produces a counter-intuitive result:

| Segment | Customers | Revenue | % of revenue | Margin | Avg days since order |
|---|---|---|---|---|---|
| Needs Attention | 84 | 96,324 | 22.3% | +13.53% | 175 |
| Loyal Customers | 40 | 88,690 | 20.6% | +5.66% | 37 |
| **At Risk** | **47** | **85,322** | **19.8%** | **−12.12%** | **233** |
| Recent High Spenders | 34 | 77,346 | 17.9% | +16.70% | 71 |
| Champions | 20 | 51,409 | 11.9% | +3.74% | 6 |
| Hibernating | 74 | 9,337 | 2.2% | −20.09% | 235 |

**At Risk** — high spenders who have not purchased in an average of 233 days — hold nearly a fifth
of revenue and **lost the business ₹10,345**. Champions, the most active segment, return only
3.74%. The best margins come from *Recent High Spenders* (16.70%) and *Needs Attention* (13.53%).

**Why it matters.** This inverts the standard win-back playbook. The conventional response to a
19.8%-of-revenue At Risk segment is an aggressive reactivation campaign — but these customers were
**unprofitable while they were active**. Winning them back at the same economics would deepen the
loss, and discounting to do it would deepen it further. Note also that At Risk customers are
concentrated in the earlier, loss-making months (233 days before 31 March 2019 is mid-August 2018),
so this segment substantially overlaps the H1 problem in Insight 1 — the segmentation may be
identifying *when* they bought as much as *who* they are.

**Recommendation.** Do **not** run an undifferentiated win-back on the At Risk segment. Split it
first by profitability and re-approach only the profitable half, at full price. For the
loss-making remainder, establish whether the losses came from product mix (Tables, Saree,
Electronic Games) or from the H1 period before re-engaging at all. Prioritise instead the
34 *Recent High Spenders* — ₹2,275 average spend at a 16.70% margin, purchased within ~71 days —
who are the most valuable and most winnable group in the base.

---

## 10. Weekend orders are larger but far less profitable

*Source: Q15 (`03_analysis.sql`)*

**Finding.** Order value and margin move in opposite directions across the week:

| Day | Orders | Avg order value | Margin |
|---|---|---|---|
| Sunday | 77 | **₹1,145** (highest) | **2.42%** |
| Monday | 81 | ₹837 | **−5.29%** |
| Saturday | 71 | **₹652** (lowest) | **13.77%** |
| Wednesday | 55 | ₹795 | 12.65% |
| Thursday | 74 | ₹960 | 11.54% |

Sunday has the **highest average order value and nearly the worst margin**; Saturday has the
**lowest order value and the best margin**. Monday is the only day that loses money.

**Why it matters.** Larger orders are systematically less profitable, which points to
basket composition or discounting on high-value baskets rather than to anything about the day
itself. The Sunday/Saturday inversion is the clearest evidence in the dataset that **order size and
order quality are negatively related** — a pattern that also shows up in Insight 2 (Tables: highest
line value, worst margin).

**Recommendation.** Treat this as a lead on basket economics, not a scheduling insight. Caveat
clearly: this is 500 orders spread across seven days, 40–50 orders per weekday, so day-level margin
differences are not statistically robust on their own. **Insight 11 tests the underlying "big
baskets are bad" hypothesis directly and largely refutes it** — so this should not be acted on
alone.

---

## 11. "Bigger orders are worse orders" is false — the real driver is category mix

*Source: Q36, Q37, Q38 (`05_advanced_analysis.sql`)*

**Finding.** Three separate results pointed the same way — Tables has the highest line value and the
worst margin (Insight 2), Sunday has the highest AOV and nearly the worst margin (Insight 10), and
Saree turns over heavily at 0.66% (Insight 3). Tested directly at order level, **the hypothesis does
not hold:**

| Order size | Orders | Revenue | Profit | Margin | Avg order value |
|---|---|---|---|---|---|
| 1 line | 235 | 62,881 | 1,586 | 2.52% | 268 |
| 2 lines | 28 | 15,793 | 2,017 | **12.77%** | 564 |
| 3–4 lines | 122 | 120,449 | 7,267 | 6.03% | 987 |
| 5–6 lines | 63 | 103,684 | 1,707 | **1.65%** | 1,646 |
| **7+ lines** | 52 | 128,695 | **11,378** | **8.84%** | **2,475** |

Margin is **not monotonic in order size**. The largest orders (7+ lines, average value ₹2,475) are
the **most profitable group in the business** — they generate 47.5% of all profit on 10.4% of
orders. The weak bucket is the middle (5–6 lines, 1.65%), not the top.

What *does* predict margin is **which categories are in the basket**:

| Category mix | Orders | Revenue | Profit | Margin | Avg order value |
|---|---|---|---|---|---|
| Electronics + Clothing | 73 | 99,539 | 9,189 | **+9.23%** | 1,364 |
| Clothing + Furniture | 49 | 53,237 | 4,318 | +8.11% | 1,086 |
| Clothing only | 195 | 47,206 | 3,575 | +7.57% | 242 |
| Furniture only | 52 | 21,974 | 1,039 | +4.73% | 423 |
| All three | 76 | 175,420 | 6,460 | +3.68% | 2,308 |
| **Electronics only** | 46 | 23,777 | **−1,376** | **−5.79%** | 517 |

**Electronics sold on its own loses money.** Sold alongside Clothing, the same category sits in the
most profitable basket in the business. Separately, orders containing Furniture return 4.82% versus
6.68% for orders without it — a real but modest drag, and those orders are 2.6× larger.

**Why it matters.** This overturns the intuitive reading of Insights 2, 3 and 10 and changes what
should be done about them. Discouraging large baskets — the natural response to "big orders lose
money" — would have removed the most profitable segment of the business. The actual problem is
narrower and more tractable: **standalone Electronics orders**, and Clothing's role as the margin
carrier that rescues baskets it appears in.

It also reframes Insight 4. Clothing is not merely the highest-margin category in isolation; it
appears to be what makes other categories profitable when bundled with it.

**Recommendation.** Target the 46 standalone-Electronics orders directly — attach a Clothing item
through bundling, cross-sell or a basket threshold, since the same Electronics units earn +9.23%
when they travel with Clothing instead of −5.79% alone. Do **not** impose minimum-basket rules or
discourage large orders. Two caveats: the all-three-category basket is large but only 3.68%, so the
attach effect is not linear and should not be extrapolated; and with 46 standalone-Electronics
orders this is a directional finding, worth a controlled test rather than an immediate policy change.

---

## Cross-cutting recommendations, in priority order

1. **Identify what changed in October 2018.** A 31-point margin swing is the largest single fact in
   this dataset and its cause is not recorded. Everything else is secondary to knowing whether the
   recovery is repeatable. *(Insight 1)*
2. **Run a margin review on Saree, Tables and Electronic Games together.** Combined, they represent
   roughly ₹9,000 of recoverable profit against a current base of ₹23,955 — a ~38% uplift with no
   revenue growth required. *(Insights 2, 3)*
3. **Attack standalone-Electronics orders, not large baskets.** The same Electronics units earn
   +9.23% beside Clothing and −5.79% alone. Do not discourage big orders — 7+ line orders are the
   most profitable group in the business. *(Insight 11)*
4. **Rebase FY2019-20 targets on H2 run-rate and add a margin target.** Current targets misfire in
   both directions and steer only on revenue. *(Insights 6, 7)*
5. **Move geographic management to city level** and diagnose Pune's economics for replication in
   Mumbai. *(Insight 5)*
6. **Focus retention entirely on the first-to-second order transition**, and segment the At Risk
   group by profitability before spending anything on win-back. *(Insights 8, 9)*
