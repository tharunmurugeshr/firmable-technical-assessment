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


# Industry needs normalising by removing spaces and converting to title case
# Creating new column 'industry_norm' to retain raw data
companies['industry_norm'] = companies['industry'].str.strip().str.title()

# Preview to Confirm
print(companies[['industry','industry_norm']].head(10))


# In[7]:


# Define filter conditions
# Define target industries
target_industries = ['Manufacturing','Warehousing','Warehousing & Logistics','Cold Storage','Cold-Storage','Food Production','Food & Beverage Manufacturing','Construction']

# Define target revenue bands
target_revenue = ['$10M-$25M','$25M-$50M','$50M-$100M','$100M-$250M','$250M+']

print('Target Industries:', len(target_industries))
print('Target Revenue Bands:', len(target_revenue))


# In[12]:


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


# In[14]:


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


# In[15]:


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


# In[16]:


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


# In[ ]:




