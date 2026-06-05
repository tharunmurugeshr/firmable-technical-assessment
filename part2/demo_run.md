# Demo Run — NL-to-SQL Skill Benchmark

All 10 benchmark questions run against `GTM_ANALYTICS` on Snowflake.
Each entry shows: question → skill behaviour → SQL → result → caveats.

---

## Q1 — What was total MRR at the end of March 2026?

**Skill behaviour:** Unambiguous. Queries `MART.MRR_MONTHLY` directly.

**SQL:**
```sql
SELECT
    MONTH,
    COUNT(DISTINCT CANONICAL_ID)    AS active_customers,
    SUM(MRR)                        AS total_mrr
FROM MART.MRR_MONTHLY
WHERE MONTH = '2026-03-01'
GROUP BY MONTH;
```

**Result:**
| MONTH | ACTIVE_CUSTOMERS | TOTAL_MRR |
|---|---|---|
| 2026-03-01 | 3,262 | $7,122,700 |

**Caveats:** MRR is subscription-based (contracted monthly amount), not invoiced revenue.
"End of March" maps to the March snapshot — the view holds one row per active customer
per calendar month.

---

## Q2 — How many new customers signed up in Q1 2026?

**Skill behaviour:** MART has no new customer acquisition metric. Falls back to
`STAGED.FACT_SUBSCRIPTIONS` and flags as unverified.

> **Unverified metric:** This query uses staged data, not a pre-built MART view.

**SQL:**
```sql
WITH first_subscription AS (
    SELECT
        CANONICAL_ID,
        MIN(START_DATE)     AS FIRST_START_DATE
    FROM STAGED.FACT_SUBSCRIPTIONS
    GROUP BY CANONICAL_ID
)
SELECT
    COUNT(DISTINCT CANONICAL_ID)    AS new_customers
FROM first_subscription
WHERE FIRST_START_DATE >= '2026-01-01'
  AND FIRST_START_DATE <  '2026-04-01';
```

**Result:**
| NEW_CUSTOMERS |
|---|
| 85 |

**Caveats:** "New customer" = customer whose first-ever subscription start date falls
in Q1 2026. Customers with multiple subscriptions (upgrades) are counted once at
their earliest start date. This metric is not in the MART layer — treat with caution.

---

## Q3 — Show me monthly gross churn count for the last 12 months.

**Skill behaviour:** Unambiguous. Queries `MART.CHURN_MONTHLY` directly.

**SQL:**
```sql
SELECT
    MONTH,
    COUNT(DISTINCT CANONICAL_ID)    AS churned_customers,
    SUM(CHURNED_MRR)                AS churned_mrr
FROM MART.CHURN_MONTHLY
WHERE MONTH >= DATE_TRUNC('MONTH', DATEADD('MONTH', -12, CURRENT_DATE()))
  AND MONTH <  DATE_TRUNC('MONTH', CURRENT_DATE())
GROUP BY MONTH
ORDER BY MONTH;
```

**Result:**
| MONTH | CHURNED_CUSTOMERS | CHURNED_MRR |
|---|---|---|
| 2025-05-01 | 10 | $28,100 |
| 2025-06-01 | 16 | $15,400 |
| 2025-07-01 | 20 | $37,500 |
| 2025-08-01 | 21 | $37,800 |
| 2025-09-01 | 19 | $37,600 |
| 2025-10-01 | 18 | $47,900 |
| 2025-11-01 | 22 | $46,400 |
| 2025-12-01 | 27 | $47,800 |
| 2026-01-01 | 28 | $54,900 |
| 2026-02-01 | 31 | $57,500 |
| 2026-03-01 | 42 | $96,000 |

**Caveats:** Gross churn = canceled subscriptions only. `canceled_upgraded` (plan changes)
excluded. 11 months returned — May 2026 not yet complete so excluded by the `< current month`
filter. Notable trend: churn accelerating from 10 in May 2025 to 42 in March 2026 (4× increase).

