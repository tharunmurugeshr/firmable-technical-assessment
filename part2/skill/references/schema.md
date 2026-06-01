# Schema Reference — GTM Analytics

Full column-level definitions for every table and view in the warehouse.
Load this file when writing complex queries or debugging unexpected results.

---

## MART Layer

### MART.MRR_MONTHLY
**Grain:** One row per active customer per calendar month
**Source:** Built from `STAGED.FACT_SUBSCRIPTIONS`, excludes churned and upgraded subscriptions

| Column | Type | Description |
|---|---|---|
| `MONTH` | DATE | First day of the calendar month (e.g. 2026-04-01) |
| `CANONICAL_ID` | VARCHAR | Customer identifier (Stripe customer_id for matched/stripe-only; HubSpot company_id for hubspot-only) |
| `COMPANY_NAME` | VARCHAR | Company name from HubSpot (NULL for stripe_only customers) |
| `COUNTRY` | VARCHAR | Country code from HubSpot (AU, NZ, SG, GB, US) |
| `INDUSTRY` | VARCHAR | Industry from HubSpot (Education, Healthcare, IT, Retail, etc.) |
| `PLAN_NAME` | VARCHAR | Stripe plan name (Starter, Growth, Business, Enterprise, Enterprise Plus) |
| `MRR` | NUMBER(12,2) | Monthly recurring revenue for this customer this month |
| `CUMULATIVE_MRR` | NUMBER(12,2) | Running total MRR for this customer since their first subscription |

**Common filters:**
- Last month: `WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))`
- Specific month: `WHERE MONTH = '2026-01-01'`
- By plan: `WHERE PLAN_NAME = 'Enterprise'`
- By country: `WHERE COUNTRY = 'AU'`

---

### MART.CHURN_MONTHLY
**Grain:** One row per churned subscription (status = 'canceled' only)
**Source:** Built from `STAGED.FACT_SUBSCRIPTIONS` where `IS_CHURNED = TRUE`

| Column | Type | Description |
|---|---|---|
| `MONTH` | DATE | First day of the month the subscription ended |
| `CANONICAL_ID` | VARCHAR | Customer identifier |
| `COMPANY_NAME` | VARCHAR | Company name from HubSpot |
| `COUNTRY` | VARCHAR | Country code |
| `INDUSTRY` | VARCHAR | Industry |
| `PLAN_NAME` | VARCHAR | Plan that was canceled |
| `CHURNED_MRR` | NUMBER(12,2) | MRR lost from this cancellation |
| `CANCELLATION_REASON` | VARCHAR | Reason for cancellation: `customer_request`, `price`, `switching_vendor`, `product_fit`, `involuntary`, `plan_change` (NULL if not provided) |

**Note:** `canceled_upgraded` subscriptions are NOT in this view — they are plan changes,
not churn. A customer upgrading from Starter to Enterprise will have a `canceled_upgraded`
old subscription and a new active one.

---

### MART.NRR_COHORT
**Grain:** One row per cohort per month offset since cohort start
**Source:** Built from `STAGED.FACT_SUBSCRIPTIONS` and `MART.MRR_MONTHLY`

| Column | Type | Description |
|---|---|---|
| `COHORT_QUARTER` | DATE | First day of the cohort's starting quarter (e.g. 2025-01-01 for Q1 2025) |
| `COHORT_YEAR` | NUMBER | Year of the cohort (e.g. 2025) |
| `COHORT_QUARTER_NUM` | NUMBER | Quarter number 1-4 |
| `COHORT_LABEL` | VARCHAR | Human-readable label (e.g. "Q1 2025") |
| `MONTHS_SINCE_START` | NUMBER | Months elapsed since cohort's first subscription (0 = starting month) |
| `COHORT_CUSTOMERS` | NUMBER | Number of customers in cohort active at this month offset |
| `COHORT_STARTING_MRR` | NUMBER(12,2) | Total MRR of cohort at month 0 |
| `COHORT_CURRENT_MRR` | NUMBER(12,2) | Total MRR of cohort at this month offset |
| `NRR_PCT` | NUMBER(5,1) | Net Revenue Retention % = (current_mrr / starting_mrr) * 100 |

**Interpretation:**
- NRR = 100%: cohort revenue is flat (churn exactly offset by expansion)
- NRR > 100%: expansion revenue exceeds churn (healthy growth)
- NRR < 100%: churn exceeds expansion (revenue contraction)

---

### MART.CUSTOMER_HEALTH
**Grain:** One row per active customer (customers with MRR in the last month)
**Source:** Built from STAGED layer with risk signal logic applied

