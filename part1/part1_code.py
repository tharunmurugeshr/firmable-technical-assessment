#!/usr/bin/env python
# coding: utf-8

# In[2]:


# Import package; needed for filtering
import pandas as pd


# In[3]:


# Load the CSV files
companies = pd.read_csv("companies.csv")
contacts = pd.read_csv("contacts.csv")
prior = pd.read_csv("brignet_prior_contacts.csv")


# In[4]:


# Check if records have been correctly loaded
print('Companies:', len(companies))
print('Contacts:', len(contacts))
print('Prior Contacts:', len(prior))


# In[5]:


# First look at data ; Preview all files
print('Companies Columns:')
print(companies.columns.tolist())
print()

print('Contacts Columns:')
print(contacts.columns.tolist())
print()

print('Prior Contacts Columns:')
print(prior.columns.tolist())
print()


# In[6]:


# Normalise industry by stripping spaces and converting to title case
companies['industry_norm'] = companies['industry'].str.strip().str.title()

# Consolidate Cold-Storage variant into Cold Storage
companies['industry_norm'] = companies['industry_norm'].str.replace('Cold-Storage', 'Cold Storage')

print(companies[['industry', 'industry_norm']].head(10))


# In[7]:


# Verify - should show only 7 clean industry values in norm column
print('Unique industry_norm values:')
print(companies['industry_norm'].value_counts())


# In[8]:


# Define target industries - 7 clean normalised values
target_industries = [
    'Manufacturing',
    'Warehousing',
    'Warehousing & Logistics',
    'Cold Storage',
    'Food Production',
    'Food & Beverage Manufacturing',
    'Construction'
]

# Define target revenue bands
target_revenue = ['$10M-$25M', '$25M-$50M', '$50M-$100M', '$100M-$250M', '$250M+']

print('Target Industries:', len(target_industries))
print('Target Revenue Bands:', len(target_revenue))


# In[9]:


# Company Data Funnel

# Start with all companies
all_companies = companies
print('All Companies:', len(all_companies))

# AU companies only using region_code
au_companies = all_companies[all_companies['region_code'] == 'AU']
print('AU Companies Only:', len(au_companies))

# Target industries only
industry_filtered = au_companies[au_companies['industry_norm'].isin(target_industries)]
print('Companies within Target Industries:', len(industry_filtered))

# Employees 20 and above
employees_filtered = industry_filtered[industry_filtered['employees'] >= 20]
print('Companies with Employees 20+:', len(employees_filtered))

# Revenue 10M and above
revenue_filtered = employees_filtered[employees_filtered['revenue_band'].isin(target_revenue)]
print('Companies making Revenue 10M+:', len(revenue_filtered))

# Exclude WA
final_companies = revenue_filtered[revenue_filtered['hq_state'] != 'WA']
print('Final Companies after excluding WA:', len(final_companies))


# In[10]:


# Contacts Data Funnel

# Start with all contacts
all_contacts = contacts
print('All Contacts:', len(all_contacts))

# Mobile filter - must have mobile number or email or both
mobile_filtered = all_contacts[all_contacts['mobile'].notna() | all_contacts['email'].notna()]
print('Contacts with Mobile or Email:', len(mobile_filtered))

# Cross reference with final 956 companies using firmable_id
final_fids = set(final_companies['firmable_id'])
qualified_contacts = mobile_filtered[mobile_filtered['firmable_id'].isin(final_fids)]
print('Contacts from 956 qualified companies:', len(qualified_contacts))


# In[11]:


# Exclude Brignet Prior Contacts

# Get prior contact IDs from Brignet Prior Contact sheet
prior_ids = set(prior['prior_contact_id'])
print('Prior contacts to remove:', len(prior_ids))

# Remove prior contacts from qualified contacts
final_contacts = qualified_contacts[~qualified_contacts['contact_id'].isin(prior_ids)]
print('Contacts after removing prior:', len(final_contacts))

# How many were removed
removed = len(qualified_contacts) - len(final_contacts)
print('Contacts removed:', removed)

# 287 had P-prefix IDs — but only 55 matched contacts in our qualified pool
# 113 had BRG-prefix IDs — none matched our contact IDs at all


