Schema Design — GTM Analytics
Layered Approach
Three schemas in `GTM\_ANALYTICS`, each with a distinct contract:
Layer	Schema	Purpose	Who queries it
Raw	`RAW`	Exact copies of source files. No transformations.	Nobody directly
Staged	`STAGED`	Cleaned, typed, joined, JSON lifted.	Skill (fallback only)
Mart	`MART`	Pre-aggregated, analytics-ready views.	NL-to-SQL skill
Naming conventions:
`DIM\_` prefix for dimension tables (one row per entity)
`FACT\_` prefix for fact tables (one row per event or transaction)
Mart views are named by the metric they serve (`MRR\_MONTHLY`, `CHURN\_MONTHLY`, etc.)
All column names uppercase, snake_case
Date columns use `\_DATE` suffix, month-grain columns use `\_MONTH` suffix
---
Where JSON Was Parsed
Stripe Events (`RAW.STRIPE\_EVENTS`)
Stored entirely as `VARIANT` in the RAW layer. Each row is one full Stripe webhook envelope:
```json
{ "id": "evt\_...", "type": "customer.subscription.created",
  "created": 1659949200, "data": { "object": { ... } } }
```
Fields were NOT lifted to STAGED. After review, `STAGED.FACT\_SUBSCRIPTIONS` (built from
`stripe\_subscriptions.csv`) already contains the full subscription lifecycle — start date,
end date, status, cancellation reason, plan, amount. The events table is retained as an
audit trail and for future use cases (e.g. detecting mid-month plan changes) but is not
promoted to a staged table. Lifting fields from 221K event rows for data already available
in the CSV would add complexity without value.
HubSpot Deals (`RAW.HUBSPOT\_DEALS → STAGED.FACT\_DEALS`)
The `properties` column in the CSV is an embedded JSON string — a typical HubSpot export
artifact. Five fields were lifted in `STAGED.FACT\_DEALS` using Snowflake's colon-notation:
Lifted field	Source path	Type
`DEAL\_OWNER\_ID`	`properties:deal\_owner\_id`	VARCHAR
`CAMPAIGN\_SOURCE`	`properties:campaign\_source`	VARCHAR
`DEAL\_PRIORITY`	`properties:deal\_priority`	VARCHAR
`FORECAST\_CATEGORY`	`properties:forecast\_category`	VARCHAR
`DISCOUNT\_PCT`	`properties:discount\_pct`	NUMBER(5,2)
The raw `PROPERTIES` VARIANT column is retained in `RAW.HUBSPOT\_DEALS` for any fields
not yet lifted. `STAGED.FACT\_DEALS` does not carry the VARIANT forward — all needed
fields are now typed columns.
HubSpot Deal Stage IDs
Raw pipeline and dealstage values are opaque HubSpot internal IDs (e.g. `2390834669`).
These are decoded to human labels in `STAGED.FACT\_DEALS` via a CASE expression:
Pipeline	Dealstage	Label
`default`	`closedwon`	Won — Core
`default`	`closedlost`	Lost
`99801891`	`182121997`	Won — Add-on
`99801891`	`182121998`	Lost
`1442832850`	`2390834669`	Won — Renewal
`1442832850`	`2390834670`	Lost — Renewal
anything else	—	Open
---
Stripe ↔ HubSpot ID Mapping
The problem: Stripe uses `customer\_id` (billing entity); HubSpot uses `company\_id`
(business entity). They are different namespaces with partial overlap via `customer\_id\_map`.
The resolution:
`STAGED.DIM\_CUSTOMER` performs a full outer join across all three sources
`CANONICAL\_ID` = Stripe `customer\_id` when available, HubSpot `company\_id` otherwise
Three match states are preserved — never silently dropped:
`both` (3,800): fully matched, all attributes available
`stripe\_only` (200): Stripe customers with no HubSpot record (company name = NULL)
`hubspot\_only` (200): HubSpot companies never converted to Stripe customers
Critical convention: All staged and mart tables use `CANONICAL\_ID = COALESCE(STRIPE\_CUSTOMER\_ID, HUBSPOT\_COMPANY\_ID)` — Stripe ID takes priority. Deviation from this breaks cross-table joins silently (a bug discovered and fixed during benchmark testing).
---
