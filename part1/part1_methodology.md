**Point 1 - Clarifying Questions**

**MUST ANSWER BEFORE I START**

| **#** | **Question**                                                                                                                                                                       | **Fallback Assumption**                                                                                                                                                 |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | The dataset contains 810 NZ companies and contacts - should these be included or excluded?                                                                                         | Excluded - brief mentioned Australian mid-market businesses only                                                                                                        |
| 2     | The brief says "under 20 staff" - does this mean exclude companies with fewer than 20 (keep 20+) or fewer than 21 (keep 21+)? 17 companies have exactly 20 employees               | Kept 20 and above - "under 20" means 19 and below are excluded                                                                                                          |
| 3     | Which revenue bands define "mid-market Australian business"? The dataset has 8 bands ranging from Under \$1M to \$250M+                                                            | Started with \$100M+ then expanded to \$10M+ based on Australian market definitions (ATO, KPMG, BDO) - majority of sources define mid-market from \$10M                 |
| 4     | Should "Food & Beverage Manufacturing" be treated as part of the target industries? It wasn't explicitly named in the brief but falls under both Food Production and Manufacturing | Included - fits the energy-spend profile and industry intent of the brief                                                                                               |
| 5     | The brief says "Warehousing" - should "Warehousing & Logistics" be included too?                                                                                                   | Included - logistics is an extension of warehousing and fits the energy-spend profile                                                                                   |
| 6     | The brief says "Mobile is critical" but also "give us email over mobile if only one" - should contacts with only mobile or only email be included?                                 | Included both - filter is mobile OR email. Contacts with neither or landline only are excluded. Priority column added: Gold (Mobile + Email) → Email Only → Mobile Only |
| 7     | What is the target contact quota? The brief mentions "fill the quota" without specifying a number                                                                                  | Assumed 3,000+ based on context and iterative expansion of states and revenue bands                                                                                     |

**NICE TO KNOW**

| **#** | **Question**                                                                                                                                                                                                                                                         | **Fallback Assumption**                                                                                                                          |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1     | What does the number suffix after each company name represent (e.g. Acme Manufacturing 1042)? Every single company has one                                                                                                                                           | No impact on filtering - used company_id and firmable_id as unique identifiers. Flagged for clarification with Brignet                           |
| 2     | Should Construction companies be verified to have a physical site before inclusion?                                                                                                                                                                                  | Included all construction companies - physical site not verifiable from data                                                                     |
| 3     | The hq_country field has 4 variations (AU, Australia, NZ, New Zealand) - should we standardise this?                                                                                                                                                                 | Used region_code instead which is clean (AU/NZ only)                                                                                             |
| 4     | Should there be a recency threshold on last_verified_date? Only 2,679 contacts were verified in 2026, majority last verified in 2024-2025                                                                                                                            | No date filter applied - brief did not specify a recency requirement                                                                             |
| 5     | The Brignet prior contacts file has 113 BRG-prefix IDs that didn't match any contact in our dataset - are these from a different system? Additionally, 343 Brignet emails match contacts in our pool - should email matching also be used to exclude prior contacts? | Only P-prefix IDs matched and removed (55 contacts). BRG-prefix and email matching flagged for clarification - brief had no instruction on this  |
| 6     | Should contacts approached by Brignet more than 12 months ago be re-included in the pool? Some campaign_date records are older than 12 months from today                                                                                                             | All 400 excluded - when measured from most recent campaign date (24 Apr 2026), all 400 falls within 12 months                                    |
| 7     | Some companies have blank web_domain values (200 blanks) - should these be excluded?                                                                                                                                                                                 | No action taken - web domain was not a filtering criterion                                                                                       |
| 8     | The brief specifically names Melbourne, Sydney, Brisbane and Adelaide metros - should we filter at suburb level within these cities rather than state level?                                                                                                         | State-level filtering only - metro/suburb prioritization too granular and risked reducing contact volume significantly                           |
| 9     | Should recently founded companies (last 2 years - 2022+) be flagged or prioritized? Brief mentions growth as a signal                                                                                                                                                | Not filtered - 182 companies founded 2022+ identified. Recommendation to sort final list with high-revenue recently founded companies at the top |

