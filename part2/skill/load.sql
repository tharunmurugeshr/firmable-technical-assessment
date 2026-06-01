-- =============================================================================
-- Go To Market (GTM) Analytics — Snowflake Load Script
-- =============================================================================
-- Reproducible from a fresh Snowflake account.
-- Run each section in order. All statements are either CREATE OR REPLACE
--
-- Prerequisites:
--   - Snowflake Standard Edition (AWS ap-southeast-1 or equivalent)
--   - Raw files uploaded to RAW_STAGE (see Step 4 below)
--
-- File layout expected in stage:
--   raw_stage/customer_id_map.csv
--   raw_stage/hubspot_companies.csv
--   raw_stage/hubspot_deals.csv
--   raw_stage/stripe_invoices.csv
--   raw_stage/stripe_subscriptions.csv
--   raw_stage/stripe_events_YYYY-MM.jsonl   (56 monthly files)
-- =============================================================================


-- =============================================================================
-- STEP 1 — Database and schemas
-- =============================================================================

CREATE DATABASE IF NOT EXISTS GTM_ANALYTICS;

CREATE SCHEMA IF NOT EXISTS GTM_ANALYTICS.RAW;
CREATE SCHEMA IF NOT EXISTS GTM_ANALYTICS.STAGED;
CREATE SCHEMA IF NOT EXISTS GTM_ANALYTICS.MART;


-- =============================================================================
-- STEP 2 — File formats
-- =============================================================================

-- CSV: handles quoted fields, nulls, header row
CREATE OR REPLACE FILE FORMAT GTM_ANALYTICS.RAW.CSV_FORMAT
    TYPE                        = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER                 = 1
    NULL_IF                     = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL         = TRUE
    TRIM_SPACE                  = TRUE;

-- JSON Lines: one JSON object per line (Stripe webhook envelope)
-- STRIP_OUTER_ARRAY = FALSE because each line is a single object, not an array
CREATE OR REPLACE FILE FORMAT GTM_ANALYTICS.RAW.JSONL_FORMAT
    TYPE                        = 'JSON'
    STRIP_OUTER_ARRAY           = FALSE
    NULL_IF                     = ('NULL', 'null');


-- =============================================================================
-- STEP 3 — Internal stage
-- =============================================================================

-- Internal stage: Snowflake hosts the files
CREATE OR REPLACE STAGE GTM_ANALYTICS.RAW.RAW_STAGE
    FILE_FORMAT = GTM_ANALYTICS.RAW.CSV_FORMAT
    COMMENT     = 'Internal stage for all raw CSV and JSONL source files';

-- Verify uploads before proceeding:
--   LIST @GTM_ANALYTICS.RAW.RAW_STAGE;
-- Expected: 61 rows (5 CSV + 56 JSONL)


-- =============================================================================
-- STEP 4 — Raw tables
-- =============================================================================
-- These are exact column-for-column mirrors of the source files.
-- No transformations — types are the minimum needed to load cleanly.
-- VARIANT used for Stripe Events (full JSON) and HubSpot deal properties (embedded JSON).

USE DATABASE GTM_ANALYTICS;
USE SCHEMA RAW;

CREATE OR REPLACE TABLE RAW.STRIPE_INVOICES (
    INVOICE_ID          VARCHAR,
    CUSTOMER_ID         VARCHAR,
    SUBSCRIPTION_ID     VARCHAR,
    INVOICE_DATE        DATE,
    AMOUNT_EX_GST       NUMBER(12,2),
    AMOUNT_INC_GST      NUMBER(12,2),
    CURRENCY            VARCHAR,
    STATUS              VARCHAR
);

CREATE OR REPLACE TABLE RAW.STRIPE_SUBSCRIPTIONS (
    SUBSCRIPTION_ID     VARCHAR,
    CUSTOMER_ID         VARCHAR,
    PLAN_NAME           VARCHAR,
    MONTHLY_AMOUNT      NUMBER(12,2),
    START_DATE          DATE,
    END_DATE            DATE,
    STATUS              VARCHAR,
    CANCELLATION_REASON VARCHAR,
    CREATED_AT          DATE
);