| Column | Type | Description |
|---|---|---|
| `CANONICAL_ID` | VARCHAR | Customer identifier |
| `COMPANY_NAME` | VARCHAR | Company name |
| `COUNTRY` | VARCHAR | Country code |
| `INDUSTRY` | VARCHAR | Industry |
| `PLAN_NAME` | VARCHAR | Current plan name |
| `CURRENT_MRR` | NUMBER(12,2) | MRR from last month |
| `HAS_UNCOLLECTIBLE_INVOICE` | BOOLEAN | TRUE if any invoice is marked uncollectible |
| `HAS_DOWNGRADED` | BOOLEAN | TRUE if a later subscription has lower monthly_amount than an earlier one |
| `MONTHS_SINCE_LAST_INVOICE` | NUMBER | Months since most recent invoice date |
| `PRIOR_CANCELLATION_REASON` | VARCHAR | If customer previously churned with reason `price` or `switching_vendor` |
| `RISK_TIER` | VARCHAR | `red` (high risk), `amber` (medium risk), `green` (healthy) |

**Risk tier logic:**
- `red`: HAS_UNCOLLECTIBLE_INVOICE = TRUE, OR MONTHS_SINCE_LAST_INVOICE >= 3, OR PRIOR_CANCELLATION_REASON IS NOT NULL
- `amber`: HAS_DOWNGRADED = TRUE (and no red signals)
- `green`: No risk signals

---

## STAGED Layer

### STAGED.DIM_CUSTOMER
**Grain:** One row per unique customer across Stripe and HubSpot
**Note:** Use for customer attributes and identity resolution. Not for metrics.

| Column | Type | Description |
|---|---|---|
| `CANONICAL_ID` | VARCHAR | Primary key — Stripe customer_id if available, else HubSpot company_id |
| `STRIPE_CUSTOMER_ID` | VARCHAR | Stripe customer ID (cus_XXXXX). NULL for hubspot_only customers |
| `HUBSPOT_COMPANY_ID` | VARCHAR | HubSpot company ID (hs_XXXXX). NULL for stripe_only customers |
| `COMPANY_NAME` | VARCHAR | Company name from HubSpot. NULL for stripe_only customers |
| `INDUSTRY` | VARCHAR | Industry from HubSpot |
| `COUNTRY` | VARCHAR | Country code from HubSpot |
| `EMPLOYEES` | NUMBER | Employee count from HubSpot |
| `IS_MATCHED` | BOOLEAN | TRUE if customer exists in both Stripe and HubSpot |
| `MATCH_SOURCE` | VARCHAR | `both`, `stripe_only`, or `hubspot_only` |

**Counts:** 3,800 both | 200 stripe_only | 200 hubspot_only = 4,200 total

---

### STAGED.FACT_SUBSCRIPTIONS
**Grain:** One row per Stripe subscription

| Column | Type | Description |
|---|---|---|
| `SUBSCRIPTION_ID` | VARCHAR | Stripe subscription ID (sub_XXXXXX) |
| `CUSTOMER_ID` | VARCHAR | Stripe customer ID |
| `CANONICAL_ID` | VARCHAR | Resolved customer ID |
| `PLAN_NAME` | VARCHAR | Plan name (Starter, Growth, Business, Enterprise, Enterprise Plus) |
| `MONTHLY_AMOUNT` | NUMBER(12,2) | Monthly subscription amount in AUD |
| `START_DATE` | DATE | Subscription start date |
| `END_DATE` | DATE | Subscription end date (NULL if still active) |
| `STATUS` | VARCHAR | `active`, `canceled`, `canceled_upgraded` |
| `CANCELLATION_REASON` | VARCHAR | Why it was canceled (NULL if active) |
| `IS_CHURNED` | BOOLEAN | TRUE only if STATUS = 'canceled' |
| `IS_UPGRADED` | BOOLEAN | TRUE only if STATUS = 'canceled_upgraded' |
| `COHORT_QUARTER` | DATE | First day of the quarter of START_DATE |
| `COHORT_YEAR` | NUMBER | Year of START_DATE |
| `COHORT_QUARTER_NUM` | NUMBER | Quarter number 1-4 of START_DATE |

**Status breakdown:** 3,558 active | 777 canceled_upgraded | 442 canceled

---

### STAGED.FACT_INVOICES
**Grain:** One row per Stripe invoice

| Column | Type | Description |
|---|---|---|
| `INVOICE_ID` | VARCHAR | Stripe invoice ID (in_XXXXXXXX) |
| `CUSTOMER_ID` | VARCHAR | Stripe customer ID |
| `CANONICAL_ID` | VARCHAR | Resolved customer ID |
| `SUBSCRIPTION_ID` | VARCHAR | Related subscription ID |
| `INVOICE_DATE` | DATE | Date the invoice was issued |
| `INVOICE_MONTH` | DATE | First day of the invoice month |
| `INVOICE_QUARTER` | DATE | First day of the invoice quarter |
| `AMOUNT_EX_GST` | NUMBER(12,2) | Amount excluding GST (AUD) |
| `AMOUNT_INC_GST` | NUMBER(12,2) | Amount including GST (AUD, typically 10% higher) |
| `CURRENCY` | VARCHAR | Currency code (AUD) |
| `STATUS` | VARCHAR | `paid` or `uncollectible` |