**POINT 2 - How I Resolved Conflicts or Ambiguities in the Brief**

The brief contained several points where rules conflicted or were under-specified. Here is each one and what was decided:

| **#** | **Conflict / Ambiguity**                                                                                                                          | **Decision Made**                                                                                   | **Reasoning**                                                                                                                                                                                               |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | **"Under 20 staff"** - does this mean exclude <20 (keep 20+) or exclude ≤20 (keep 21+)? 6 companies in the filtered set have exactly 20 employees | Kept 20 and above                                                                                   | "Under 20" means 19 and below qualify, so 20 and above are kept                                                                                                                                             |
| 2     | **"Mobile is critical" vs "give us email over mobile if only one"** - these two statements appear to contradict each other                        | Include mobile OR email, exclude landline only and neither                                          | Mobile is critical for calling, but email is preferred if only one exists. Both are valid contact methods - neither is excluded. Priority column added: Gold (1,545) → Email Only (655) → Mobile Only (268) |
| 3     | **"Facilities or Procurement"** - brief groups these as one group but they are two different departments                                          | Treated as two separate groups - Finance, Operations, Facilities, Procurement = 4 groups            | When all 4 groups exist in a company, Facilities is dropped (lowest priority) as it is least directly tied to energy spend decisions. Max 3 contacts per company maintained                                 |
| 4     | **"Mid-market Australian businesses"** - brief never defines what revenue range this means                                                        | Used \$10M+ across 5 revenue bands (\$10M-\$25M, \$25M-\$50M, \$50M-\$100M, \$100M-\$250M, \$250M+) | Majority of Australian sources (ATO, KPMG, BDO) define mid-market from \$10M. Grant Thornton uses \$50M but is the outlier. Started at \$100M+ and expanded down to \$10M+ iteratively to hit contact quota |
| 5     | **"Companies that have grown recently, like in the last 2 years"** - brief mentions growth but gives no instruction on how to use it              | Flagged for sorting, not filtering                                                                  | 50 companies within the filtered set of 956 were founded 2022 or later. Treated as a sort/prioritization signal rather than a hard filter to avoid reducing the contact pool                                |
| 6     | **"Victoria and NSW first... if we can't fill the quota"** - no quota defined                                                                     | Iterated through 3 state combinations until 3,000+ contacts achieved                                | VIC/NSW → 601 companies, 2,895 contacts. Added QLD/SA → 901 companies, 4,340 contacts. Added TAS/ACT/NT → 956 companies, 4,584 contacts                                                                     |
| 7     | **"Prioritize Melbourne and Sydney metro"** - brief names specific metros but data only has suburb level                                          | State-level filtering used                                                                          | Metro suburb filtering too granular - risked significantly reducing contact volume. State used as proxy for metro                                                                                           |
| 8     | **"Construction is fine too if they have a physical site"** - no way to verify physical site from data                                            | Included all 85 construction companies                                                              | No field in the dataset indicates physical site presence. All construction companies meeting other criteria were included and flagged as an assumption                                                      |
| 9     | **"No one we've already pitched in the last 12 months"** - 12 months from when?                                                                   | Measured from most recent campaign date (24 Apr 2026)                                               | All 400 Brignet contacts fall within 12 months when measured from most recent campaign date (24 Apr 2025 to 24 Apr 2026). All 400 excluded as a safe approach                                               |
| 10    | **NZ data present but brief only mentions Australia** - no explicit instruction to exclude NZ                                                     | Excluded all 810 NZ companies and 4,168 NZ contacts                                                 | Brief clearly focuses on Australian mid-market businesses. Region code used to identify and exclude all NZ records cleanly                                                                                  |

**POINT 3 - Role-Group Definitions**

**FINANCE GROUP - 860 contacts**

| **Role Title**           | **Count** |
| ------------------------ | --------- |
| Chief Financial Officer  | 122       |
| CFO                      | 120       |
| Head of Finance          | 112       |
| Finance Director         | 92        |
| Finance Manager          | 86        |
| Senior Financial Analyst | 79        |
| Accountant               | 76        |
| Financial Controller     | 59        |
| Finance Analyst          | 59        |
| Junior Accountant        | 55        |

