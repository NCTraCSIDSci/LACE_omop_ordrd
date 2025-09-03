# LACE Hospital Readmission Index README
This repository contains code developed by the TraCS Data Science Lab, which is part of the School of Medicine at the University of North Carolina at Chapel Hill.

## LACE Background
The LACE hospital readmission index, formulated by van Walraven et al. (2010), is a method to predict the likelihood of either death or an unplanned patient readmission within 30 days of discharge from a hospital. The index is composed of four components: Length of hospital stay in days, Acuity of admission, Charlson Comorbidity Index of the patient, and the number of ER visits in the past 6 months. The scores can vary from 0 to 19. 

The LACE index has been included in many studies analyzing readmission rates. Specific examples include applications to patients with COVID-19 (McAlister et al. 2022), heart failure (Ingles 2020), or to assess the utilization of transitional care management visits (Kim et al. 2025). It has also been expanded by van Walraven, Wong, and Forster (2012) to create the LACE+ index which additionally includes patient age, sex, hospital teaching status, acute diagnoses and procedures performed during admission, number of days on alternative level of care during the admission, and number of elective and urgent admissions in the previous year.

Here we present an implementation of the original LACE index described by van Walraven et al. (2010).

## Structure of Code
We provide Python, R, and PostgreSQL programs to calculate the LACE index. All execute the same logic outlined below and have been confirmed to return the same results. 

## Code Source Environment Notes
This code is designed to work on Observational Medical Outcomes Partnerships (OMOP) databases. We utilized the OMOP Common Data Model v5.3 for development in the University of North Carolina at Chapel Hill de-identified OMOP Research Data Repository, ORDR(D).

## Methods Applied to the Calculation
The code generates a LACE score for every inpatient visit. We use the OMOP *visit_occurrence* table for the visit information and the *condition_occurrence* and *person* tables for calculating the Charlson Comorbidity Index. 

Inpatient visits are defined as OMOP concept ID 262 (Emergency Room and Inpatient Visit) or 9201 (Inpatient Visit). We additionally use OMOP concept ID 9203 (Emergency Room Visit) for the calculation of the number of ER visits in the previous six months. Below we give additional details about the calculation of each component. 

### Length of Stay
Length of stay is calculated as the difference between the *visit_end_date* and *visit_start_date* fields in the *visit_occurence* table. The length of stay can be zero. The L component of the LACE score is calculated according to Table 3 of van Walraven et al. (2010):

| Length of stay (days) | 0 | 1 | 2 | 3 | 4–6 | 7–13 | ≥14 |
|------------------------|---|---|---|---|-----|------|-----|
| **L Score**            | 0 | 1 | 2 | 3 |  4  |  5   |  7  |

### Acuity of Admission
An acute admission refers to a hospital admission that occurs without prior scheduling or planning. Each visit in the OMOP CDM is assigned a *visit_concept_id*, which describes the kind of visit that took place (Outpatient, Inpatient, Telehealth, Emergency Room, etc.). The admission acuity is recorded in the source EHR data record as a standard UB-04 value; however, the OMOP CDM does not currently bring in UB-04 values or the discrete admission acuity UB values.

We examined the overlap between the UB-04 values and the OMOP *visit_concept_ids* within our internal EHR data. Of the non-NULL values for concept ID 262 (Emergency Room and Inpatient Visit), 99.1% were recorded as having an admittance priority of Emergency, 0.6% were Urgent visits, 0.1% were Trauma Center visits, and 0.1% were Elective visits. Of the non-NULL values for concept ID 9201 (Inpatient Visit), 51.9% were recorded as Elective visits, 23.4% were Newborn visits, 18.2% were Urgent visits, and 6.4% were Emergency visits. Visits with a concept ID of 262 are overwhelmingly acute admissions. There is more variability in visits with a concept ID of 9201, but with over 75% of those visits clearly non-acute, it is generally accurate to consider these visits as non-acute. Therefore, for the purposes of this calculation of the LACE score, we assign visits with concept ID of 262 as acute visits, and visits with concept ID of 9201 as non-acute visits. 

The A component of the LACE score is calculated according to Table 3 of van Walraven et al. (2010):

| Acuity of admission     | Non-acute (visit_concept_id 9201) | Acute (visit_concept_id 262) |
|-------------------------|------------------------------------|-------------------------------|
| **A Score**             | 0                                  | 3                             |

### Charlson Comorbidity Index
The Charlson Comorbidity Index (CCI) is a commonly used measure of disease burden. van Walraven et al. (2010) calculated the CCI using ICD-9 codes from Quan et al. (2005) and weights from Schneeweiss et al. (2003). We similarly use the ICD-9 and ICD-10 codes from Quan et al. (2005) to identify and classify the comorbid conditions. But instead use the original weights from Charlson et al. (1987). The weights are easy to change is users prefer different weights.

