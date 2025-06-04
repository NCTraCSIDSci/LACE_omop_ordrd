-- LACE Hospital Readmission Index

-- This calculation of the LACE Score has been 
-- designed to work on the OMOP CDM v5.3 and developed in the 
-- University of North Carolina at Chapel Hill de-identified
-- OMOP Research Data Repository, ORDR(D). Please see the 
-- README in the repo with important notes, clarifications
-- and assumptions. 

-- Author: Josh Fuchs

-- Copyright 2025, The University of North Carolina at Chapel Hill. 
-- Permission is granted to use in accordance with the MIT license. 
-- The code is licensed under the open-source MIT license. 

----------------------------------------------
-- Initial queries. These tables will be used for calculations of each
-- individual component of LACE. 
-- visit_concept_id 262 corresponds to an ER visit with subsequent inpatient stay
-- visit_concept_id 9201 corresponds to an inpatient visit alone
-- visit_concept_id 9203 corresponds to an ER visit alone
-----------------------------------------------

-- All visit types
WITH visit_query AS (
	SELECT visit_occurrence_id, person_id, visit_concept_id, 
		visit_start_date, visit_end_date
	FROM omop.visit_occurrence
	WHERE visit_concept_id in (262, 9201, 9203)
),
	
-- Inpatient Only
-- Add length of stay
inpatient_visits AS (
	SELECT *,
		visit_end_date - visit_start_date AS los
	FROM visit_query
	WHERE visit_concept_id IN (262,9201)
),

----------------	
-- Length of Stay
-- A score is assigned based on the
-- length of the inpatient stay. 
----------------
length_table AS (
	SELECT *,
	CASE WHEN los < 1 THEN 0
		WHEN los = 1 THEN 1
		WHEN los = 2 THEN 2
		WHEN los = 3 THEN 3
		WHEN (los >= 4 AND los <= 6) THEN 4
		WHEN (los >= 7 AND los <= 13) THEN 5
		WHEN los >= 14 THEN 7
		ELSE -99 END AS l_score
	FROM inpatient_visits
),

-------------
-- Acuity of Admission 
-- Acuity of admission is inferred from the type of visit. An inpatient visit 
-- alone, visit_concept_id = 9201, is considered a non-emergent/non-acute admission. 
-- An ER visit followed by an inpatient visit, visit_concept_id = 262, is 
-- considered an emergent/acute admission. For a more detained disucssion, consult the README. 
-----------------

acuity_table AS (
	SELECT *,
	CASE WHEN visit_concept_id = 262 THEN 3
		WHEN visit_concept_id = 9201 THEN 0
		ELSE -99 END AS a_score
	FROM inpatient_visits
),

-----------------	
-- Charlson comorbidity index 
-- Calculates the CCI for each inpatient visit to 
-- convert to the C component of LACE. See the README 
-- for details about this calculation.
-----------------
condition_start_filter AS (
	SELECT vco.*
	FROM omop.v_condition_occurrence AS vco
	LEFT JOIN omop.person AS p
		ON vco.person_id = p.person_id
	WHERE condition_type_concept_id = 32840 --EHR problem list
	-- only keep conditions with start date on or after birth date
		AND (vco.condition_start_date - p.birth_datetime::date) >= 0 
),

-- Now, select use ICD-9 and ICD-10 codes to group conditions into
-- the categories set by Quan et al (2005). We assign these categories
-- as 1 to 17 and any diagnoses not in a category as 0. 

conditions AS (
	SELECT DISTINCT
	person_id,
	condition_start_date,
	condition_end_date,
	condition_source_value,
	condition_source_concept_vocabulary_id,

--myocardial infarction--
	CASE WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('410','412') THEN 1
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('I21','I22') THEN 1
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) = ('I252') THEN 1 

--congestive heart failure--			 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('39891','40201','40211',
																		  '40291','40401','40403',
																		  '40411','40413','40491',
																		  '40493') THEN 2
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('428')  THEN 2 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('I099','I110','I130','I132',
																		  'I255','I420','I425','I426',
																		  'I427','I428','I429','P290',
																		  '4254','4255','4256','4257',
																		  '4258','4259')  THEN 2
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('I43','I50') THEN 2
			 
--peripheral vascular--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('0930','4373','4431','4432',
																		  '4433','4434','4435','4436',
																		  '4437','4438','4439','4471',
																		  '5571','5579','V434') THEN 3
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('440','441') THEN 3 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('I731','I738','I739','I771',
																		  'I790','I792','K551','K558',
																		  'K559','Z958','Z959') THEN 3
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('I70','I71') THEN 3
			 