**Seniority Hierarchy (top to bottom):** C-Level (242) → Head (112) → Director (92) → Manager (86) → Senior (134) → Mid (139) → Junior (55)

**Edge cases:**

- CFO and Chief Financial Officer - both classified as C-Level Finance. Treated as identical roles with different naming conventions
- Financial Controller - 55 classified as Senior (original data), 4 as Mid (inferred). Senior is the correct classification for this role
- 137 Finance contacts had seniority inferred from role title

**OPERATIONS GROUP - 865 contacts**

| **Role Title**          | **Count** |
| ----------------------- | --------- |
| COO                     | 125       |
| Chief Operating Officer | 111       |
| Head of Operations      | 102       |
| Site Manager            | 91        |
| Operations Manager      | 86        |
| Operations Director     | 82        |
| Plant Manager           | 72        |
| Operations Coordinator  | 69        |
| Operations Analyst      | 54        |
| Operations Lead         | 49        |
| Facilities Coordinator  | 24        |

**Seniority Hierarchy (top to bottom):** C-Level (263) → Head (102) → Director (82) → Manager (249) → Senior (47) → Mid (122)

**Edge cases:**

- COO and Chief Operating Officer - both classified as C-Level Operations. Treated as identical roles with different naming conventions
- Facilities Coordinator (24 contacts) - appears in Operations group because the role title matched the Operations keyword operations coordinator. Could arguably belong to Facilities - flagged as a potential misclassification
- Site Manager and Plant Manager - classified as Operations as they manage physical operational sites directly relevant to energy spend
- 153 Operations contacts had seniority inferred from role title

**FACILITIES GROUP - 228 contacts**

| **Role Title**     | **Count** |
| ------------------ | --------- |
| Head of Facilities | 92        |
| Facilities Manager | 69        |
| Facilities Officer | 67        |

**Seniority Hierarchy (top to bottom):** Head (92) → Manager (69) → Junior (55) → Mid (12)

**Edge cases:**

- Facilities is the **smallest group** - only 3 distinct role titles in the dataset
- No C-Level or Director in Facilities - highest seniority available is Head
- Facilities Officer - 55 classified as Junior and 12 as Mid. Junior classification came from original source data, not inferred
- Facilities is the **lowest priority group** - when a company has all 4 groups, Facilities is dropped to maintain the 3-contact cap
- 41 Facilities contacts had seniority inferred from role title

**PROCUREMENT GROUP - 515 contacts**

| **Role Title**       | **Count** |
| -------------------- | --------- |
| Head of Procurement  | 98        |
| Procurement Director | 92        |
| Strategic Buyer      | 90        |
| Procurement Analyst  | 80        |
| Buyer                | 78        |
| Procurement Manager  | 77        |

**Seniority Hierarchy (top to bottom):** Head (98) → Director (92) → Senior (90) → Manager (77) → Mid (158)

**Edge cases:**

- No C-Level in Procurement - highest seniority available is Head
- Strategic Buyer - classified as Senior via inferred logic (strategic keyword). Reasonable given the strategic nature of the role. All 90 confirmed as Senior
- Buyer - classified as Mid (78). Could be argued as Junior in some organizations but Mid is a safe assumption
- 81 Procurement contacts had seniority inferred from role title

**Seniority Inference Summary**

| **Group**   | **Original** | **Inferred** | **Total** |
| ----------- | ------------ | ------------ | --------- |
| Finance     | 723          | 137          | 860       |
| Operations  | 712          | 153          | 865       |
| Facilities  | 187          | 41           | 228       |
| Procurement | 434          | 81           | 515       |
| **Total**   | **2,056**    | **412**      | **2,468** |

**Point 4 - Contact-Tier Prioritisation:**

**Contact Priority Logic**

The brief states: _"Mobile is critical - if you have both mobile and email, that's gold. If you only have one, give us email over mobile. Last resort is landline."_

Three tiers were defined and a contact_priority column added to the final output:

