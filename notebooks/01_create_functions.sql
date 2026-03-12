-- =============================================================
-- Workshop Module 4: Create UC Functions (Agent Bricks)
-- Run each block in the SQL editor or a %sql notebook cell
--
-- STEP 1: Update the three DECLARE values below to match
--         your catalog, schema, and vector search index name.
-- STEP 2: Run all statements in order.
-- =============================================================

-- >>> UPDATE THESE THREE VALUES FOR YOUR ENVIRONMENT <<<
DECLARE OR REPLACE catalog_name  = 'hls_amer_catalog';
DECLARE OR REPLACE schema_name   = 'clinical_workshop';
DECLARE OR REPLACE vs_index_name = 'note_events_vs_index';

-- Apply context
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;
EXECUTE IMMEDIATE 'USE SCHEMA '  || schema_name;


-- -------------------------------------------------------------
-- FUNCTION 1: get_latest_admission
-- Returns the most recent hospital admission for a patient
-- Used by: Supervisor Agent to anchor clinical timelines
-- -------------------------------------------------------------
EXECUTE IMMEDIATE
'CREATE OR REPLACE FUNCTION ' || catalog_name || '.' || schema_name || '.get_latest_admission(
  patient_id INT COMMENT \'Unique patient identifier (SUBJECT_ID)\'
)
RETURNS TABLE (
  SUBJECT_ID     INT,
  HADM_ID        INT,
  ADMITTIME      DATE,
  DISCHTIME      DATE,
  ADMISSION_TYPE STRING,
  INSURANCE      STRING,
  DIAGNOSIS      STRING
)
COMMENT \'Returns the most recent admission record for a given patient. Use this to anchor clinical timelines before querying labs or notes.\'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    ADMITTIME,
    DISCHTIME,
    ADMISSION_TYPE,
    INSURANCE,
    DIAGNOSIS
  FROM ' || catalog_name || '.' || schema_name || '.admissions
  WHERE SUBJECT_ID = patient_id
  ORDER BY ADMITTIME DESC
  LIMIT 1';

-- Test it
EXECUTE IMMEDIATE
'SELECT * FROM ' || catalog_name || '.' || schema_name || '.get_latest_admission(22)';


-- -------------------------------------------------------------
-- FUNCTION 2: get_abnormal_labs
-- Returns all abnormal lab results for a given hospital admission
-- Used by: Supervisor Agent when asked about lab findings
-- -------------------------------------------------------------
EXECUTE IMMEDIATE
'CREATE OR REPLACE FUNCTION ' || catalog_name || '.' || schema_name || '.get_abnormal_labs(
  admission_id INT COMMENT \'Hospital admission identifier (HADM_ID)\'
)
RETURNS TABLE (
  SUBJECT_ID INT,
  HADM_ID    INT,
  ITEMID     INT,
  CHARTTIME  TIMESTAMP,
  VALUE      STRING,
  VALUEUOM   STRING,
  FLAG       STRING
)
COMMENT \'Returns abnormal lab results for a specific hospital admission. Returns subject ID, admission ID, lab item ID, chart time, value, unit, and abnormal flag.\'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    ITEMID,
    CHARTTIME,
    VALUE,
    VALUEUOM,
    FLAG
  FROM ' || catalog_name || '.' || schema_name || '.lab_events
  WHERE HADM_ID = admission_id
    AND FLAG = \'abnormal\'';

-- Test it (replace with a real HADM_ID from your admissions table)
-- EXECUTE IMMEDIATE 'SELECT * FROM ' || catalog_name || '.' || schema_name || '.get_abnormal_labs(135236) LIMIT 10';


