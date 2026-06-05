# Part 2 Design Document — GTM Analytics NL-to-SQL Skill

---

## 1. Metric Definitions Baked into the Skill

### MRR (Monthly Recurring Revenue)

**Grain:** Customer × calendar month. One row per active customer per month in `MART.MRR_MONTHLY`.

**Source of truth:** Stripe subscriptions (`STAGED.FACT_SUBSCRIPTIONS.MONTHLY_AMOUNT`).
Not invoice-based. Invoice amounts represent what was billed; subscription amounts represent
what is contracted. These diverge when invoices are uncollectible, when billing is ahead or
behind the subscription cycle, or when GST is included.

**Edge cases:**

- **Upgrades (`canceled_upgraded`):** The old subscription is excluded from MRR entirely.
  The new (higher) subscription is included from its start date. There is no double-counting.
  In the data: 777 subscriptions have this status and contribute $0 to MRR directly — their
  replacement subscriptions carry the revenue.

- **Downgrades:** A customer moving from Enterprise Plus ($5,000) to Enterprise ($3,000) keeps
  contributing MRR — just at the lower amount from the new subscription's start date. The
  downgrade is flagged in `MART.CUSTOMER_HEALTH` as a risk signal but does not create a gap
  in MRR.

- **Multi-subscription customers:** Not present in this dataset — each customer has at most
  one active subscription at a time. If they existed, each active subscription would contribute
  independently to MRR, and the customer-month grain would have multiple rows. The skill's
  `SUM(MRR)` aggregation handles this correctly.

- **Trials:** No trial data in this dataset. If present, zero-amount trial subscriptions are
  excluded by the `MONTHLY_AMOUNT > 0` filter in `MART.MRR_MONTHLY`.

- **Pauses:** Not modelled in the source data. A paused subscription with no end date would
  continue contributing MRR — a known gap if pauses are introduced in production.

- **Refunds:** Not modelled. Refunds would appear as negative invoice amounts or as status
  changes in Stripe events, neither of which feeds the subscription-based MRR calculation.
  MRR would be unaffected; invoiced revenue queries would need a refund adjustment.

- **Involuntary failures:** Subscriptions with `cancellation_reason = 'involuntary'` are
  counted as churned (they have `status = 'canceled'`). They stop contributing MRR from
  their `end_date`. They are not distinguished from voluntary churn in the MRR view but
  are distinguishable in `MART.CHURN_MONTHLY` via the `CANCELLATION_REASON` column.

**GST treatment:** MRR uses `monthly_amount` from subscriptions, which is ex-GST.
Invoice amounts carry both `amount_ex_gst` and `amount_inc_gst`. Revenue queries
should consistently use `amount_ex_gst`. The skill's response template notes this
whenever invoice-based queries are run.

---

### NRR (Net Revenue Retention)

**Grain:** Cohort × months-since-start. One row per cohort per month offset in `MART.NRR_COHORT`.

**Source of truth:** Derived from `MART.MRR_MONTHLY` (which is Stripe-based).

**Definition:** `NRR% = (cohort_current_mrr / cohort_starting_mrr) × 100`

Where:
- `cohort_starting_mrr` = sum of MRR of cohort members at month 0 of observation
- `cohort_current_mrr` = sum of MRR of those same customers at month N

**Cohort definition:** Calendar quarter of a customer's first subscription `start_date`.
A customer who started in February 2025 belongs to Q1 2025.

**Edge cases:**

- **Churned cohort members:** Contribute $0 current MRR. Their absence pulls NRR below 100%.
- **Upgraded cohort members:** Contribute higher current MRR. Their growth pushes NRR above 100%.
- **Cohort starting MRR grows in early months:** Customers in the same quarter don't all start on day 1 — some start in month 1, others in month 2 or 3. The cohort base accumulates until the quarter closes, so NRR in months 0, 1, and 2 is not meaningful — the denominator is still growing. NRR should only be interpreted from month 3 onwards when the cohort is fully formed and the denominator is stable.
- **No expansion from new customers:** NRR measures retention and expansion of existing cohort
  members only. New customers acquired after the cohort window closes are not included.