| **Tier**        | **Condition**                                     | **Count** |
| --------------- | ------------------------------------------------- | --------- |
| 1 - Gold        | Mobile + Email both present                       | 1,545     |
| 2 - Email Only  | Email present, no mobile                          | 655       |
| 3 - Mobile Only | Mobile present, no email                          | 268       |
| Excluded        | Neither mobile nor email (landline only or blank) | -         |

**Priority by Group**

| **Group**   | **Gold** | **Email Only** | **Mobile Only** |
| ----------- | -------- | -------------- | --------------- |
| Operations  | 546      | 222            | 97              |
| Finance     | 530      | 241            | 89              |
| Procurement | 329      | 123            | 63              |
| Facilities  | 140      | 69             | 19              |

**Priority by Seniority**

| **Seniority** | **Gold** | **Email Only** | **Mobile Only** |
| ------------- | -------- | -------------- | --------------- |
| C-Level       | 326      | 121            | 58              |
| Head          | 264      | 99             | 41              |
| Manager       | 297      | 133            | 51              |
| Director      | 171      | 61             | 34              |
| Senior        | 171      | 77             | 23              |
| Mid           | 252      | 127            | 52              |
| Junior        | 64       | 37             | 9               |

**Ranking Logic Within a Group**

When selecting the most senior contact per group per company, the ranking was applied in this order:

- **Seniority rank** - C-Level (6) → Head (5) → Director (4) → Manager (3) → Senior (2) → Mid (1) → Junior (0)
- **Contact priority was not used as a tiebreaker** - seniority was the sole selection criterion. The most senior contact was selected regardless of whether they were Gold, Email Only or Mobile Only

**Tie Breaking**

- Maximum of 1 contact per group per company - enforced via deduplication after seniority sort
- Verified: max contacts per group per company = **1**, min = **1** - no ties in final output
- If two contacts in the same group had identical seniority, the first record in the sorted dataset was selected - no secondary tiebreaker was applied. This is flagged as a potential refinement - a secondary sort by contact_priority (Gold first) could be added

**Group Priority (3-contact cap)**

When a company had contacts across all 4 groups, the cap of 3 was enforced using this priority order:

- Finance
- Operations
- Procurement
- Facilities _(dropped when all 4 present)_

**Verified:**

| **Contacts**    | **Companies** |
| --------------- | ------------- |
| 3 contacts      | 597           |
| 2 contacts      | 320           |
| 1 contact       | 37            |
| Total companies | 954           |

**0 companies had all 4 groups** - the Facilities drop rule never triggered in practice

**419 companies** had 3 groups excluding Facilities - Finance, Operations and Procurement was the dominant combination

**178 companies** had 3 groups including Facilities - Facilities was retained in these cases as it was one of only 3 available groups

**Point 5 - Location-Prioritization Logic:**

**Brief Instruction:** _"Victoria and NSW first, prioritize Melbourne and Sydney metro if you can. If we can't fill the quota there, open up to Brisbane and Adelaide metros, then other regional areas. Definitely no WA."_

**Approach - State-level prioritization, iterative expansion**

Metro suburb filtering was considered but not implemented - too granular and risked significantly reducing contact volume. State was used as the proxy for metro. The brief's geographic expansion logic was followed at state level across 3 stages:

**Stage Funnel**

| **Stage** | **States Added** | **Companies** | **Contacts (pool)** |
| --------- | ---------------- | ------------- | ------------------- |
| Stage 1   | VIC, NSW         | 601           | 2,895               |
| Stage 2   | \+ QLD, SA       | 901           | 4,340               |
| Stage 3   | \+ TAS, ACT, NT  | 956           | 4,584               |

Stage 3 (all states ex-WA) was selected as the final combination to maximize the contact pool.

**Final 2,468 Contacts by State**

| **State** | **Companies** | **Contacts** |
| --------- | ------------- | ------------ |
| VIC       | 305           | 801          |
| NSW       | 295           | 756          |
| QLD       | 219           | 570          |
| SA        | 80            | 208          |
| TAS       | 30            | 73           |
| ACT       | 17            | 42           |
| NT        | 8             | 18           |
| **Total** | **954**       | **2,468**    |

**WA Exclusion**