# In[12]:


# Full Funnel Summary

print('COMPANY FUNNEL')
print('All companies:                    ', len(all_companies))
print('AU only:                          ', len(au_companies))
print('Target industries:                ', len(industry_filtered))
print('Employees 20+:                    ', len(employees_filtered))
print('Revenue 10M+:                     ', len(revenue_filtered))
print('Exclude WA - Final companies:     ', len(final_companies))
print()
print('CONTACT FUNNEL')
print('All contacts:                     ', len(all_contacts))
print('Contacts with mobile or email:    ', len(mobile_filtered))
print('Contacts from 956 companies:      ', len(qualified_contacts))
print('After removing prior contacts:    ', len(final_contacts))


# In[13]:


# Define keywords for each decision-maker group
finance_keywords = ['cfo', 'chief financial', 'finance director', 'head of finance',
                    'finance manager', 'financial controller', 'financial analyst',
                    'senior financial', 'finance analyst', 'accountant', 'treasurer']

operations_keywords = [r'\bcoo\b', 'chief operating', 'operations director', 'head of operations',
                       'operations manager', 'operations lead', 'operations coordinator',
                       'operations analyst', 'site manager', 'plant manager',
                       'facilities coordinator']

facilities_keywords = ['head of facilities', 'facilities manager', 'facilities officer', 'facilities']

procurement_keywords = ['procurement director', 'head of procurement', 'procurement manager',
                        'strategic buyer', 'procurement analyst', 'buyer', 'purchasing']

# Seniority ranking - higher number = more senior
seniority_rank = {
    'C-Level': 6, 'Head': 5, 'Director': 4,
    'Manager': 3, 'Senior': 2, 'Mid': 1, 'Junior': 0
}

# Contact priority ranking - lower number = more reachable
contact_priority_rank = {
    '1 - Gold (Mobile + Email)': 1,
    '2 - Email Only': 2,
    '3 - Mobile Only': 3
}

print('Keywords and rankings defined')


# In[14]:


# Lowercase role titles for matching
final_contacts['role_lower'] = final_contacts['role_title'].str.lower()

# Classify into groups - order matters, first match wins
final_contacts['group'] = None
final_contacts.loc[final_contacts['group'].isna() & final_contacts['role_lower'].str.contains('|'.join(finance_keywords), na=False), 'group'] = 'Finance'
final_contacts.loc[final_contacts['group'].isna() & final_contacts['role_lower'].str.contains('|'.join(operations_keywords), na=False), 'group'] = 'Operations'
final_contacts.loc[final_contacts['group'].isna() & final_contacts['role_lower'].str.contains('|'.join(facilities_keywords), na=False), 'group'] = 'Facilities'
final_contacts.loc[final_contacts['group'].isna() & final_contacts['role_lower'].str.contains('|'.join(procurement_keywords), na=False), 'group'] = 'Procurement'

# Keep only contacts with a group
with_group = final_contacts[final_contacts['group'].notna()].copy()

print('Before group filter:', len(final_contacts))
print('After group filter:', len(with_group))
print()
print('By group:')
print(with_group['group'].value_counts())


# In[15]:


# Assign contact priority tier
with_group['contact_priority'] = None

# Gold - has both mobile and email
with_group.loc[with_group['mobile'].notna() & with_group['email'].notna(), 'contact_priority'] = '1 - Gold (Mobile + Email)'

# Email only - has email but no mobile
with_group.loc[with_group['email'].notna() & with_group['mobile'].isna(), 'contact_priority'] = '2 - Email Only'

# Mobile only - has mobile but no email
with_group.loc[with_group['mobile'].notna() & with_group['email'].isna(), 'contact_priority'] = '3 - Mobile Only'

print('Contact priority distribution:')
print(with_group['contact_priority'].value_counts().sort_index())


# In[16]:


# Flag which contacts have blank seniority
with_group['seniority_source'] = 'Original'
with_group.loc[with_group['seniority'].isna(), 'seniority_source'] = 'Inferred from role title'