---

### Gross Churn

**Grain:** Subscription × end month. One row per churned subscription in `MART.CHURN_MONTHLY`.

**Source of truth:** Stripe subscriptions where `status = 'canceled'`.

**Definition:** A subscription is churned if and only if `status = 'canceled'`.
`canceled_upgraded` is explicitly excluded — the customer remains active on a new subscription.

**Edge cases:**

- **Customer with multiple canceled subscriptions:** Each cancellation is a separate row.
  A customer who churned, reacquired, and churned again appears twice in the churn view.
  Customer-level churn counts should use `COUNT(DISTINCT CANONICAL_ID)`, not `COUNT(*)`.
- **Involuntary churn:** `cancellation_reason = 'involuntary'` is included in gross churn.
  It is distinguishable via the `CANCELLATION_REASON` column but not separated by default.
- **Churn MRR:** `CHURNED_MRR` = the `monthly_amount` of the canceled subscription, not the
  last invoice amount. This is consistent with MRR being subscription-based throughout.

---

### At-Risk (Customer Health)

**Grain:** One row per active customer in `MART.CUSTOMER_HEALTH`.
Active = customer has MRR in the most recent complete month.

**Source of truth:** Reconciled — combines Stripe invoice data (uncollectible invoices,
invoice recency) with Stripe subscription data (downgrades, prior cancellation reasons).

**Risk signals and their thresholds:**

| Signal | Threshold | Tier | Rationale |
|---|---|---|---|
| Uncollectible invoice | Any | red | Payment failure is an immediate risk signal |
| No invoice in N months | ≥ 3 months | red | Agreed threshold — 1-2 months too noisy, 3+ is meaningful |
| Prior cancellation reason | `price` or `switching_vendor` | red | Return customers with these reasons are most likely to leave again |
| Downgraded plan | Any lower `monthly_amount` | amber | Revenue contraction — not an exit, but a warning |

**Edge cases:**

- **Churned customers:** Excluded via INNER JOIN on last month's MRR. A customer with
  `status = 'canceled'` has no recent MRR and will not appear in the health view.
  This was a bug discovered during benchmark testing — using a LEFT JOIN allowed churned
  customers (with `MONTHS_SINCE_LAST_INVOICE = 99`) to flood the red tier falsely.
- **Stripe-only customers:** Included but will have NULL `COMPANY_NAME` and `INDUSTRY`.
  They are scored on the signals available from Stripe data only.
- **Hubspot-only customers:** Excluded — they have no Stripe subscriptions and no MRR.

---

## 2. How the Skill Handles Source-System Disagreement

When Stripe and HubSpot give different numbers for the same question, the skill
**always defers to Stripe as the financial source of truth** for revenue and churn metrics,
and **always defers to HubSpot for company attributes** (name, industry, country).

**The reasoning:**

Stripe is the billing system of record. Revenue recognition, churn, and MRR are financial
facts — they depend on whether a subscription was active and an invoice was paid. Stripe
owns this data by design. HubSpot is a CRM — it records sales activity, deal stages, and
company attributes. Asking HubSpot for a churn count is asking a sales tool to answer a
finance question; the answer will reflect sales pipeline activity, not billing reality.

**For the specific "why don't our numbers match?" question:** The skill answers conceptually
in prose (no SQL) and explains the five structural reasons the systems disagree. It does not
attempt to reconcile them in a single query — that reconciliation belongs in a formal
finance close process with human sign-off, not an automated BI tool.

**The `CANONICAL_ID` convention encodes this choice:** Stripe `customer_id` takes priority
over HubSpot `company_id` as the primary key. When a customer exists in both systems,
the Stripe ID wins. This means MRR and churn queries anchor on Stripe's identity, and
HubSpot attributes (industry, country) are enrichment — present when available, NULL when not.

---

## 3. Guardrails

### Questions the skill refuses to answer
- Anything requiring RAW table queries — the skill will not generate SQL against `RAW.*`
- Questions where the user's intent is clearly outside the data domain and no relevant
  data exists (e.g. "write me a sales email", "what is our competitor's pricing")