|                       | **Count** |
| --------------------- | --------- |
| WA companies excluded | 84        |
| WA contacts excluded  | 396       |

Reason: Brief explicitly stated _"Definitely no WA - our retailer partnerships don't cover WA well."_

**Fallback Note**

Even after including all states ex-WA, the final decision-maker count of **2,468** falls short of the assumed 3,000 quota. This is the absolute maximum achievable within all brief conditions. The gap is documented in Point 8 - Gap Report.

**Point 6 - Data Quality Issues** with all 19 issues:

**COMPANIES FILE**

| **#** | **Issue**                                                                                                                                                                                                               | **How Spotted**                             | **What Was Done**                                                                                                | **Fixed or flagged**                                          |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| 1     | **Industry field - inconsistent casing and formatting** - Manufacturing appears as Manufacturing, Manufacturing (trailing space) and manufacturing. Cold Storage appears as Cold Storage, Cold-Storage and cold storage | Checking unique values in industry column   | Created industry_norm column using .str.strip().str.title() to normalize for filtering. Original column retained | Fixed for filtering - flagged as data quality issue at source |
| 2     | **hq_country - 4 inconsistent variations** - AU, Australia, NZ, New Zealand all present                                                                                                                                 | Checking unique values in hq_country column | Used region_code instead - clean with only AU and NZ                                                             | Flagged - region_code used as replacement                     |
| 3     | **web_domain - 200 blank values**                                                                                                                                                                                       | Null check on all columns                   | No action - web domain was not a filtering criterion                                                             | Flagged                                                       |
| 4     | **firmable_id - 510 duplicate values**                                                                                                                                                                                  | Duplicate check on key columns              | Expected - firmable_id is a linking key between companies and contacts. No action needed                         | Flagged as expected behavior                                  |
| 5     | **Company name number suffix** - every company name ends with a number (e.g. Cormane Partners Industries 2824)                                                                                                          | Pattern check on company_name column        | No filtering impact - company_id and firmable_id used as identifiers                                             | Flagged - clarification needed from Brignet                   |
| 6     | **NZ state names in hq_state** - Waikato, Canterbury, Bay of Plenty, Auckland, Otago, Wellington (810 records total)                                                                                                    | Checking unique values in hq_state column   | Excluded via region_code = 'AU' filter                                                                           | Fixed via region_code filter                                  |
| 7     | **Companies with 1 employee** - 27 companies in master file have only 1 employee. 23 of these survived other filters but were excluded by the 20+ employee condition                                                    | Checking employee min/max values            | Excluded by 20+ employee filter                                                                                  | Fixed by employee filter                                      |

**CONTACTS FILE**

| **#** | **Issue**                                                                                                                                                                                                                 | **How Spotted**                                            | **What Was Done**                                                                   | **Fixed or flagged**                                                           |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 8     | **Seniority - 2,632 blank values**                                                                                                                                                                                        | Null check on all columns                                  | Inferred from role title for contacts in final 2,468. seniority_source column added | Fixed via inference - flagged                                                  |
| 9     | **Mobile - 5,011 blank values**                                                                                                                                                                                           | Null check on all columns                                  | Contacts with neither mobile nor email excluded. Mobile-only = Tier 3 priority      | Flagged - handled via contact priority logic                                   |
| 10    | **Email - 2,499 blank values**                                                                                                                                                                                            | Null check on all columns                                  | Contacts with neither mobile nor email excluded. Email-only = Tier 2 priority       | Flagged - handled via contact priority logic                                   |
| 11    | **Landline - 8,456 blank values**                                                                                                                                                                                         | Null check on all columns                                  | Landline excluded as per brief                                                      | Flagged                                                                        |
| 12    | **393 contacts with no contact info at all** - no mobile, no email, no landline                                                                                                                                           | Cross-checking all three contact fields                    | Excluded from filtered pool                                                         | Fixed by contact filter                                                        |
| 13    | **last_verified_date - majority of contacts last verified in 2025** - only 2,679 verified in 2026, 8,384 in 2025, 5,814 in 2024                                                                                           | Checking date range and distribution                       | No filter applied - brief did not specify recency requirement                       | Flagged as data freshness risk                                                 |
| 14    | **Role title distribution - unusually uniform** - top role has 522 records, bottom 282, range of only 240                                                                                                                 | Checking value counts for role titles                      | No action - role titles used as-is                                                  | Flagged - possibly synthetic data. Worth confirming with Brignet               |
| 15    | **2,593 contact records appear to be exact duplicates** - same contact_id appears twice across 5,186 rows                                                                                                                 | Duplicate check on contact_id with merged company data     | No action - duplicates not identified until post-merge analysis                     | Flagged - significant data quality issue. Brignet should deduplicate at source |
| 16    | **57 emails shared across multiple contacts (114 contacts total)** - all shared emails are generic providers (Yahoo, Hotmail, Outlook). 20 corporate emails also shared                                                   | Cross-referencing email field across all contacts          | No action - brief does not require email uniqueness                                 | Flagged - shared generic emails suggest placeholder or test data               |
| 17    | **93 contacts at AU companies have NZ email domains (. co.nz)**                                                                                                                                                           | Cross-referencing email domain against company region_code | No action - email domain not a filtering criterion                                  | Flagged - may indicate NZ-based staff at AU companies or data error            |
| 18    | **3,178 email-domain mismatches** - contacts with email have a domain that doesn't match their company web domain. Breakdown: 1,316 generic providers, 858 blank web domain, 112 NZ domain, 889 different domain entirely | Cross-referencing email domain against web_domain field    | No action - email validity not a brief requirement                                  | Flagged - 1,316 personal emails in B2B list are a risk                         |