The implementation of the CCI is based on the version we published here: [https://github.com/NCTraCSIDSci/charlson_comorbidity_omop_ordrd](https://github.com/NCTraCSIDSci/charlson_comorbidity_omop_ordrd). We have modified that code slightly to calculate the CCI at the end of each inpatient visit, excluding conditions that start after that date. Please see that code for additional details on this calculation.

The CCI is converted to the C component of the LACE score according to Table 3 of van Walraven et al. (2010):
| Charlson Comorbidity Index | 0 | 1 | 2 | 3 | ≥4 |
|----------------------------|---|---|---|---|----|
| **C Score**                | 0 | 1 | 2 | 3 | 5  |

### Emergency Room Visits in the Past 180 Days
van Walraven et al. (2010) defined the E component of the LACE index as the number of ER visits in the previous six months. We implemented this as ER visits in the previous 180 days, calculated from the visit start date. ER visits which occurred on the same day as the inpatient visits, and were independent of that inpatient visit, are included in the count. 

The E component of the LACE score is calculated according to Table 3 of van Walraven et al. (2010):
| ER Visits in Past 180 Days | 0 | 1 | 2 | 3 | ≥4 |
|----------------------------|---|---|---|---|----|
| **E Score**                | 0 | 1 | 2 | 3 | 4  |

### Final LACE Score
The final LACE Score is calculated by summing the individual components L, A, C, and E. 

## Limitations/Calculation Aspects to Consider
We emphasize again that Acuity is determined based on using the *visit_concept_id* as a proxy for admission reason. While mostly accurate, having access to the foundational reason for admission would improve the accuracy of this calculation. 

Calculating the CCI using EHR data is not a straightforward process. For considerations about the calculation of the CCI using OMOP, please refer to our standalone CCI Repo: [https://github.com/NCTraCSIDSci/charlson_comorbidity_omop_ordrd](https://github.com/NCTraCSIDSci/charlson_comorbidity_omop_ordrd).

The LACE indices produced in this code should be thought of as LACE index minimums. For individual patients, any missing data in the database (i.e. from care in a different health care system) would only potentially increase the CCI or number of ER visits in the previous 180 days. 

## Authors
Nathan Foster and Josh Fuchs developed this code. 

## Citing This Repo
If you use this software in your work, please cite it using the CITATION.cff file or by clicking "Cite this repository" on the right. 

## Support
The project described was supported by the National Center for Advancing Translational Sciences (NCATS), National Institutes of Health, through Grant Award Number UM1TR004406. The content is solely the responsibility of the authors and does not necessarily represent the official views of the NIH.

# References
1.	Charlson, M. E., P. Pompei, K. L. Ales, and C. R. MacKenzie. 1987. “A New Method of Classifying Prognostic Comorbidity in Longitudinal Studies: Development and Validation.” Journal of Chronic Diseases 40 (5): 373–83.
2.	Ingles, Aileen. 2020. “Heart Failure Nurse Navigator Program Interventions Based on LACE Scores Reduces Inpatient Heart Failure Readmission Rates.” Heart & Lung: The Journal of Critical Care 49 (2): 219.
3.	Kim, Eun Ji, Kevin Coppa, Sara Abrahams, Amresh D. Hanchate, Sumit Mohan, Martin Lesser, and Jamie S. Hirsch. 2025. “Utilization of Transitional Care Management Services and 30-Day Readmission.” PloS One 20 (1): e0316892.
4.	McAlister, Finlay A., Yuan Dong, Anna Chu, Xuesong Wang, Erik Youngson, Kieran L. Quinn, Amol Verma, et al. 2022. “The Risk of Death or Unplanned Readmission after Discharge from a COVID-19 Hospitalization in Alberta and Ontario.” Journal de l’Association Medicale Canadienne [Canadian Medical Association Journal] 194 (19): E666–73.
5.	Quan, Hude, Vijaya Sundararajan, Patricia Halfon, Andrew Fong, Bernard Burnand, Jean-Christophe Luthi, L. Duncan Saunders, Cynthia A. Beck, Thomas E. Feasby, and William A. Ghali. 2005. “Coding Algorithms for Defining Comorbidities in ICD-9-CM and ICD-10 Administrative Data.” Medical Care 43 (11): 1130–39.
6.	Schneeweiss, Sebastian, Philip S. Wang, Jerry Avorn, and Robert J. Glynn. 2003. “Improved Comorbidity Adjustment for Predicting Mortality in Medicare Populations: Improved Comorbidity Adjustment in Medicare Populations.” Health Services Research 38 (4): 1103–20.
7.	Walraven, Carl van, Irfan A. Dhalla, Chaim Bell, Edward Etchells, Ian G. Stiell, Kelly Zarnke, Peter C. Austin, and Alan J. Forster. 2010. “Derivation and Validation of an Index to Predict Early Death or Unplanned Readmission after Discharge from Hospital to the Community.” Journal de l’Association Medicale Canadienne [Canadian Medical Association Journal] 182 (6): 551–57.
8.	Walraven, Carl van, Jenna Wong, and Alan J. Forster. 2012. “LACE+ Index: Extension of a Validated Index to Predict Early Death or Urgent Readmission after Hospital Discharge Using Administrative Data.” Open Medicine: A Peer-Reviewed, Independent, Open-Access Journal 6 (3): e80-90.