-- Events stored as VARIANT — full webhook envelope preserved.
-- Relevant fields are parsed in STAGED layer, not here.
CREATE OR REPLACE TABLE RAW.STRIPE_EVENTS (
    RAW_JSON            VARIANT
);

-- PROPERTIES column stored as VARIANT — HubSpot's embedded JSON column.
-- Fields (deal_owner_id, campaign_source, etc.) lifted in STAGED layer.
CREATE OR REPLACE TABLE RAW.HUBSPOT_DEALS (
    DEAL_ID                 VARCHAR,
    PROPERTIES_COMPANY_ID   VARCHAR,
    PIPELINE                VARCHAR,
    DEALSTAGE               VARCHAR,
    CLOSEDATE               DATE,
    AMOUNT                  NUMBER(12,2),
    PROPERTIES_CUSTOMER_ID  VARCHAR,
    PROPERTIES              VARIANT
);

CREATE OR REPLACE TABLE RAW.HUBSPOT_COMPANIES (
    COMPANY_ID          VARCHAR,
    NAME                VARCHAR,
    INDUSTRY            VARCHAR,
    EMPLOYEES           NUMBER,
    COUNTRY             VARCHAR
);

-- Bridge table: maps Stripe customer IDs to HubSpot company IDs.
-- Note: not every Stripe customer has a HubSpot match, and vice versa.
CREATE OR REPLACE TABLE RAW.CUSTOMER_ID_MAP (
    STRIPE_CUSTOMER_ID  VARCHAR,
    HUBSPOT_COMPANY_ID  VARCHAR
);


-- =============================================================================
-- STEP 5 — Load CSV files
-- =============================================================================

COPY INTO GTM_ANALYTICS.RAW.CUSTOMER_ID_MAP
FROM @GTM_ANALYTICS.RAW.RAW_STAGE/customer_id_map.csv
FILE_FORMAT = GTM_ANALYTICS.RAW.CSV_FORMAT;

COPY INTO GTM_ANALYTICS.RAW.HUBSPOT_COMPANIES
FROM @GTM_ANALYTICS.RAW.RAW_STAGE/hubspot_companies.csv
FILE_FORMAT = GTM_ANALYTICS.RAW.CSV_FORMAT;

COPY INTO GTM_ANALYTICS.RAW.HUBSPOT_DEALS
FROM @GTM_ANALYTICS.RAW.RAW_STAGE/hubspot_deals.csv
FILE_FORMAT = (FORMAT_NAME = GTM_ANALYTICS.RAW.CSV_FORMAT,
               FIELD_OPTIONALLY_ENCLOSED_BY = '"');

COPY INTO GTM_ANALYTICS.RAW.STRIPE_SUBSCRIPTIONS
FROM @GTM_ANALYTICS.RAW.RAW_STAGE/stripe_subscriptions.csv
FILE_FORMAT = GTM_ANALYTICS.RAW.CSV_FORMAT;

COPY INTO GTM_ANALYTICS.RAW.STRIPE_INVOICES
FROM @GTM_ANALYTICS.RAW.RAW_STAGE/stripe_invoices.csv
FILE_FORMAT = GTM_ANALYTICS.RAW.CSV_FORMAT;


-- =============================================================================
-- STEP 6 — Load JSONL files (Stripe Events)
-- =============================================================================
-- Pattern matches all 56 monthly files in one pass.
-- ON_ERROR = CONTINUE skips malformed lines without failing the entire load.
-- Each line loads as a single VARIANT row — no schema applied at this layer.

COPY INTO GTM_ANALYTICS.RAW.STRIPE_EVENTS
FROM @GTM_ANALYTICS.RAW.RAW_STAGE
FILE_FORMAT = GTM_ANALYTICS.RAW.JSONL_FORMAT
PATTERN     = '.*stripe_events.*\\.jsonl'
ON_ERROR    = CONTINUE;


-- =============================================================================
-- STEP 7 — Verify raw load
-- =============================================================================
-- Expected row counts:
--   CUSTOMER_ID_MAP     3,800
--   HUBSPOT_COMPANIES   4,000
--   HUBSPOT_DEALS       5,078
--   STRIPE_SUBSCRIPTIONS 4,777
--   STRIPE_INVOICES    107,551
--   STRIPE_EVENTS      221,098