**BRIGNET PRIOR CONTACTS FILE**

| **#** | **Issue**                                                             | **How Spotted**                            | **What Was Done**                                                      | **Fixed or flagged**                                             |
| ----- | --------------------------------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 19    | **Two ID formats** - 287 P-prefix and 113 BRG-prefix IDs              | Checking unique values in prior_contact_id | Only P-prefix matched against master contacts. BRG-prefix had no match | Flagged - BRG-prefix origin unknown                              |
| 20    | **57 blank email values** in prior contacts file                      | Null check on all columns                  | No impact - prior contacts matched on contact_id not email             | Flagged                                                          |
| 21    | **343 Brignet emails match master contacts vs only 55 on contact_id** | Comparing email field across both files    | Not actioned - brief only instructed exclusion by contact ID           | Flagged - up to 343 contacts may have been previously approached |

**POINT 7 - What I Would Not Recommend Delivering Even Though It Technically Meets the Brief**

| **#** | **What**                                                                                                                                                                                                                          | **Why Not Recommended**                                                                                                                                                                                                                       | **Impact If included**                                                          |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1     | **NZ companies and contacts**                                                                                                                                                                                                     | NZ has different energy market regulations, retailer partnerships and pricing structures - not relevant to Brignet's outreach                                                                                                                 | Would add contacts but from a completely different market                       |
| 2     | **WA companies and contacts** - 84 companies and 403 contacts meet all criteria                                                                                                                                                   | Brief explicitly states _"Definitely no WA - our retailer partnerships don't cover WA well."_ Including WA contacts would send reps into a market Brignet cannot service                                                                      | Would add 403 contacts but reps would have no product to sell in that territory |
| 3     | **Revenue bands under \$10M** - 625 companies and 3,065 contacts with revenue Under \$1M, \$1M-\$5M or \$5M-\$10M meet all other criteria                                                                                         | Below mid-market threshold by all major Australian definitions (ATO, KPMG, BDO). Brief says "skew toward larger businesses" - these companies likely don't have the energy spend volume or budget authority to make the engagement worthwhile | Would significantly inflate contact numbers but dilute list quality             |
| 4     | **Non-target industries** - 486 companies in Retail, Real Estate, Media, Hospitality, Agriculture, Healthcare, IT, Education, Financial Services, Transportation, Professional Services meet revenue, employee and state criteria | Brief specifically names industries with high energy spend. These industries either have low energy spend profiles or are not the core target market for Brignet's energy products                                                            | Would add volume but reduce conversion likelihood significantly                 |
| 5     | **Companies with under 20 employees** - 167 companies and 794 contacts meet all other criteria                                                                                                                                    | Brief says _"we've had bad experiences with companies under 20 staff"; they don't have the volume."_ These companies lack the energy spend scale that makes outreach commercially viable                                                      | Would add 794 contacts but with historically poor conversion rates per brief    |
| 6     | **Landline-only contacts** - 361 contacts have a landline number but no mobile or email                                                                                                                                           | Brief explicitly deprioritizes landline - _"Last resort is landline but honestly we don't really call landlines anymore."_ Low answer rates and no email fallback makes these contacts operationally inefficient                              | Would add 361 contacts with very low likelihood of successful outreach          |