-- -------------------------------------------------------------
-- FUNCTION 3: get_lab_type
-- Resolves a lab item ID to its human-readable label and category
-- Used by: Supervisor Agent to interpret lab result IDs
-- -------------------------------------------------------------
EXECUTE IMMEDIATE
'CREATE OR REPLACE FUNCTION ' || catalog_name || '.' || schema_name || '.get_lab_type(
  abnormal_lab_item_id INT COMMENT \'Lab item identifier (ITEMID) from lab_events\'
)
RETURNS TABLE (
  ROW_ID     INT,
  ITEMID     INT,
  LABEL      STRING,
  FLUID      STRING,
  CATEGORY   STRING,
  LOINC_CODE STRING
)
COMMENT \'Resolves a lab item ID to its label, fluid type, category, and LOINC code. Use after get_abnormal_labs to understand what each lab item represents. Example: ITEMID=51279 -> Red Blood Cells, Blood, Hematology\'
RETURN
  SELECT *
  FROM ' || catalog_name || '.' || schema_name || '.d_labitems
  WHERE ITEMID = abnormal_lab_item_id';

-- Test it
-- EXECUTE IMMEDIATE 'SELECT * FROM ' || catalog_name || '.' || schema_name || '.get_lab_type(51279)';


-- -------------------------------------------------------------
-- FUNCTION 4: get_clinical_notes
-- Returns clinical notes for a specific admission on a given date
-- Used by: Supervisor Agent for known patient-admission lookups
-- NOTE: Use the Knowledge Assistant for semantic/topic queries
-- -------------------------------------------------------------
EXECUTE IMMEDIATE
'CREATE OR REPLACE FUNCTION ' || catalog_name || '.' || schema_name || '.get_clinical_notes(
  admission_id INT  COMMENT \'Hospital admission identifier (HADM_ID)\',
  chart_date   DATE COMMENT \'Date of the clinical note (CHARTDATE)\'
)
RETURNS TABLE (
  SUBJECT_ID INT,
  HADM_ID    INT,
  TEXT       STRING,
  CHARTDATE  DATE,
  CHARTTIME  TIMESTAMP
)
COMMENT \'Returns clinical notes for a specific patient admission on a given date. Use when you need notes for a known HADM_ID and date. Use the Knowledge Assistant for semantic or topic-based retrieval instead.\'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    TEXT,
    CHARTDATE,
    CHARTTIME
  FROM ' || catalog_name || '.' || schema_name || '.note_events_20000
  WHERE HADM_ID   = admission_id
    AND CHARTDATE = chart_date';

-- Test it
-- EXECUTE IMMEDIATE 'SELECT * FROM ' || catalog_name || '.' || schema_name || '.get_clinical_notes(175562, \'2143-01-18\')';


-- -------------------------------------------------------------
-- FUNCTION 5: clinical_notes_vector_search
-- Semantic search over note embeddings via vector index
-- PREREQUISITE: Complete Module 1 (Vector Search Index) first
-- -------------------------------------------------------------
EXECUTE IMMEDIATE
'CREATE OR REPLACE FUNCTION ' || catalog_name || '.' || schema_name || '.clinical_notes_vector_search(
  query STRING COMMENT \'Natural language question or clinical topic to search for in notes\'
)
RETURNS TABLE (
  page_content STRING,
  metadata     MAP<STRING, STRING>
)
COMMENT \'Performs semantic similarity search over MIMIC clinical notes. Returns the most relevant note text and metadata (doc_uri, HADM_ID). Use when you need notes relevant to a clinical topic rather than a specific patient.\'
RETURN
  SELECT
    TEXT     AS page_content,
    map(
      \'doc_uri\', ROW_ID,
      \'HADM_ID\', HADM_ID
    )        AS metadata
  FROM vector_search(
    index       => \'' || catalog_name || '.' || schema_name || '.' || vs_index_name || '\',
    query       => query,
    num_results => 5
  )';

-- Test after completing Module 1 (Vector Search Index):
-- EXECUTE IMMEDIATE 'SELECT * FROM ' || catalog_name || '.' || schema_name || '.clinical_notes_vector_search(\'patient on ventilator with respiratory failure\')';