SELECT 'CUSTOMER_ID_MAP'      AS table_name, COUNT(*) AS row_count FROM GTM_ANALYTICS.RAW.CUSTOMER_ID_MAP
UNION ALL
SELECT 'HUBSPOT_COMPANIES',   COUNT(*) FROM GTM_ANALYTICS.RAW.HUBSPOT_COMPANIES
UNION ALL
SELECT 'HUBSPOT_DEALS',       COUNT(*) FROM GTM_ANALYTICS.RAW.HUBSPOT_DEALS
UNION ALL
SELECT 'STRIPE_SUBSCRIPTIONS',COUNT(*) FROM GTM_ANALYTICS.RAW.STRIPE_SUBSCRIPTIONS
UNION ALL
SELECT 'STRIPE_INVOICES',     COUNT(*) FROM GTM_ANALYTICS.RAW.STRIPE_INVOICES
UNION ALL
SELECT 'STRIPE_EVENTS',       COUNT(*) FROM GTM_ANALYTICS.RAW.STRIPE_EVENTS;


-- =============================================================================
-- STEP 8 — STAGED layer
-- =============================================================================
-- Cleaned, typed, deduplicated. ID mapping resolved. JSON fields lifted.
-- CANONICAL_ID convention: Stripe customer_id (cus_XXXXX) when available,
-- HubSpot company_id (hs_XXXXX) for HubSpot-only records.
-- This convention must be consistent across ALL staged tables.

USE SCHEMA STAGED;

-- -----------------------------------------------------------------------------
-- DIM_CUSTOMER
-- Master customer record. Full outer join across Stripe + HubSpot via id map.
-- Three match states: both / stripe_only / hubspot_only — never silently dropped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGED.DIM_CUSTOMER AS
WITH stripe_customers AS (
    SELECT DISTINCT CUSTOMER_ID
    FROM RAW.STRIPE_SUBSCRIPTIONS
),
mapped AS (
    SELECT
        s.CUSTOMER_ID          AS STRIPE_CUSTOMER_ID,
        m.HUBSPOT_COMPANY_ID
    FROM stripe_customers s
    LEFT JOIN RAW.CUSTOMER_ID_MAP m ON s.CUSTOMER_ID = m.STRIPE_CUSTOMER_ID
),
hubspot_unmatched AS (
    -- HubSpot companies with no Stripe match (prospects, unconverted leads)
    SELECT
        NULL                   AS STRIPE_CUSTOMER_ID,
        c.COMPANY_ID           AS HUBSPOT_COMPANY_ID
    FROM RAW.HUBSPOT_COMPANIES c
    LEFT JOIN RAW.CUSTOMER_ID_MAP m ON c.COMPANY_ID = m.HUBSPOT_COMPANY_ID
    WHERE m.HUBSPOT_COMPANY_ID IS NULL
),
all_customers AS (
    SELECT * FROM mapped
    UNION ALL
    SELECT * FROM hubspot_unmatched
)
SELECT
    COALESCE(a.STRIPE_CUSTOMER_ID, a.HUBSPOT_COMPANY_ID) AS CANONICAL_ID,
    a.STRIPE_CUSTOMER_ID,
    a.HUBSPOT_COMPANY_ID,
    c.NAME                                                AS COMPANY_NAME,
    c.INDUSTRY,
    c.COUNTRY,
    c.EMPLOYEES,
    CASE
        WHEN a.STRIPE_CUSTOMER_ID IS NOT NULL
         AND a.HUBSPOT_COMPANY_ID IS NOT NULL            THEN TRUE
        ELSE                                                  FALSE
    END                                                   AS IS_MATCHED,
    CASE
        WHEN a.STRIPE_CUSTOMER_ID IS NOT NULL
         AND a.HUBSPOT_COMPANY_ID IS NOT NULL            THEN 'both'
        WHEN a.STRIPE_CUSTOMER_ID IS NOT NULL
         AND a.HUBSPOT_COMPANY_ID IS NULL                THEN 'stripe_only'
        ELSE                                                  'hubspot_only'
    END                                                   AS MATCH_SOURCE
FROM all_customers a
LEFT JOIN RAW.HUBSPOT_COMPANIES c ON a.HUBSPOT_COMPANY_ID = c.COMPANY_ID;

-- Expected: 3,800 both | 200 stripe_only | 200 hubspot_only