**POINT 8 - Gap Report**

**The Brief's Intent vs What Was Achievable**

The brief implied a target of 3,000+ contacts. After applying all conditions, the maximum achievable within the brief is **2,468 contacts**.

**COMPANY FUNNEL - How 956 ICP Companies Were Identified**

| **Step** | **Condition**              | **Companies** |
| -------- | -------------------------- | ------------- |
| Start    | All companies in master    | 3,810         |
| 1        | AU only (region_code = AU) | 3,000         |
| 2        | Target industries only     | 2,009         |
| 3        | Employees 20+              | 1,723         |
| 4        | Revenue \$10M+             | 1,040         |
| 5        | Exclude WA                 | **956**       |

**CONTACT FUNNEL - How 2,468 Decision Makers Were Identified**

| **Step** | **Condition**                                             | **Contacts** |
| -------- | --------------------------------------------------------- | ------------ |
| Start    | All contacts in master                                    | 16,877       |
| 1        | Mobile or email (exclude landline only / neither)         | 16,123       |
| 2        | Cross-reference to 956 companies                          | 4,654        |
| 3        | Remove Brignet prior contacts                             | 4,584        |
| 4        | Relevant groups only (Finance/Ops/Facilities/Procurement) | 3,694        |
| 5        | Most senior per group per company                         | 2,542        |
| 6        | Max 3 contacts per company                                | **2,468**    |

**CONTACTS PER COMPANY (final)**

| **Contacts** | **Companies** |
| ------------ | ------------- |
| 1 contact    | 37            |
| 2 contacts   | 320           |
| 3 contacts   | 597           |

**WHY 3,000 COULD NOT BE HIT**

The gap of 532 contacts is structural - not fixable without relaxing at least one brief condition:

| **Lever**                        | **Contacts Added** | **Trade-off**                         |
| -------------------------------- | ------------------ | ------------------------------------- |
| Include WA                       | ~403               | Violates brief - no retailer coverage |
| Include revenue under \$10M      | ~3,065             | Below mid-market definition           |
| Include non-target industries    | Significant        | Outside energy-spend profile          |
| Include companies under 20 staff | ~794               | Brief says poor conversion history    |
| Include landline only            | ~361               | Brief deprioritizes landline          |
| Include NZ                       | ~1,294             | Different market entirely             |

**Every remaining lever violates the brief.** The 2,468 figure is the absolute ceiling within all stated conditions.

**IF BRIGNET ASKED FOR 5,000 - WHERE WOULD QUALITY DEGRADE FIRST?**

Quality would degrade in this order:

- **Revenue band** - dropping to \$5M-\$10M adds volume (625 companies, ~3,065 contacts) but moves firmly into SME territory. Energy spend drops significantly below the threshold where Brignet's product is commercially viable
- **Employee threshold** - dropping below 20 staff adds 167 companies and ~794 contacts but brief already flagged poor conversion history with small companies
- **WA inclusion** - adds 84 companies and ~403 contacts but Brignet has no retailer partnerships there - reps would generate leads they can't service
- **Non-target industries** - adding Retail, Hospitality, Agriculture etc. adds 486 companies but these have fundamentally different energy profiles - likely low conversion
- **NZ inclusion** - adds 266 companies and ~1,294 contacts but entirely different regulatory and retail energy market - not comparable to AU operations

**The recommendation:** If Brignet needs 5,000 contacts, the data simply isn't there within the brief's parameters. The conversation should be about either refreshing the dataset with a larger data provider, or revisiting the brief conditions with sales leadership.