--cerebrovascular--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('430','431','432','433',
																		  '434','435','436','437',
																		  '438') THEN 4
		 WHEN TRANSLATE(condition_source_value,'.','')=('36234') THEN 4  
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('G45','G46','I60','I61',
																		  'I62','I63','I64','I65',
																		  'I66','I67','I68','I69') THEN 4
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) = ('H340') THEN 4 
			 
--dementia--	
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('29410','29411') THEN 5
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('290') THEN 5  
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('F051','G311','3312') THEN 5
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('F00','F01','F02','F03','G30') THEN 5

--chronic pulmonary--
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('490','491','492','493','494',
																		 '495','496','500','501','502',
																		 '503','504','505') THEN 6
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('4168','4169','5064','5081',
																		 '5088') THEN 6 
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('J40','J41','J42','J43','J44',
																		 'J45','J46','J47','J60','J61',
																		 'J62','J63','J64','J65','J66',
																		 'J67') THEN 6
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('I278','I279','J684','J701',
																		 'J703') THEN 6
			
--connective tissue--	
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('4465','7100','7101','7102',
																		  '7103','7104','7140','7141',
																		  '7142','7148') THEN 7
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('725') THEN 7  
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('M315','M351','M353','M360') THEN 7 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('M05','M32','M33','M34','M06') THEN 7
			 
--peptic ulcer--	 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('531','532','533','534') THEN 8 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('K25','K26','K27','K28') THEN 8
			 
--mild liver--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('07022','07023','07032',
																		  '07033','07044','07054') THEN 9
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('570','571') THEN 9 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('K700','K701','K702','K703',
																		  'K709','K717','K713','K714',
																		  'K715','K760','K762','K763',
																		  'K764','K768','K769','Z944',
																		  '0706','0709','5733','5734',
																		  '5738','5739','V427') THEN 9
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('B18','K73','K74') THEN 9
				 
--diabetes without complications--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('2500','2501','2502','2503',
																		  '2508','2509') THEN 10
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('E100','E101','E106','E108',
																		  'E109','E110','E111','E116',
																		  'E118','E119','E120','E121',
																		  'E126','E128','E129','E130',
																		  'E131','E136','E138','E139',
																		  'E140','E141','E146','E148',
																		  'E149') THEN 10
		
--diabetes with complications--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('2504','2505','2506','2507') THEN 11 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('E102','E103','E104','E105',
																		  'E107','E112','E113','E114',
																		  'E115','E117','E122','E123',
																		  'E124','E125','E127','E132',
																		  'E133','E134','E135','E137',
																		  'E142','E143','E144','E145',
																		  'E147') THEN 11
						 
--paralysis--
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('3341','3440','3441','3442',
																		  '3443','3444','3445','3446',
																		  '3449') THEN 12
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('342','343') THEN 12 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('G041','G114','G801','G802',
																		  'G830','G831','G832','G833',
																		  'G834','G839') THEN 12
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('G81','G82') THEN 12
			 
--renal disease-- 
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('40301','40311','40391','40402',
																		  '40403','40412','40413','40492',
																		  '40493') THEN 13
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('582','585','586','V56') THEN 13
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('N18','N19') THEN 13
		 WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('N052','N053','N054','N055','N056',
																		  'N057','N250','I120','I131','N032',
																		  'N033','N034','N035','N036','N037',
																		  'Z490','Z491','Z492','Z940','Z992',
																		  '5830','5831','5832','5834','5836',
																		  '5837','5880','V420','V451') THEN 13
			 
--cancer--	 
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('140','141','142','143','144','145',
																		 '146','147','148','149','150','151',
																		 '152','153','154','155','156','157',
																		 '158','159','160','161','162','163',
																		 '164','165','170','171','172','174',
																		 '175','176','179','180','181','182',
																		 '183','184','185','186','187','188',
																		 '189','190','191','192','193','194',
																		 '195','200','201','202','203','204',
																		 '205','206','207','208') THEN 14
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('2386') THEN 14 
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('C00','C01','C02','C03','C04','C05',
																		 'C06','C07','C08','C09','C10','C11',
																		 'C12','C13','C14','C15','C16','C17',
																		 'C18','C19','C20','C21','C22','C23',
																		 'C24','C25','C26','C30','C31','C32',
																		 'C33','C34','C37','C38','C39','C40',
																		 'C41','C43','C45','C46','C47','C48',
																		 'C49','C50','C51','C52','C53','C54',
																		 'C55','C56','C57','C58','C60','C61',
																		 'C62','C63','C64','C65','C66','C67',
																		 'C68','C69','C70','C71','C72','C73',
																		 'C74','C75','C76','C81','C82','C83',
																		 'C84','C85','C88','C90','C91','C92',
																		 'C93','C94','C95','C96','C97') THEN 14
			