-- -----------------------------------------------------------------------------
-- FACT_SUBSCRIPTIONS
-- One row per Stripe subscription. Churn and upgrade flags applied.
-- IMPORTANT: CANONICAL_ID = COALESCE(CUSTOMER_ID, HUBSPOT_COMPANY_ID)
-- i.e. Stripe ID takes priority. This must match DIM_CUSTOMER.CANONICAL_ID.
-- Bug note: using HUBSPOT_COMPANY_ID as canonical breaks joins to DIM_CUSTOMER
-- for matched customers — always prefer Stripe ID when available.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGED.FACT_SUBSCRIPTIONS AS
SELECT
    s.SUBSCRIPTION_ID,
    s.CUSTOMER_ID,
    COALESCE(s.CUSTOMER_ID, m.HUBSPOT_COMPANY_ID)   AS CANONICAL_ID,
    s.PLAN_NAME,
    s.MONTHLY_AMOUNT,
    s.START_DATE,
    s.END_DATE,
    s.STATUS,
    s.CANCELLATION_REASON,
    -- Churn: canceled only. canceled_upgraded = plan change, not churn.
    CASE WHEN s.STATUS = 'canceled'          THEN TRUE ELSE FALSE END AS IS_CHURNED,
    -- Upgrade: subscription ended because customer moved to a higher plan
    CASE WHEN s.STATUS = 'canceled_upgraded' THEN TRUE ELSE FALSE END AS IS_UPGRADED,
    DATE_TRUNC('QUARTER', s.START_DATE)             AS COHORT_QUARTER,
    YEAR(s.START_DATE)                              AS COHORT_YEAR,
    QUARTER(s.START_DATE)                           AS COHORT_QUARTER_NUM
FROM RAW.STRIPE_SUBSCRIPTIONS s
LEFT JOIN RAW.CUSTOMER_ID_MAP m ON s.CUSTOMER_ID = m.STRIPE_CUSTOMER_ID;

-- Expected: 3,558 active | 777 canceled_upgraded | 442 canceled


-- -----------------------------------------------------------------------------
-- FACT_INVOICES
-- One row per Stripe invoice. Amounts in AUD (source currency).
-- Same CANONICAL_ID convention as FACT_SUBSCRIPTIONS.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGED.FACT_INVOICES AS
SELECT
    i.INVOICE_ID,
    i.CUSTOMER_ID,
    COALESCE(i.CUSTOMER_ID, m.HUBSPOT_COMPANY_ID)   AS CANONICAL_ID,
    i.SUBSCRIPTION_ID,
    i.INVOICE_DATE,
    DATE_TRUNC('MONTH', i.INVOICE_DATE)             AS INVOICE_MONTH,
    DATE_TRUNC('QUARTER', i.INVOICE_DATE)           AS INVOICE_QUARTER,
    i.AMOUNT_EX_GST,
    i.AMOUNT_INC_GST,
    i.CURRENCY,
    i.STATUS
FROM RAW.STRIPE_INVOICES i
LEFT JOIN RAW.CUSTOMER_ID_MAP m ON i.CUSTOMER_ID = m.STRIPE_CUSTOMER_ID;

-- Expected: 107,418 paid | 133 uncollectible


