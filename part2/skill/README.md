# GTM Analytics NL-to-SQL Skill

Answers business intelligence questions in natural language against the GTM Analytics
Snowflake warehouse. Generates SQL, runs it, and explains the result.

---

## Prerequisites

1. **A Snowflake account** with the GTM Analytics warehouse loaded
   - If starting from scratch, run `load.sql` (in the root of this submission) on a
     fresh Snowflake Standard trial account
   - Expected setup time: ~30 minutes including file uploads

2. **Snowflake access details** — you'll need:
   - Account identifier (e.g. `ABC12345.ap-southeast-1.aws`)
   - Username and password
   - Warehouse: `COMPUTE_WH` (default) or any XS warehouse
   - Database: `GTM_ANALYTICS`
   - Role: `ACCOUNTADMIN` or any role with SELECT on `MART.*` and `STAGED.*`

3. **Claude** — claude.ai or any Claude API access

---

## Installation

### Option A — Claude Skills (~/.claude/skills/)
```bash
cp -r skill/ ~/.claude/skills/nl-to-sql-gtm-analytics/
```
Claude will automatically load `SKILL.md` when you ask BI questions.

### Option B — System prompt (any LLM framework)
Use `system_prompt.md` from the root of this submission.
Paste the content directly as your system prompt in OpenAI SDK, LangChain, or
the Anthropic API. See `system_prompt.md` for copy-paste code examples.

---

## How to Use

1. **Ask a question in plain English:**
   - "What was MRR last month?"
   - "How many customers churned in March 2026?"
   - "Which customers are at risk of churning?"
   - "Show me NRR for 2025 cohorts"
   - "Why does our Stripe churn number not match HubSpot?"

2. **The skill returns:**
   - A direct answer in plain English
   - The exact SQL query used
   - A brief explanation of how it was calculated and any caveats

3. **Run the SQL** in Snowflake (Snowsight worksheet or any SQL client):
   ```sql
   -- Example: paste the generated SQL here
   SELECT MONTH, SUM(MRR) AS total_mrr
   FROM GTM_ANALYTICS.MART.MRR_MONTHLY
   WHERE MONTH = '2026-03-01'
   GROUP BY MONTH;
   ```

4. **If the skill asks a clarifying question** — answer it before it generates SQL.
   This happens for ambiguous questions (e.g. "revenue" without specifying MRR vs invoiced).

---

## What the Skill Can Answer

| Question type | Source | Confidence |
|---|---|---|
| MRR (monthly, by plan, by country) | `MART.MRR_MONTHLY` | Verified |
| Churn counts and churned MRR | `MART.CHURN_MONTHLY` | Verified |
| NRR by cohort | `MART.NRR_COHORT` | Verified |
| At-risk / health scoring | `MART.CUSTOMER_HEALTH` | Verified |
| New customer acquisition | `STAGED.FACT_SUBSCRIPTIONS` | Unverified |
| Deal-level questions (campaign, owner) | `STAGED.FACT_DEALS` | Unverified |
| Why Stripe ≠ HubSpot | Conceptual explanation | No SQL |

---

## File Structure

```
skill/
├── README.md               ← You are here
├── SKILL.md                ← Main skill instructions, rules, and few-shot examples
└── references/
    └── schema.md           ← Full column-level schema for all tables and views
```