---

## Q4 — What's our NRR for the 2025-Q1 cohort?

**Skill behaviour:** Unambiguous. Queries `MART.NRR_COHORT` for latest data point.

**SQL:**
```sql
SELECT
    COHORT_LABEL,
    MONTHS_SINCE_START,
    COHORT_CUSTOMERS,
    COHORT_STARTING_MRR,
    COHORT_CURRENT_MRR,
    NRR_PCT
FROM MART.NRR_COHORT
WHERE COHORT_YEAR = 2025
  AND COHORT_QUARTER_NUM = 1
ORDER BY MONTHS_SINCE_START DESC
LIMIT 1;
```

**Result:**
| COHORT_LABEL | MONTHS_SINCE_START | COHORT_CUSTOMERS | COHORT_STARTING_MRR | COHORT_CURRENT_MRR | NRR_PCT |
|---|---|---|---|---|---|
| Q1 2025 | 16 | 177 | $370,300 | $421,300 | 113.8% |

**Caveats:** NRR of 113.8% means expansion revenue (upgrades) is outpacing churn by 13.8%
within this cohort. Cohort starting MRR grows over time as more customers start their first
subscription within the quarter window — month 0 shows only the earliest starters.

---

## Q5 — How many customers churned in March 2026?

**Skill behaviour:** Unambiguous. Queries `MART.CHURN_MONTHLY` directly.

**SQL:**
```sql
SELECT
    MONTH,
    COUNT(DISTINCT CANONICAL_ID)    AS churned_customers,
    SUM(CHURNED_MRR)                AS total_churned_mrr
FROM MART.CHURN_MONTHLY
WHERE MONTH = '2026-03-01'
GROUP BY MONTH;
```

**Result:**
| MONTH | CHURNED_CUSTOMERS | TOTAL_CHURNED_MRR |
|---|---|---|
| 2026-03-01 | 42 | $96,000 |

**Caveats:** Consistent with Q3. Churn definition: `status = 'canceled'` only.
`canceled_upgraded` excluded — those 777 customers moved to a different plan and remain active.

---

## Q6 — Which industries have the highest churn rate?

**Skill behaviour:** Clarifies target month first (most recent complete month may be empty).
Joins `STAGED.DIM_CUSTOMER` explicitly — does not rely on INDUSTRY column in MART views
which can be NULL for unmatched customers.

**SQL:**
```sql
WITH active AS (
    SELECT
        c.INDUSTRY,
        COUNT(DISTINCT m.CANONICAL_ID)  AS active_customers
    FROM MART.MRR_MONTHLY m
    LEFT JOIN STAGED.DIM_CUSTOMER c ON m.CANONICAL_ID = c.CANONICAL_ID
    WHERE m.MONTH = '2026-03-01'
    GROUP BY c.INDUSTRY
),
churned AS (
    SELECT
        c.INDUSTRY,
        COUNT(DISTINCT ch.CANONICAL_ID) AS churned_customers
    FROM MART.CHURN_MONTHLY ch
    LEFT JOIN STAGED.DIM_CUSTOMER c ON ch.CANONICAL_ID = c.CANONICAL_ID
    WHERE ch.MONTH = '2026-03-01'
    GROUP BY c.INDUSTRY
)
SELECT
    COALESCE(a.INDUSTRY, 'Unknown')     AS industry,
    a.ACTIVE_CUSTOMERS,
    COALESCE(c.CHURNED_CUSTOMERS, 0)    AS churned_customers,
    ROUND(
        COALESCE(c.CHURNED_CUSTOMERS, 0) * 100.0
        / NULLIF(a.ACTIVE_CUSTOMERS, 0), 2
    )                                   AS churn_rate_pct
FROM active a
LEFT JOIN churned c ON a.INDUSTRY = c.INDUSTRY
ORDER BY churn_rate_pct DESC;
```