-- -----------------------------------------------------------------------------
-- FACT_DEALS
-- One row per HubSpot deal. Properties JSON unpacked into typed columns.
-- Raw pipeline/dealstage IDs decoded to human labels via CASE expression.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGED.FACT_DEALS AS
SELECT
    d.DEAL_ID,
    d.PROPERTIES_COMPANY_ID                         AS HUBSPOT_COMPANY_ID,
    d.PROPERTIES_CUSTOMER_ID                        AS STRIPE_CUSTOMER_ID,
    COALESCE(d.PROPERTIES_CUSTOMER_ID,
             d.PROPERTIES_COMPANY_ID)               AS CANONICAL_ID,
    d.PIPELINE,
    d.DEALSTAGE,
    -- Decoded deal outcome — raw IDs are opaque HubSpot internals
    CASE
        WHEN d.PIPELINE = 'default'
         AND d.DEALSTAGE = 'closedwon'              THEN 'Won - Core'
        WHEN d.PIPELINE = 'default'
         AND d.DEALSTAGE = 'closedlost'             THEN 'Lost'
        WHEN d.PIPELINE = '99801891'
         AND d.DEALSTAGE = '182121997'              THEN 'Won - Add-on'
        WHEN d.PIPELINE = '99801891'
         AND d.DEALSTAGE = '182121998'              THEN 'Lost'
        WHEN d.PIPELINE = '1442832850'
         AND d.DEALSTAGE = '2390834669'             THEN 'Won - Renewal'
        WHEN d.PIPELINE = '1442832850'
         AND d.DEALSTAGE = '2390834670'             THEN 'Lost - Renewal'
        ELSE                                             'Open'
    END                                             AS DEAL_OUTCOME,
    d.AMOUNT,
    d.CLOSEDATE                                     AS CLOSE_DATE,
    -- Lifted from PROPERTIES VARIANT (HubSpot embedded JSON)
    d.PROPERTIES:deal_owner_id::VARCHAR             AS DEAL_OWNER_ID,
    d.PROPERTIES:campaign_source::VARCHAR           AS CAMPAIGN_SOURCE,
    d.PROPERTIES:deal_priority::VARCHAR             AS DEAL_PRIORITY,
    d.PROPERTIES:forecast_category::VARCHAR         AS FORECAST_CATEGORY,
    d.PROPERTIES:discount_pct::NUMBER(5,2)          AS DISCOUNT_PCT
FROM RAW.HUBSPOT_DEALS d;


-- =============================================================================
-- STEP 9 — MART layer (views)
-- =============================================================================
-- Analytics-ready. Pre-joined, pre-aggregated.
-- Views (not tables) — always fresh, no scheduling needed at this data volume.
-- NL-to-SQL skill queries ONLY from this layer.

USE SCHEMA MART;