--moderate or severe liver disease--		
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('4560','4561','4562','5722','5723',
																		 '5724','5728') THEN 15 
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('K704','K711','K721','K729','K765',
																		 'K766','K767','I850','I859','I864',
																		 'I982') THEN 15
			
--metastatic cancer--	
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('196','197','198','199') THEN 16 
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('C77','C78','C79','C80') THEN 16
			
 --HIV/aids--	
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('042','043','044') THEN 17
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,3) IN ('B20','B21','B22','B24') THEN 17

		ELSE 0 END AS cc_group
	FROM condition_start_filter
),

-- Now add in rows for 4 cases when the conditons need to be double counted across
-- multiple conditions. 
conditions_expanded AS (
	SELECT *
	FROM conditions
	UNION ALL
	SELECT person_id,
	condition_start_date,
	condition_end_date,
	condition_source_value,
	condition_source_concept_vocabulary_id,
	CASE WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('40403','40413','40493') THEN 13
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('4373') THEN 4
		ELSE 0 END AS cc_group
	FROM conditions
	WHERE CASE
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,5) IN ('40403','40413','40493') THEN 1
		WHEN SUBSTRING(TRANSLATE(condition_source_value,'.',''),1,4) IN ('4373') THEN 1
		ELSE 0 END = 1
),

-- Remove rows where the following condition corresponds
-- to ICD10 codes: V43.4, V42.76, V42.0, V45.1, V56.x
-- in Quan 2005 these are ICD-9 codes
conditions_expanded_filtered AS (
	SELECT *
	FROM conditions_expanded
	WHERE NOT ((TRANSLATE(condition_source_value,'.','') LIKE 'V434%' OR
			  TRANSLATE(condition_source_value,'.','') LIKE 'V4276%' OR
			  TRANSLATE(condition_source_value,'.','') LIKE 'V420%' OR
			  TRANSLATE(condition_source_value,'.','') LIKE 'V451%' OR
			  TRANSLATE(condition_source_value,'.','') LIKE 'V56%')
		  AND condition_source_concept_vocabulary_id = 'ICD10CM')
),

-- Remove those cc_groups that are 0 (not a commorbid condition)
no_duplicate_conditions AS (
	SELECT DISTINCT person_id, condition_start_date, cc_group 
	FROM conditions_expanded_filtered
	WHERE cc_group > 0
),

-- Add in the weights for each cc_group
-- using the original weights from Charlson et al (1987)
weights AS (
	SELECT person_id,
	condition_start_date,
	cc_group,
	--myocardial infarction --
	CASE WHEN cc_group = 1 THEN 1

	--congestive heart failure--			 
		WHEN cc_group = 2 THEN 1

	--peripheral vascular--
		WHEN cc_group = 3 THEN 1

	--cerebrovascular--
		WHEN cc_group = 4 THEN 1

	--dementia--	
		WHEN cc_group = 5 THEN 1

	--chronic pulmonary--
		WHEN cc_group = 6 THEN 1

	--connective tissue--	
		WHEN cc_group = 7 THEN 1

	--peptic ulcer--	 
		WHEN cc_group = 8 THEN 1

	--mild liver--
		WHEN cc_group = 9 THEN 1

	--diabetes without complications--
		WHEN cc_group = 10 THEN 1

	--diabetes with complications--
		WHEN cc_group = 11 THEN 2

	--paralysis--
		WHEN cc_group = 12 THEN 2

	--renal disease-- 
		WHEN cc_group = 13 THEN 2

	--cancer--	 
		WHEN cc_group = 14 THEN 2

	--moderate or severe liver disease--		
		WHEN cc_group = 15 THEN 3

	--metastatic cancer--	
		WHEN cc_group = 16 THEN 6

	 --HIV/aids--	
		WHEN cc_group = 17 THEN 6

		ELSE 0 END AS cc_weights

	FROM no_duplicate_conditions
),