### Questions the skill answers with a clarification first
- **Ambiguous time periods:** "What is MRR?" → asks for specific month or trend
- **Ambiguous metrics:** "Show me revenue" → asks whether contracted MRR or invoiced revenue
- **Ambiguous scope:** "Show me NRR" → asks for specific cohort year or all cohorts
- **Industry churn by month:** → asks which month to use (most recent may be empty)

### How the skill signals confidence
Three confidence tiers are explicit in every response:

1. **MART query (high confidence):** No warning. The SQL queries a pre-validated view
   with a documented metric definition. The answer is an official metric.

2. **STAGED fallback (medium confidence):** Prefixed with
   `Unverified metric: This query uses staged data, not a pre-built MART view.`
   The analyst is warned before reading the number.

3. **Conceptual answer (no SQL):** For source-system disagreement questions, the skill
   answers in prose and explicitly recommends the correct source of truth. No number
   is produced that could be misread as authoritative.

### How an analyst audits an answer
Every SQL response includes the full query, table names, and a plain-English explanation
of the metric definition used. An analyst can:
1. Run the SQL directly in Snowflake to verify the result
2. Trace the table back to `schema.md` for the column-level definition
3. Trace the metric definition back to `SKILL.md` for the business rule (e.g. why
   `canceled_upgraded` is excluded from churn)
4. Inspect the underlying STAGED table if the MART view is suspect

---

## 4. Three Known Failure Modes

### Failure Mode 1 — The most-recent-month trap
**What happens:** A query using `DATEADD('MONTH', -1, CURRENT_DATE())` returns the
current month, not the previous complete month, when run on the first day of a new month.
Churn queries for "last month" may return zero rows if churn data hasn't landed yet.

**Evidence:** Benchmark Q6 (industry churn rate) returned all-zero churned counts when
run against April 2026 — the month had no churn data yet.

**Mitigation in production:** Replace dynamic date expressions with a `reporting_calendar`
table that marks months as "closed" once all source data has loaded. The skill should
query against the latest closed month, not `DATEADD(-1 month)`. Alternatively, add a
data freshness check at the top of each MART view that surfaces the latest available month.

---

### Failure Mode 2 — CANONICAL_ID drift across tables
**What happens:** If any staged table uses a different CANONICAL_ID convention
(e.g. HubSpot ID instead of Stripe ID for matched customers), cross-table joins silently
return NULLs. No error is thrown — the query runs, but company attributes are missing.

**Evidence:** This exact bug occurred during benchmark testing. `FACT_SUBSCRIPTIONS` was
built with `COALESCE(HUBSPOT_ID, STRIPE_ID)` instead of `COALESCE(STRIPE_ID, HUBSPOT_ID)`,
causing all industry-level aggregations to return NULL. It was caught only because we ran
a diagnostic query.

**Mitigation in production:** Add a dbt test (or equivalent) that asserts
`COUNT(*) FROM STAGED.FACT_SUBSCRIPTIONS WHERE CANONICAL_ID LIKE 'hs_%' AND CUSTOMER_ID IS NOT NULL = 0`.
Any Stripe subscription with a known `CUSTOMER_ID` must have a `cus_` canonical ID.
Run this test on every load.

---

### Failure Mode 3 — Confident answers on thin data
**What happens:** The skill produces a well-formatted answer with SQL and a result for
a segment that has very few customers. For example, "churn rate for the Construction
industry in March 2026" returns 1.84% based on 5 churned customers out of 272.
This is statistically noisy but the skill presents it with the same confidence as
"total MRR last month" which is based on 3,173 customers.

**Evidence:** Q6 benchmark showed churn rates ranging from 0.63% to 2.09% across
industries, all based on single-digit churned customer counts.

**Mitigation in production:** Add a sample size caveat to any query that groups by
a dimension and returns segments with fewer than N customers (e.g. N = 30). The skill
should append: "Note: segments with fewer than 30 churned customers may not be
statistically reliable." This is a prompt-level guardrail, not a SQL-level one.

---