**Counts:** 107,418 paid | 133 uncollectible

---

### STAGED.FACT_DEALS
**Grain:** One row per HubSpot deal

| Column | Type | Description |
|---|---|---|
| `DEAL_ID` | VARCHAR | HubSpot deal ID (deal_XXXXXX) |
| `HUBSPOT_COMPANY_ID` | VARCHAR | HubSpot company ID |
| `STRIPE_CUSTOMER_ID` | VARCHAR | Stripe customer ID (from deal properties) |
| `CANONICAL_ID` | VARCHAR | Resolved customer ID |
| `PIPELINE` | VARCHAR | HubSpot pipeline name |
| `DEALSTAGE` | VARCHAR | Deal stage (`closedwon`, `closedlost`, `qualifiedtobuy`, etc.) |
| `AMOUNT` | NUMBER(12,2) | Deal value in AUD |
| `CLOSE_DATE` | DATE | Deal close date |
| `DEAL_OWNER_ID` | VARCHAR | Sales rep ID (user_XXX) |
| `CAMPAIGN_SOURCE` | VARCHAR | Lead source: `Inbound`, `Outbound`, `Event`, `PLG`, `Partner`, or NULL |
| `DEAL_PRIORITY` | VARCHAR | `high`, `medium`, `low` |
| `FORECAST_CATEGORY` | VARCHAR | `closed`, `commit`, `best_case` |
| `DISCOUNT_PCT` | NUMBER(5,2) | Discount applied as a decimal (e.g. 0.16 = 16%) |

**Deal stage counts:** 3,800 closedwon | 286 closedlost | 200 qualifiedtobuy | other pipeline stages

**Deal stage decoding:** Raw pipeline/dealstage values are opaque HubSpot IDs.
Always decode using the CASE expression in SKILL.md before presenting results.

| PIPELINE | DEALSTAGE | Human Label |
|---|---|---|
| `default` | `closedwon` | Won — Core |
| `default` | `closedlost` | Lost |
| `99801891` | `182121997` | Won — Add-on |
| `99801891` | `182121998` | Lost |
| `1442832850` | `2390834669` | Won — Renewal |
| `1442832850` | `2390834670` | Lost — Renewal |
| anything else | — | Open |

---

## Identity Resolution Notes

The warehouse resolves Stripe↔HubSpot identity via `customer_id_map`:
- `STRIPE_CUSTOMER_ID` format: `cus_XXXXX`
- `HUBSPOT_COMPANY_ID` format: `hs_XXXXX`
- `CANONICAL_ID` = Stripe ID when available, HubSpot ID otherwise

When joining across sources always join on `CANONICAL_ID`, not raw IDs.
Unmatched records (stripe_only, hubspot_only) will produce NULLs on the unmatched side.

---

## Common Query Patterns

### Total MRR trend over last 12 months
```sql
SELECT MONTH, SUM(MRR) AS total_mrr
FROM MART.MRR_MONTHLY
WHERE MONTH >= DATE_TRUNC('MONTH', DATEADD('MONTH', -12, CURRENT_DATE()))
GROUP BY MONTH ORDER BY MONTH;
```

### Churn rate by month
```sql
SELECT
    c.MONTH,
    COUNT(DISTINCT c.CANONICAL_ID)  AS churned,
    COUNT(DISTINCT m.CANONICAL_ID)  AS active_start_of_month,
    ROUND(COUNT(DISTINCT c.CANONICAL_ID) * 100.0 /
          NULLIF(COUNT(DISTINCT m.CANONICAL_ID), 0), 2) AS churn_rate_pct
FROM MART.CHURN_MONTHLY c
JOIN MART.MRR_MONTHLY m ON c.MONTH = m.MONTH
GROUP BY c.MONTH ORDER BY c.MONTH;
```

### MRR by plan
```sql
SELECT PLAN_NAME, COUNT(DISTINCT CANONICAL_ID) AS customers, SUM(MRR) AS total_mrr
FROM MART.MRR_MONTHLY
WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
GROUP BY PLAN_NAME ORDER BY total_mrr DESC;
```

### Top 10 customers by MRR
```sql
SELECT CANONICAL_ID, COMPANY_NAME, PLAN_NAME, MRR
FROM MART.MRR_MONTHLY
WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
ORDER BY MRR DESC LIMIT 10;
```
