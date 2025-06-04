# LACE Hospital Readmission Index

# This calculation of the  LACE Hospital Readmission Index has been designed 
# to work on the OMOP CDM v5.3 and developed in the University of North 
# Carolina at Chapel Hill de-identified OMOP Research Data Repository, ORDR(D).
# Please see the README in the repo with important notes, clarifications, 
# and assumptions.

# Author: Nathan Foster

# Copyright 2025, The University of North Carolina at Chapel Hill. 
# Permission is granted to use in accordance with the MIT license. 
# The code is licensed under the open-source MIT license. 

# Set username and password
username = 'username'
pw = 'password'

# Load libraries
library(RPostgreSQL)
library(DBI)
library(tidyverse)
library(jsonlite)

### Query OMOP ###
# Open server connection, define the correct query string, and query the server. 

# Configure connection to OMOP database
conn = dbConnect(PostgreSQL(),
                 dbname= 'ordrd',
                 host = 'od2-primary',
                 port = 5432,
                 user = username,
                 password = pw)

# Define Query
# visit_concept_id 262 corresponds to an ER visit with subsequent inpatient stay
# visit_concept_id 9201 corresponds to an inpatient visit alone
# visit_concept_id 9203 corresponds to an ER visit alone
# To limit the date range, add a line at the end of visit_query:
# and visit_start_date > '2022/01/01'
visit_query = ("\
                SELECT visit_occurrence_id, person_id, visit_concept_id, 
                visit_start_date, visit_end_date
                FROM omop.visit_occurrence
                WHERE visit_concept_id IN (262, 9201, 9203);
                ")

# Query the database 
visit_raw_query <- dbGetQuery(conn, visit_query)

# Select only inpatient visits (ER + inpatient or inpatient alone)
inpatient_visits <- filter(visit_raw_query, visit_concept_id %in% c(262, 9201))



### 1: Length of Stay ###
# A score is assigned based on the length of the inpatient stay. 

length_of_stay <- inpatient_visits %>%
  mutate(length = visit_end_date - visit_start_date) %>%
  mutate(l_score = case_when(length < 1 ~ 0,
                             length == 1 ~ 1,
                             length == 2 ~ 2,
                             length == 3 ~ 3,
                             length >= 4 & length <= 6 ~ 4,
                             length >= 7 & length <= 13 ~ 5,
                             length >= 14 ~ 7)) %>%
  select(visit_occurrence_id, l_score)



### 2: Acuity of Admission ###
# Acuity of admission is inferred from the type of visit. An inpatient visit 
# alone, visit_concept_id = 9201, is considered a non-emergent/non-acute 
# admission. An ER visit followed by an inpatient visit, 
# visit_concept_id = 262, is considered an emergent/acute admission. 
# For a more detained discussion, consult the README. 

acuity_of_admission <- inpatient_visits %>%
  mutate(a_score = case_when(visit_concept_id == 262 ~ 3,
                             visit_concept_id == 9201 ~ 0)) %>%
  select(visit_occurrence_id, a_score)



### 3: Charlson comorbidity index ###
# Calculates the CCI for each inpatient visit to convert to the C component 
# of LACE. See the README for details about this calculation.

# Helper Functions

# Because Quan (2005) defines conditions 437 and 437.3 separately, for each person
# with condition 437.3, if condition 437 is not already present, it is added.
duplicate_condition_4373 <- function(df) {
  # Get all rows with condition 4373
  con_4373_df = filter(df, condition_source_value == "4373")
  
  # Replace condition code 4373 with code 437 in all rows
  con_4373_df['condition_source_value'][con_4373_df['condition_source_value'] == '4373'] <- '437'
  
  # Add these rows back to the dataframe, now with condition code 437
  # Duplicate rows (where that person already has condition 437 listed) are not added
  df <- union(df, con_4373_df)
  
  return(df)
}

# The codes V43.4, V42.7, V42.0, V45.1, and V56.x can correspond to different 
# conditions whether they are in ICD9 or ICD10. Check for these codes and, if 
# they are in ICD10, remove them from the dataframe. 
remove_certain_icd10_codes <- function(df) {
  to_remove <- filter(df, condition_source_value %in% c('V434', 'V427', 'V420', 'V451', 'V56') &
                        condition_source_concept_vocabulary_id == "ICD10CM")
  
  df <- anti_join(df, to_remove)
  
  return(df)
}


# Parse condition dictionary

# Directly parse the condition_dictionary from a list of lists. 
# This dictionary lists the name of the condition, all corresponding ICD codes,
# and the condition's Charlson Comorbidity Index weight.
# Both ICD-9 and ICD-10 codes from Quan et al. (2005) are included. 
# These have been stripped of periods to make matching easier in the database.
# We use the weights from Charlson et al. (1987)
condition_dictionary <- list(
  list("condition"="myocardial infarction", "icd"=list("410", "412", "I21", "I22", "I252"), "charlson87_weight"=as.integer(1)),
  list("condition"="congestive heart failure", "icd"=list("39891", "40201", "40211", "40291", "40401", 
                                                          "40403", "40411", "40413", "40491", "40493", 
                                                          "4254", "4255", "4256", "4257", "4258", "4259", 
                                                          "428", "I099", "I110", "I130", "I132", "I255", 
                                                          "I420", "I425", "I426", "I427", "I428", "I429", 
                                                          "P290", "I43", "I50"), "charlson87_weight"=as.integer(1)),
  list("condition"="peripheral vascular disease", "icd"=list("0930", "4373", "4431", "4432", "4433", "4434", 
                                                             "4435", "4436", "4437", "4438", "4439", "4471", 
                                                             "5571", "5579", "V434", "440", "441", "I731", 
                                                             "I738", "I739", "I771", "I790", "I792", "K551", 
                                                             "K558", "K559", "Z958", "Z959", "I70", "I71"), "charlson87_weight"=as.integer(1)),
  list("condition"="cerebrovascular disease", "icd"=list("430", "431", "432", "433", "434", "435", "436", 
                                                         "437", "438", "36234", "G45", "G46", "I60", "I61", 
                                                         "I62", "I63", "I64", "I65", "I66", "I67", "I68", 
                                                         "I69", "H340"), "charlson87_weight"=as.integer(1)),
  list("condition"="dementia", "icd"=list("29410", "29411", "3312", "290", "F051", "G311", "F00", "F01", 
                                          "F02", "F03", "G30"), "charlson87_weight"=as.integer(1)),
  list("condition"="chronic pulmonary disease", "icd"=list("490", "491", "492", "493", "494", "495", "496", 
                                                           "500", "501", "502", "503", "504", "505", "4168", 
                                                           "4169", "5064", "5081", "5088", "J40", "J41", 
                                                           "J42", "J43", "J44", "J45", "J46", "J47", "J60", 
                                                           "J61", "J62", "J63", "J64", "J65", "J66", "J67", 
                                                           "I278", "I279", "J684", "J701", "J703"), "charlson87_weight"=as.integer(1)),
  list("condition"="connective tissue disease", "icd"=list("4465", "7100", "7101", "7102", "7103", "7104", 
                                                           "7140", "7141", "7142", "7148", "725", "M315", 
                                                           "M351", "M353", "M360", "M05", "M32", "M33", 
                                                           "M34", "M06"), "charlson87_weight"=as.integer(1)),
  list("condition"="ulcer disease", "icd"=list("531", "532", "533", "534", "K25", "K26", "K27", "K28"), "charlson87_weight"=as.integer(1)),
  list("condition"="mild liver disease", "icd"=list("07022", "07023", "07032", "07033", "07044", "07054", 
                                                    "0706", "0709", "5733", "5734", "5738", "5739", "V427", 
                                                    "570", "571", "K700", "K701", "K702", "K703", "K709", 
                                                    "K717", "K713", "K714", "K715", "K760", "K762", "K763", 
                                                    "K764", "K768", "K769", "Z944", "B18", "K73", "K74"), "charlson87_weight"=as.integer(1)),
  list("condition"="diabetes without complications", "icd"=list("2500", "2501", "2502", "2503", "2508", "2509", 
                                                                "E100", "E101", "E106", "E108", "E109", "E110", 
                                                                "E111", "E116", "E118", "E119", "E120", "E121", 
                                                                "E126", "E128", "E129", "E130", "E131", "E136", 
                                                                "E138", "E139", "E140", "E141", "E146", "E148", 
                                                                "E149"), "charlson87_weight"=as.integer(1)),
  list("condition"="hemiplegia", "icd"=list("3341", "3440", "3441", "3442", "3443", "3444", "3445", "3446", 
                                            "3449", "342", "343", "G041", "G114", "G801", "G802", "G830", 
                                            "G831", "G832", "G833", "G834", "G839", "G81", "G82"), "charlson87_weight"=as.integer(2)),
  list("condition"="renal disease", "icd"=list("40301", "40311", "40391", "40402", "40403", "40412", "40413", 
                                               "40492", "40493", "5830", "5831", "5832", "5834", "5836", 
                                               "5837", "5880", "V420", "V451", "582", "585", "586", "V56", 
                                               "N18", "N19", "N052", "N053", "N054", "N055", "N056", "N057", 
                                               "N250", "I120", "I131", "N032", "N033", "N034", "N035", "N036", 
                                               "N037", "Z490", "Z491", "Z492", "Z940", "Z992"), "charlson87_weight"=as.integer(2)),
  list("condition"="diabetes with complications", "icd"=list("2504", "2505", "2506", "2507", "E102", "E103", 
                                                             "E104", "E105", "E107", "E112", "E113", "E114", 
                                                             "E115", "E117", "E122", "E123", "E124", "E125", 
                                                             "E127", "E132", "E133", "E134", "E135", "E137", 
                                                             "E142", "E143", "E144", "E145", "E147"), "charlson87_weight"=as.integer(2)),
  list("condition"="cancer", "icd"=list("140", "141", "142", "143", "144", "145", "146", "147", "148", "149", 
                                        "150", "151", "152", "153", "154", "155", "156", "157", "158", "159", 
                                        "160", "161", "162", "163", "164", "165", "170", "171", "172", "174", 
                                        "175", "176", "179", "180", "181", "182", "183", "184", "185", "186", 
                                        "187", "188", "189", "190", "191", "192", "193", "194", "195", "200", 
                                        "201", "202", "203", "204", "205", "206", "207", "208", "2386", "C00", 
                                        "C01", "C02", "C03", "C04", "C05", "C06", "C07", "C08", "C09", "C10", 
                                        "C11", "C12", "C13", "C14", "C15", "C16", "C17", "C18", "C19", "C20", 
                                        "C21", "C22", "C23", "C24", "C25", "C26", "C30", "C31", "C32", "C33", 
                                        "C34", "C37", "C38", "C39", "C40", "C41", "C43", "C45", "C46", "C47", 
                                        "C48", "C49", "C50", "C51", "C52", "C53", "C54", "C55", "C56", "C57", 
                                        "C58", "C60", "C61", "C62", "C63", "C64", "C65", "C66", "C67", "C68", 
                                        "C69", "C70", "C71", "C72", "C73", "C74", "C75", "C76", "C81", "C82", 
                                        "C83", "C84", "C85", "C88", "C90", "C91", "C92", "C93", "C94", "C95", 
                                        "C96", "C97"), "charlson87_weight"=as.integer(2)),
  list("condition"="moderate or severe liver disease", "icd"=list("4560", "4561", "4562", "5722", "5723", 
                                                                  "5724", "5728", "K704", "K711", "K721", 
                                                                  "K729", "K765", "K766", "K767", "I850", 
                                                                  "I859", "I864", "I982"), "charlson87_weight"=as.integer(3)),
  list("condition"="metastatic cancer", "icd"=list("196", "197", "198", "199", "C77", "C78", "C79", "C80"), "charlson87_weight"=as.integer(6)),
  list("condition"="aids", "icd"=list("042", "043", "044", "B20", "B21", "B22", "B24"), "charlson87_weight"=as.integer(6))
)

# Convert condition_dictionary to a DataFrame
condition_df <- tibble(condition_dictionary) %>%
  unnest_wider(condition_dictionary)

# Flatten condition_df by making each ICD code its own row
condition_df_long <- condition_df %>%
  unnest_longer(icd)

# Define three strings, one each for ICD codes with length 3, 4, and 5.
# These will be formatted as SQL lists, so that they can be added to the SQL
# query string below. 
con_icd_3 = "("
con_icd_4 = "("
con_icd_5 = "("

# For each ICD code in the dictionary, find its length, and add it to the right list. 
for (i in 1:nrow(condition_df_long)) {
  
  icd_code = condition_df_long$"icd"[i]
  
  if (nchar(icd_code) == 3) {
    con_icd_3 = paste(con_icd_3, "'", icd_code, "', ", sep="")
  } else if (nchar(icd_code) == 4) {
    con_icd_4 = paste(con_icd_4, "'", icd_code, "', ", sep="")
  } else if (nchar(icd_code) == 5) {
    con_icd_5 = paste(con_icd_5, "'", icd_code, "', ", sep="")
  } else{
    print("Unknown ICD Code Present")
  }
}

# Modify the end of the ICD code strings to format them as SQL lists. 
con_icd_3 = paste(str_replace(con_icd_3, ".{2}$", ""), ")", sep="")
con_icd_4 = paste(str_replace(con_icd_4, ".{2}$", ""), ")", sep="")
con_icd_5 = paste(str_replace(con_icd_5, ".{2}$", ""), ")", sep="")


# Query OMOP: define the correct query string (using
# string manipulations to sub in the ICD codes above), and query the server. 

# Format condition query by substituting in the ICD code strings from above

# If you want to limit the date range considered, you can add the following two 
# lines at the end of the condition_start_filter common table expression: 
# and vco.condition_start_date >= '2015-01-03' 
# and vco.condition_start_date < '2016-01-03'
condition_query = ("\
                    WITH condition_start_filter AS (
                      SELECT vco.*
                      FROM omop.v_condition_occurrence AS vco
                      LEFT join omop.person AS p
                        ON vco.person_id = p.person_id
                      WHERE condition_type_concept_id = 32840
                        AND (vco.condition_start_date - p.birth_datetime::date) >= 0
                    )    
                    SELECT DISTINCT person_id, 
                    CASE WHEN substring(translate(condition_source_value,'.',''),1,4) IN ('4373') THEN '4373' 
                      WHEN substring(condition_source_value,1,3) IN -0- THEN substring(condition_source_value,1,3)
                      WHEN substring(translate(condition_source_value,'.',''),1,4) IN -1- THEN substring(translate(condition_source_value,'.',''),1,4)
                      WHEN substring(translate(condition_source_value,'.',''),1,5) IN -2- THEN substring(translate(condition_source_value,'.',''),1,5)
                      ELSE NULL END AS condition_source_value,
                    condition_source_concept_vocabulary_id,
                    condition_start_date
                    FROM condition_start_filter
                    WHERE CASE
                      WHEN substring(translate(condition_source_value,'.',''),1,4) IN ('4373') THEN  1
                      WHEN substring(condition_source_value,1,3) IN -0- THEN 1
                      WHEN substring(translate(condition_source_value,'.',''),1,4) IN -1- THEN 1 
                      WHEN substring(translate(condition_source_value,'.',''),1,5) IN -2- THEN 1 
                      ELSE 0
                      END = 1;
                    ") %>% 
  str_replace_all("-0-", con_icd_3) %>%
  str_replace_all("-1-", con_icd_4) %>%
  str_replace_all("-2-", con_icd_5)

# Query the database 
person_condition_raw_query <- dbGetQuery(conn, condition_query)

# Transform queried data. The left join will add a small # of rows, because 
# some codes correspond to multiple diseases
charlson_conditions <- person_condition_raw_query %>%
  duplicate_condition_4373() %>% 
  remove_certain_icd10_codes() %>%  
  left_join(condition_df_long, 
            by = c("condition_source_value" = "icd"), 
            relationship = "many-to-many")

# Add the Charlson conditions to the inpatient_visits table. Remove conditions
# that occurred after the end date of the visit. 
cci_by_inpatient_visit <- inpatient_visits %>%
  left_join(charlson_conditions,
            by = c("person_id"),
            relationship = "many-to-many") %>%
  filter(visit_end_date - condition_start_date >= 0) %>%
  group_by(visit_occurrence_id, condition, charlson87_weight) %>%
  slice_head(n = 1) %>%
  group_by(visit_occurrence_id) %>%
  summarize(charlson_score = sum(charlson87_weight))

# Join CCI scores back to inpatient_visits. Replace NA with 0. 
cci_score <- inpatient_visits %>%
  left_join(cci_by_inpatient_visit, by=join_by(visit_occurrence_id)) %>%
  mutate(c_score = case_when(is.na(charlson_score) ~ 0,
                             charlson_score <= 3 ~ charlson_score,
                             charlson_score >= 4 ~ 5)) %>%
  select(visit_occurrence_id, c_score)


### 4: ER Visits in Past 180 Days ###
# While van Walraven et al. (2010), uses ER visits in the past 6 months, 
# 180 days is a more consistent unit to use. ER visits which took place on 
# the same day as the inpatient admission, but did not directly lead to that 
# admission, are counted towards the total. 


# All ER visits
er_visits <- visit_raw_query %>%
  filter(visit_concept_id %in% c(262, 9203)) %>%
  select(person_id, visit_start_date) %>%
  rename(er_visit_date = visit_start_date)

# Take each inpatient ER visit, and match it to every ER visit by the same patient,
# no matter the time frame. Then, exclude all ER visits which were not in the 180
# days prior to the inpatient visit start date. 
visits_prior_180_days <- inpatient_visits %>%
  left_join(er_visits, by=join_by(person_id), relationship="many-to-many") %>%
  mutate(date_diff = visit_start_date - er_visit_date) %>%
  filter(date_diff >= 0 & date_diff <= 180)

# Group by inpatient ER visit and count the number of rows, each of which 
# represents an ER visit by the same person in the prior 180 days. 
# If the visit is an inpatient + ER visit, subtract the count by 1, because it
# joined to itself once. 
visit_counts <- visits_prior_180_days %>%
  group_by(visit_occurrence_id) %>%
  summarize(prior_er_visits = n(), visit_concept_id = max(visit_concept_id)) %>%
  mutate(prior_er_visits = if_else(visit_concept_id == 262, prior_er_visits - 1, prior_er_visits)) %>%
  select(visit_occurrence_id, prior_er_visits)

# Join the counts back to inpatient_visits. Replace NA with 0. Calculate final 
# score. 
er_visits <- inpatient_visits %>%
  left_join(visit_counts, by=join_by(visit_occurrence_id)) %>%
  mutate(prior_er_visits = if_else(is.na(prior_er_visits), 0, prior_er_visits)) %>%
  mutate(e_score = case_when(prior_er_visits <= 4 ~ prior_er_visits,
                             TRUE ~ 4)) %>%
  select(visit_occurrence_id, e_score)


### Sum the four scores to get the combined LACE score

lace_score <- length_of_stay
lace_score$a_score <- acuity_of_admission$a_score
lace_score$c_score <- cci_score$c_score
lace_score$e_score <- er_visits$e_score
lace_score <- mutate(lace_score, total_score = l_score + a_score + c_score + e_score)