-- Add the Charlson conditions to the inpatient_visits table. Remove conditions
-- that occurred after the end date of the visit. 
charlson_conditions AS (
    SELECT 
        iv.visit_occurrence_id,
        w.cc_group,
        w.cc_weights,
        ROW_NUMBER() OVER (PARTITION BY iv.visit_occurrence_id, w.cc_group ORDER BY w.condition_start_date DESC) AS rn
    FROM 
        inpatient_visits AS iv
    JOIN 
        weights AS w
    ON 
        iv.person_id = w.person_id
    WHERE 
        iv.visit_end_date >= w.condition_start_date
),

cci_by_inpatient_visit AS (
	SELECT 
		visit_occurrence_id,
		SUM(cc_weights) AS charlson_score
	FROM 
		charlson_conditions
	WHERE 
		rn = 1
	GROUP BY 
		visit_occurrence_id
),

cci_table AS (
	SELECT 
		iv.visit_occurrence_id,
		CASE 
			WHEN ccibiv.charlson_score IS NULL THEN 0
			WHEN ccibiv.charlson_score <= 3 THEN ccibiv.charlson_score
			WHEN ccibiv.charlson_score >= 4 THEN 5
		END AS c_score
	FROM 
		inpatient_visits AS iv
	LEFT JOIN 
		cci_by_inpatient_visit AS ccibiv
	ON 
		iv.visit_occurrence_id = ccibiv.visit_occurrence_id
),

-----------
-- ER Visits in Past 180 Days 
-- While van Walraven et al. (2010), uses ER visits in the past 
-- 6 months, 180 days is a more consistent unit to use. ER visits 
-- which took place on the same day as the inpatient admission, 
-- but did not directly lead to that admission, are counted towards the total. 
-----------

-- All ER visits
er_visits AS (
	SELECT visit_occurrence_id,
			person_id,
			visit_concept_id,
			visit_start_date AS er_visit_date
	FROM visit_query
	WHERE visit_concept_id IN (262,9203)
),

-- Take each inpatient ER visit, and match it to every ER visit by the same patient,
-- no matter the time frame. Then, exclude all ER visits which were not in the 180
-- days prior to the inpatient visit start date. 

-- Then group by inpatient ER visit and count the number of rows, each of which 
-- represents an ER visit by the same person in the prior 180 days. 
-- If the visit is an inpatient + ER visit, subtract the count by 1, because it
-- joined to itself once. 
visit_counts AS (
    SELECT 
        visit_occurrence_id,
        CASE 
            WHEN visit_concept_id = 262 THEN COUNT(*) - 1
            ELSE COUNT(*)
        END AS prior_er_visits
    FROM 
        (SELECT 
            iv.person_id,
            iv.visit_occurrence_id,
            iv.visit_start_date,
            ev.er_visit_date,
            (iv.visit_start_date - ev.er_visit_date) AS date_diff,
            iv.visit_concept_id
        FROM 
            inpatient_visits iv
        JOIN 
            er_visits ev
        ON 
            iv.person_id = ev.person_id
        WHERE 
            (iv.visit_start_date - ev.er_visit_date) >= 0 
            AND (iv.visit_start_date - ev.er_visit_date) <= 180) AS visits_prior_180_days
    GROUP BY 
        visit_occurrence_id, visit_concept_id
),

er_table AS (
	SELECT 
		iv.visit_occurrence_id,
		COALESCE(vc.prior_er_visits, 0) AS prior_er_visits,
		CASE 
			WHEN COALESCE(vc.prior_er_visits, 0) <= 4 THEN COALESCE(vc.prior_er_visits, 0)
			ELSE 4
		END AS e_score
	FROM 
		inpatient_visits iv
	LEFT JOIN 
		visit_counts vc
	ON 
		iv.visit_occurrence_id = vc.visit_occurrence_id
)

-- Combine the intermediate tables
-- and sum to calculate the LACE score
SELECT
	lt.visit_occurrence_id,
	lt.person_id,
	lt.visit_concept_id,
	lt.visit_start_date,
	lt.l_score,
	act.a_score,
	ct.c_score,
	et.e_score,
	lt.l_score + act.a_score + ct.c_score + et.e_score AS lace_score	
FROM length_table AS lt
	LEFT JOIN acuity_table AS act
		ON lt.visit_occurrence_id = act.visit_occurrence_id
	LEFT JOIN cci_table AS ct
		ON lt.visit_occurrence_id = ct.visit_occurrence_id
	LEFT JOIN er_table AS et
		ON lt.visit_occurrence_id = et.visit_occurrence_id


	
	