# Infer seniority from role title for blanks
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains(r'\bcfo\b|\bcoo\b|\bceo\b|chief', regex=True), 'seniority'] = 'C-Level'
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains('head of'), 'seniority'] = 'Head'
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains('director|managing director'), 'seniority'] = 'Director'
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains('manager'), 'seniority'] = 'Manager'
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains('senior|strategic'), 'seniority'] = 'Senior'
with_group.loc[with_group['seniority'].isna() & with_group['role_lower'].str.contains('junior'), 'seniority'] = 'Junior'
with_group.loc[with_group['seniority'].isna(), 'seniority'] = 'Mid'

print('Seniority source:')
print(with_group['seniority_source'].value_counts())
print()
print('Seniority distribution:')
print(with_group['seniority'].value_counts())


# In[17]:


# Map seniority and contact priority to numeric ranks
with_group['seniority_rank'] = with_group['seniority'].map(seniority_rank).fillna(1)
with_group['contact_priority_rank'] = with_group['contact_priority'].map(contact_priority_rank)

# Sort by company, group, seniority (highest first), contact priority (best first) as tiebreaker
with_group_sorted = with_group.sort_values(
    ['firmable_id', 'group', 'seniority_rank', 'contact_priority_rank'],
    ascending=[True, True, False, True]
)

# Keep only the most senior per group per company
best_per_group = with_group_sorted.drop_duplicates(subset=['firmable_id', 'group'], keep='first')

print('After seniority filter:', len(best_per_group))
print()
print('By group:')
print(best_per_group['group'].value_counts())


# In[18]:


# Define group priority for the 3-contact cap
group_priority = {'Finance': 1, 'Operations': 2, 'Procurement': 3, 'Facilities': 4}

# Map group priority to each contact
best_per_group['group_priority'] = best_per_group['group'].map(group_priority)

# Sort by company then group priority
best_per_group_sorted = best_per_group.sort_values(['firmable_id', 'group_priority'])

# Keep max 3 contacts per company
final_decision_makers = best_per_group_sorted.groupby('firmable_id').head(3).copy()

print('After 3-contact cap:', len(final_decision_makers))
print('Companies covered:', final_decision_makers['firmable_id'].nunique())
print()
print('By group:')
print(final_decision_makers['group'].value_counts())
print()
print('Contacts per company:')
print(final_decision_makers.groupby('firmable_id').size().value_counts().sort_index())


# In[19]:


# Merge company details into final contacts
final_output = final_decision_makers.merge(
    final_companies[['firmable_id', 'company_id', 'company_name', 'industry_norm',
                      'employees', 'revenue_band', 'hq_state', 'hq_suburb', 'region_code']],
    on='firmable_id', how='left'
)

# Rename normalised columns for output
final_output = final_output.rename(columns={
    'industry_norm': 'industry',
    'region_code': 'hq_country'
})

# Clean mobile and landline - remove decimal points
final_output['mobile'] = final_output['mobile'].dropna().astype(int).astype(str)
final_output['landline'] = final_output['landline'].dropna().astype(int).astype(str)

# Add selection reasoning column
final_output['selection_reasoning'] = (
    'Selected as most senior ' + final_output['group'] + ' contact at this company '
    '(Role: ' + final_output['role_title'] + ', '
    'Seniority: ' + final_output['seniority'] + ', '
    'Source: ' + final_output['seniority_source'] + ', '
    'Contact Priority: ' + final_output['contact_priority'] + ')'
)

# Select and order final columns
output_cols = ['contact_id', 'firmable_id', 'company_id', 'full_name', 'role_title',
               'seniority', 'seniority_source', 'group', 'email', 'mobile', 'landline',
               'last_verified_date', 'contact_priority', 'company_name', 'industry',
               'employees', 'revenue_band', 'hq_state', 'hq_suburb', 'hq_country',
               'selection_reasoning']

final_output = final_output[output_cols].sort_values(['hq_state', 'company_name', 'group'])

# Save to Excel
final_output.to_excel('prioritised_contacts_version2.xlsx', index=False)

print('Saved:', len(final_output), 'rows')
print('Columns:', final_output.columns.tolist())