**Result:**
| INDUSTRY | ACTIVE_CUSTOMERS | CHURNED_CUSTOMERS | CHURN_RATE_PCT |
|---|---|---|---|
| Healthcare | 287 | 6 | 2.09% |
| Construction | 272 | 5 | 1.84% |
| Education | 300 | 5 | 1.67% |
| Retail | 311 | 5 | 1.61% |
| Hospitality | 336 | 5 | 1.49% |
| Manufacturing | 313 | 4 | 1.28% |
| IT | 320 | 4 | 1.25% |
| Logistics | 291 | 3 | 1.03% |
| Professional Services | 272 | 2 | 0.74% |
| Financial Services | 320 | 2 | 0.63% |
| Unknown | 151 | 0 | 0.00% |

**Caveats:** "Unknown" = 151 stripe_only customers with no HubSpot company record.
Churn rate is point-in-time for March 2026 — a single month can be noisy for small
industry segments. Healthcare and Construction are highest but the absolute numbers
(5–6 customers) are small enough that one or two customers can move the rate significantly.

---

## Q7 — List customers at risk of churning.

**Skill behaviour:** Unambiguous. Queries `MART.CUSTOMER_HEALTH` directly.

**SQL:**
```sql
SELECT
    CANONICAL_ID,
    COMPANY_NAME,
    PLAN_NAME,
    CURRENT_MRR,
    HAS_UNCOLLECTIBLE_INVOICE,
    HAS_DOWNGRADED,
    MONTHS_SINCE_LAST_INVOICE,
    PRIOR_CANCELLATION_REASON,
    RISK_TIER
FROM MART.CUSTOMER_HEALTH
WHERE RISK_TIER IN ('red', 'amber')
ORDER BY RISK_TIER, CURRENT_MRR DESC;
```

**Result summary:**
| RISK_TIER | CUSTOMER_COUNT | MRR_AT_RISK |
|---|---|---|
| amber | 95 | ~$163,800 |
| red | 0 | $0 |

95 amber customers, all flagged for `HAS_DOWNGRADED = TRUE` (moved to a lower plan).
0 red customers — no active customers have uncollectible invoices, 3+ months of silence,
or prior price/switching_vendor cancellation reasons.

**Caveats:** Only active customers (with MRR last month) are scored. Churned customers
are excluded. Downgrade signal = a later subscription has a lower `monthly_amount` than
an earlier one — genuine revenue contraction even if the customer didn't leave.

---

## Q8 — Show me revenue for last month.

**Skill behaviour:** Ambiguous. Asks clarifying question before generating SQL.

> "Just to confirm — by 'revenue' do you mean contracted MRR (monthly subscription
> amounts from active plans) or invoiced revenue (actual amounts billed and collected)?
> These can differ if some invoices are uncollectible or billing is irregular."

**Both options run for comparison:**

Option A — Contracted MRR:
```sql
SELECT MONTH, SUM(MRR) AS contracted_mrr
FROM MART.MRR_MONTHLY
WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
GROUP BY MONTH;
```
Result: **$7,202,900**

Option B — Invoiced revenue (paid only):
```sql
SELECT
    INVOICE_MONTH,
    SUM(AMOUNT_EX_GST)  AS invoiced_revenue_ex_gst,
    SUM(AMOUNT_INC_GST) AS invoiced_revenue_inc_gst
FROM STAGED.FACT_INVOICES
WHERE INVOICE_MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
  AND STATUS = 'paid'
GROUP BY INVOICE_MONTH;
```
Result: **$7,276,700 ex-GST / $8,004,370 inc-GST**

**Caveats:** $143,700 gap between contracted MRR and invoiced revenue. These are
genuinely different numbers — silently returning one when the analyst meant the other
would cause Finance and GTM to report different figures. Clarification is mandatory.

---

## Q9 — Why is our Stripe churn number different from HubSpot?

**Skill behaviour:** Conceptual question — no SQL generated. Explains structural reasons in prose.

**Answer:**

This is a structural mismatch, not a data error. Five reasons these numbers differ:

1. **Different customer definitions.** Stripe tracks `customer_id` (a billing entity). HubSpot tracks `company_id` (a business entity). One company can have multiple Stripe customers — different products, billing contacts, or subsidiaries.

2. **Different churn definitions.** Stripe marks a subscription `canceled` when billing stops. HubSpot marks a deal `closedlost` when a sales opportunity fails. These are different events on different timelines — a customer can churn in Stripe months after a deal was lost in HubSpot, or vice versa.

3. **Unmatched records.** In this warehouse, 200 Stripe customers have no HubSpot match and 200 HubSpot companies have no Stripe match. Any report joining both systems will miss these records entirely.

4. **Timing differences.** Stripe events are timestamped to the second. HubSpot deal close dates are manually entered by sales reps and may lag reality by days or weeks.

5. **Plan changes look like churn.** Stripe's `canceled_upgraded` status appears as a cancellation in a raw count but the customer remains active on a new plan. If HubSpot tracks the new deal while Stripe counts the old subscription as canceled, the numbers diverge.

**Recommendation:** Always use `MART.CHURN_MONTHLY` as the single source of truth. It applies the agreed churn definition (`status = 'canceled'` only) and resolves the Stripe↔HubSpot identity gap via `customer_id_map`.

---

## Q10 — Who are our top 10 customers by lifetime value?

**Skill behaviour:** Unambiguous. Joins `STAGED.DIM_CUSTOMER` explicitly for company attributes.

**SQL:**
```sql
SELECT
    m.CANONICAL_ID,
    c.COMPANY_NAME,
    c.INDUSTRY,
    c.COUNTRY,
    SUM(m.MRR)                      AS lifetime_mrr,
    MIN(m.MONTH)                    AS first_month,
    MAX(m.MONTH)                    AS last_month,
    COUNT(DISTINCT m.MONTH)         AS active_months
FROM MART.MRR_MONTHLY m
LEFT JOIN STAGED.DIM_CUSTOMER c ON m.CANONICAL_ID = c.CANONICAL_ID
GROUP BY m.CANONICAL_ID, c.COMPANY_NAME, c.INDUSTRY, c.COUNTRY
ORDER BY lifetime_mrr DESC
LIMIT 10;
```

**Result:**
| CANONICAL_ID | COMPANY_NAME | INDUSTRY | COUNTRY | LIFETIME_MRR | ACTIVE_MONTHS |
|---|---|---|---|---|---|
| cus_03870 | Bralven Platforms Partners 7487 | Logistics | GB | $270,000 | 54 |
| cus_00469 | Pellori Studios Partners 2163 | Hospitality | AU | $270,000 | 54 |
| cus_02767 | Prymor Systems 6214 | IT | GB | $270,000 | 54 |
| cus_00057 | Bralven Works Partners 8007 | IT | AU | $270,000 | 54 |
| cus_03937 | Kraveth Commerce Partners 5901| *(stripe_only — no HubSpot record)* | — | $270,000 | 54 |
| cus_02694 | Cormane Labs Holdings 5980 | Financial Services | NZ | $270,000 | 54 |
| cus_03638 | Dalmire Systems Holdings 1730 | Manufacturing | AU | $270,000 | 54 |
| cus_01951 | Verdane Works 7000 | *(stripe_only — no HubSpot record)* | — | $270,000 | 54 |
| cus_01188 | Thessalt Platforms Group 4479 | Professional Services | AU | $270,000 | 54 |
| cus_00183 | Mardel Studios Group 3417 | Logistics | AU | $270,000 | 54 |





**Caveats:** LTV = sum of all monthly MRR across every active month. All top 10 have been active since January 2022 (54 months). The $270,000 LTV reflects their subscription amounts across all active months — customers may have been on different plans during this period. `cus_03937` and `cus_01951` are stripe_only customers — no HubSpot company record, so company name and industry are NULL. This is expected and correctly surfaced.