## 5. What I Would Actively Refuse to Automate with This Skill

**I would refuse to automate churn intervention decisions** — specifically, automatically
triggering customer outreach, cancellation offers, or account escalations based on the
health score from `MART.CUSTOMER_HEALTH`.

The reason is not that the data is wrong. The risk tiers are correctly computed and the
signals are grounded in real behaviour. The reason is that **automated intervention at
the customer level conflates a statistical signal with a specific human relationship**.

A customer flagged amber (downgraded plan) may have downgraded because their business
contracted, because they switched to a cheaper tier while evaluating a competitor, or
because a new finance team reduced spending across all vendors. The appropriate response
to these three scenarios is different — empathy, urgency, and patience respectively.
An automated trigger cannot distinguish them.

Sending automated retention emails to 95 customers in one week, all flagged for the same reason, 
with no prioritisation and no context, is more likely to damage relationships than save them. 
A customer success manager who knows an account can tell the difference between a customer who 
downgraded because their startup ran out of money and one who downgraded while evaluating a 
competitor. An automated trigger cannot. The skill should surface the list — the human decides 
what to do with it.

The skill should **surface** at-risk customers to a human. The human decides whether
and how to act. The line between "surfacing data" and "triggering action" is where
automation earns its keep or causes harm — and in customer relationships, that line
matters.

---

## 6. What I'd Do Differently with 2 Weeks Instead of 4 Hours

**1. Add a `MART.NEW_CUSTOMERS_MONTHLY` view.**
New customer acquisition is a core GTM metric and Q2 of the benchmark required a
STAGED fallback with an unverified flag. In production this should be a pre-built,
validated view — not an ad hoc CTE. The definition (first subscription start date per
customer) is simple enough to formalise in an hour; the value of having it in MART
is that analysts trust it as an official number.

**2. Fix the most-recent-month trap properly.**
The dynamic `DATEADD('MONTH', -1, CURRENT_DATE())` filter is brittle. I'd build a
`MART.REPORTING_CALENDAR` table with a `is_closed` flag populated by the data load
pipeline. Every time-relative query in the skill would reference the latest closed
month from this table rather than computing it from the current date.

**3. Add dbt (or equivalent) with tests.**
The CANONICAL_ID bug we found during benchmarking would have been caught on day one
with a dbt test. With two weeks I'd port all the STAGED and MART SQL to dbt models,
add schema tests for primary key uniqueness and referential integrity, and add custom
tests for the CANONICAL_ID convention. The `load.sql` file is reproducible but fragile —
dbt gives you reproducibility plus regression safety.

**4. Promote Stripe Events to a STAGED table.**
Right now 221K event rows sit in RAW as an unqueried VARIANT. Events contain mid-month
plan change data, upgrade timestamps, and trial conversion signals that the CSV snapshots
don't capture. With two weeks I'd build `STAGED.FACT_SUBSCRIPTION_EVENTS` — one row per
relevant event type (`customer.subscription.created`, `customer.subscription.updated`,
`customer.subscription.deleted`) with fields lifted from `data.object`. This would
enable event-based MRR calculations (more accurate for mid-month changes) and richer
health signals.

**5. Add a cohort acquisition metric alongside NRR.**
NRR tells you how existing cohorts retain and expand. It doesn't tell you whether
new cohorts are as valuable as old ones. With two weeks I'd add `MART.COHORT_ACQUISITION`
— starting MRR per cohort vs. starting MRR of the prior cohort — so the Exec team can
see whether new customers are coming in at higher or lower contract values over time.

**6. Validate the skill against adversarial queries.**
The benchmark tests 10 well-formed questions. In production, analysts ask malformed,
ambiguous, and domain-crossing questions constantly. I'd spend a week on red-teaming
the skill — asking it questions designed to elicit wrong SQL, confident wrong answers,
or inappropriate fallbacks — and use the failures to add guardrails and examples.
Specifically: multi-metric questions ("show me MRR and churn side by side"), year-over-year
questions ("how does March 2026 compare to March 2025"), and filter combinations
("MRR for Enterprise customers in Australia who have been active more than 12 months").