-- -----------------------------------------------------------------------------
-- MRR_MONTHLY
-- Subscription-based MRR. One row per active customer per calendar month.
-- Excludes churned (canceled) and upgraded (canceled_upgraded) subscriptions.
-- Generates one row per month a subscription was active using FLATTEN.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MART.MRR_MONTHLY AS
WITH active_subscriptions AS (
    SELECT
        s.CANONICAL_ID,
        s.SUBSCRIPTION_ID,
        s.PLAN_NAME,
        s.MONTHLY_AMOUNT,
        s.START_DATE,
        s.END_DATE,
        DATEADD('MONTH', SEQ4.INDEX,
            DATE_TRUNC('MONTH', s.START_DATE))      AS MONTH
    FROM STAGED.FACT_SUBSCRIPTIONS s
    JOIN TABLE(FLATTEN(ARRAY_GENERATE_RANGE(
        0,
        DATEDIFF('MONTH', s.START_DATE,
            COALESCE(s.END_DATE, CURRENT_DATE())) + 1
    ))) SEQ4
    WHERE s.MONTHLY_AMOUNT > 0
      AND s.IS_CHURNED  = FALSE
      AND s.IS_UPGRADED = FALSE
)
SELECT
    a.MONTH,
    a.CANONICAL_ID,
    c.COMPANY_NAME,
    c.COUNTRY,
    c.INDUSTRY,
    a.PLAN_NAME,
    a.MONTHLY_AMOUNT                                AS MRR,
    SUM(a.MONTHLY_AMOUNT) OVER (
        PARTITION BY a.CANONICAL_ID
        ORDER BY a.MONTH
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS CUMULATIVE_MRR
FROM active_subscriptions a
LEFT JOIN STAGED.DIM_CUSTOMER c ON a.CANONICAL_ID = c.CANONICAL_ID
WHERE a.MONTH <= DATE_TRUNC('MONTH', CURRENT_DATE());


-- -----------------------------------------------------------------------------
-- CHURN_MONTHLY
-- One row per churned subscription (IS_CHURNED = TRUE only).
-- canceled_upgraded excluded — those customers remain active on a new plan.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MART.CHURN_MONTHLY AS
SELECT
    DATE_TRUNC('MONTH', s.END_DATE)             AS MONTH,
    s.CANONICAL_ID,
    c.COMPANY_NAME,
    c.COUNTRY,
    c.INDUSTRY,
    s.PLAN_NAME,
    s.MONTHLY_AMOUNT                            AS CHURNED_MRR,
    s.CANCELLATION_REASON
FROM STAGED.FACT_SUBSCRIPTIONS s
LEFT JOIN STAGED.DIM_CUSTOMER c ON s.CANONICAL_ID = c.CANONICAL_ID
WHERE s.IS_CHURNED = TRUE
  AND s.END_DATE   IS NOT NULL;


-- -----------------------------------------------------------------------------
-- NRR_COHORT
-- Net Revenue Retention by quarterly cohort.
-- Cohort = calendar quarter of a customer's first subscription start_date.
-- NRR > 100%: expansion outpacing churn. NRR < 100%: contraction.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MART.NRR_COHORT AS
WITH cohort_base AS (
    SELECT
        COHORT_QUARTER,
        COHORT_YEAR,
        COHORT_QUARTER_NUM,
        CANONICAL_ID,
        MONTHLY_AMOUNT          AS STARTING_MRR
    FROM STAGED.FACT_SUBSCRIPTIONS
    WHERE START_DATE = (
        SELECT MIN(START_DATE)
        FROM STAGED.FACT_SUBSCRIPTIONS s2
        WHERE s2.CANONICAL_ID = FACT_SUBSCRIPTIONS.CANONICAL_ID
    )
    AND MONTHLY_AMOUNT > 0
),
cohort_monthly AS (
    SELECT
        cb.COHORT_QUARTER,
        cb.COHORT_YEAR,
        cb.COHORT_QUARTER_NUM,
        cb.CANONICAL_ID,
        cb.STARTING_MRR,
        m.MONTH,
        DATEDIFF('MONTH', cb.COHORT_QUARTER, m.MONTH) AS MONTHS_SINCE_START,
        m.MRR                   AS CURRENT_MRR
    FROM cohort_base cb
    LEFT JOIN MART.MRR_MONTHLY m ON cb.CANONICAL_ID = m.CANONICAL_ID
)
SELECT
    COHORT_QUARTER,
    COHORT_YEAR,
    COHORT_QUARTER_NUM,
    CONCAT('Q', COHORT_QUARTER_NUM, ' ', COHORT_YEAR)  AS COHORT_LABEL,
    MONTHS_SINCE_START,
    COUNT(DISTINCT CANONICAL_ID)                        AS COHORT_CUSTOMERS,
    SUM(STARTING_MRR)                                   AS COHORT_STARTING_MRR,
    SUM(CURRENT_MRR)                                    AS COHORT_CURRENT_MRR,
    ROUND(SUM(CURRENT_MRR) /
          NULLIF(SUM(STARTING_MRR), 0) * 100, 1)       AS NRR_PCT
FROM cohort_monthly
WHERE MONTHS_SINCE_START >= 0
GROUP BY
    COHORT_QUARTER, COHORT_YEAR, COHORT_QUARTER_NUM,
    COHORT_LABEL, MONTHS_SINCE_START
ORDER BY COHORT_QUARTER, MONTHS_SINCE_START;


-- -----------------------------------------------------------------------------
-- CUSTOMER_HEALTH
-- At-risk scoring for active customers only (those with MRR last month).
-- Four risk signals — each grounded in a business decision made during design:
--   1. Uncollectible invoice — payment failure
--   2. Downgrade — later subscription has lower monthly_amount than earlier one
--   3. 3+ months since last invoice — gone quiet
--   4. Prior cancellation reason of 'price' or 'switching_vendor'
-- Risk tiers: red (any high signal) > amber (downgrade only) > green (none)
-- IMPORTANT: INNER JOIN on current_mrr ensures only active customers are scored.
-- Churned customers have no recent MRR and must not pollute the health view.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MART.CUSTOMER_HEALTH AS
WITH latest_invoice AS (
    SELECT
        CANONICAL_ID,
        MAX(INVOICE_DATE)           AS LAST_INVOICE_DATE,
        DATEDIFF('MONTH',
            MAX(INVOICE_DATE),
            CURRENT_DATE())         AS MONTHS_SINCE_LAST_INVOICE
    FROM STAGED.FACT_INVOICES
    GROUP BY CANONICAL_ID
),
uncollectible AS (
    SELECT DISTINCT CANONICAL_ID, TRUE AS HAS_UNCOLLECTIBLE_INVOICE
    FROM STAGED.FACT_INVOICES
    WHERE STATUS = 'uncollectible'
),
downgrades AS (
    SELECT DISTINCT s1.CANONICAL_ID, TRUE AS HAS_DOWNGRADED
    FROM STAGED.FACT_SUBSCRIPTIONS s1
    JOIN STAGED.FACT_SUBSCRIPTIONS s2
        ON  s1.CANONICAL_ID    = s2.CANONICAL_ID
        AND s2.START_DATE      > s1.START_DATE
        AND s2.MONTHLY_AMOUNT  < s1.MONTHLY_AMOUNT
),
prior_cancellation AS (
    SELECT DISTINCT
        CANONICAL_ID,
        CANCELLATION_REASON     AS PRIOR_CANCELLATION_REASON
    FROM STAGED.FACT_SUBSCRIPTIONS
    WHERE IS_CHURNED = TRUE
      AND CANCELLATION_REASON IN ('price', 'switching_vendor')
),
current_mrr AS (
    SELECT
        CANONICAL_ID,
        SUM(MRR)                AS CURRENT_MRR,
        MAX(PLAN_NAME)          AS PLAN_NAME
    FROM MART.MRR_MONTHLY
    WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
    GROUP BY CANONICAL_ID
)
SELECT
    c.CANONICAL_ID,
    c.COMPANY_NAME,
    c.COUNTRY,
    c.INDUSTRY,
    mr.PLAN_NAME,
    mr.CURRENT_MRR,
    COALESCE(u.HAS_UNCOLLECTIBLE_INVOICE, FALSE)    AS HAS_UNCOLLECTIBLE_INVOICE,
    COALESCE(d.HAS_DOWNGRADED, FALSE)               AS HAS_DOWNGRADED,
    li.MONTHS_SINCE_LAST_INVOICE,
    pc.PRIOR_CANCELLATION_REASON,
    CASE
        WHEN COALESCE(u.HAS_UNCOLLECTIBLE_INVOICE, FALSE) = TRUE
          OR COALESCE(li.MONTHS_SINCE_LAST_INVOICE, 0) >= 3
          OR pc.PRIOR_CANCELLATION_REASON IS NOT NULL      THEN 'red'
        WHEN COALESCE(d.HAS_DOWNGRADED, FALSE) = TRUE      THEN 'amber'
        ELSE                                                    'green'
    END                                             AS RISK_TIER
FROM STAGED.DIM_CUSTOMER c
-- INNER JOIN: only customers with MRR last month are scored
-- Churned customers with no recent MRR must not appear in health view
INNER JOIN current_mrr mr          ON c.CANONICAL_ID = mr.CANONICAL_ID
LEFT  JOIN latest_invoice li       ON c.CANONICAL_ID = li.CANONICAL_ID
LEFT  JOIN uncollectible u         ON c.CANONICAL_ID = u.CANONICAL_ID
LEFT  JOIN downgrades d            ON c.CANONICAL_ID = d.CANONICAL_ID
LEFT  JOIN prior_cancellation pc   ON c.CANONICAL_ID = pc.CANONICAL_ID;


-- =============================================================================
-- STEP 10 — Final verification
-- =============================================================================

-- MART spot checks
SELECT MONTH, COUNT(DISTINCT CANONICAL_ID) AS customers, SUM(MRR) AS total_mrr
FROM MART.MRR_MONTHLY
WHERE MONTH = DATE_TRUNC('MONTH', DATEADD('MONTH', -1, CURRENT_DATE()))
GROUP BY MONTH;
-- Expected: ~3,224 customers, ~$7,133,000 MRR

SELECT MONTH, COUNT(DISTINCT CANONICAL_ID) AS churned, SUM(CHURNED_MRR) AS churned_mrr
FROM MART.CHURN_MONTHLY
WHERE MONTH = '2026-03-01'
GROUP BY MONTH;
-- Expected: 42 customers, $96,000

SELECT RISK_TIER, COUNT(*) AS customers, SUM(CURRENT_MRR) AS mrr
FROM MART.CUSTOMER_HEALTH
GROUP BY RISK_TIER ORDER BY RISK_TIER;
-- Expected: ~95 amber, ~0 red, ~3,129 green
