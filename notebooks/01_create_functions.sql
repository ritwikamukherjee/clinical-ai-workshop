-- =============================================================
-- Workshop Module 3: Create UC Functions (Agent Bricks)
-- Run each block in the SQL editor or a notebook %sql cell
-- Target schema: hls_amer_catalog.clinical_workshop
-- =============================================================

USE CATALOG hls_amer_catalog;
USE SCHEMA clinical_workshop;

-- -------------------------------------------------------------
-- FUNCTION 1: get_latest_admission
-- Returns the most recent hospital admission for a patient
-- Used by: Supervisor Agent to anchor clinical timelines
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION hls_amer_catalog.clinical_workshop.get_latest_admission(
  patient_id INT COMMENT 'Unique patient identifier (SUBJECT_ID)'
)
RETURNS TABLE (
  SUBJECT_ID INT,
  HADM_ID    INT,
  ADMITTIME  DATE,
  DISCHTIME  DATE,
  ADMISSION_TYPE STRING,
  INSURANCE  STRING,
  DIAGNOSIS  STRING
)
COMMENT 'Returns the most recent admission record for a given patient. Use this to anchor clinical timelines before querying labs or notes.'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    ADMITTIME,
    DISCHTIME,
    ADMISSION_TYPE,
    INSURANCE,
    DIAGNOSIS
  FROM hls_amer_catalog.clinical_workshop.admissions
  WHERE SUBJECT_ID = patient_id
  ORDER BY ADMITTIME DESC
  LIMIT 1;

-- Test it
SELECT * FROM hls_amer_catalog.clinical_workshop.get_latest_admission(22);


-- -------------------------------------------------------------
-- FUNCTION 2: get_abnormal_labs
-- Returns all abnormal lab results for a given hospital admission
-- Used by: Supervisor Agent when asked about lab findings
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION hls_amer_catalog.clinical_workshop.get_abnormal_labs(
  admission_id INT COMMENT 'Hospital admission identifier (HADM_ID)'
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
COMMENT 'Returns abnormal lab results for a specific hospital admission. Returns subject ID, admission ID, lab item ID, chart time, value, unit, and abnormal flag.'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    ITEMID,
    CHARTTIME,
    VALUE,
    VALUEUOM,
    FLAG
  FROM hls_amer_catalog.clinical_workshop.lab_events
  WHERE HADM_ID = admission_id
    AND FLAG = 'abnormal';

-- Test it (use a real HADM_ID from your admissions table)
-- SELECT * FROM hls_amer_catalog.clinical_workshop.get_abnormal_labs(135236) LIMIT 10;


-- -------------------------------------------------------------
-- FUNCTION 3: get_lab_type
-- Resolves a lab item ID to its human-readable label and category
-- Used by: Supervisor Agent to interpret lab result IDs
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION hls_amer_catalog.clinical_workshop.get_lab_type(
  abnormal_lab_item_id INT COMMENT 'Lab item identifier (ITEMID) from lab_events'
)
RETURNS TABLE (
  ROW_ID     INT,
  ITEMID     INT,
  LABEL      STRING,
  FLUID      STRING,
  CATEGORY   STRING,
  LOINC_CODE STRING
)
COMMENT 'Resolves a lab item ID to its label, fluid type, category, and LOINC code. Use after get_abnormal_labs to understand what each lab item represents. Example result: ITEMID=51279, LABEL=Red Blood Cells, FLUID=Blood, CATEGORY=Hematology'
RETURN
  SELECT *
  FROM hls_amer_catalog.clinical_workshop.d_labitems
  WHERE ITEMID = abnormal_lab_item_id;

-- Test it
-- SELECT * FROM hls_amer_catalog.clinical_workshop.get_lab_type(51279);


-- -------------------------------------------------------------
-- FUNCTION 4: get_clinical_notes
-- Returns clinical notes for a specific admission on a given date
-- Used by: Supervisor Agent for specific patient-admission lookups
-- NOTE: Use Knowledge Assistant (vector search) for semantic queries
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION hls_amer_catalog.clinical_workshop.get_clinical_notes(
  admission_id INT  COMMENT 'Hospital admission identifier (HADM_ID)',
  chart_date   DATE COMMENT 'Date of the clinical note (CHARTDATE)'
)
RETURNS TABLE (
  SUBJECT_ID INT,
  HADM_ID    INT,
  TEXT       STRING,
  CHARTDATE  DATE,
  CHARTTIME  TIMESTAMP
)
COMMENT 'Returns clinical notes for a specific patient admission on a given date. Use this when you need notes for a known HADM_ID and date. Use the Knowledge Assistant instead for semantic/topic-based retrieval.'
RETURN
  SELECT
    SUBJECT_ID,
    HADM_ID,
    TEXT,
    CHARTDATE,
    CHARTTIME
  FROM hls_amer_catalog.clinical_workshop.note_events_20000
  WHERE HADM_ID    = admission_id
    AND CHARTDATE  = chart_date;

-- Test it
-- SELECT * FROM hls_amer_catalog.clinical_workshop.get_clinical_notes(175562, '2143-01-18');


-- -------------------------------------------------------------
-- FUNCTION 5: clinical_notes_vector_search
-- Semantic search over note embeddings via vector index
-- Used by: Knowledge Assistant as its retrieval backbone
-- IMPORTANT: Create the vector index FIRST (Module 2 in the UI)
--            then update the index name below
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION hls_amer_catalog.clinical_workshop.clinical_notes_vector_search(
  query STRING COMMENT 'Natural language question or clinical topic to search for in notes'
)
RETURNS TABLE (
  page_content STRING,
  metadata     MAP<STRING, STRING>
)
COMMENT 'Performs semantic similarity search over MIMIC clinical notes. Returns the most relevant note text and metadata (doc_uri, HADM_ID). Use this when you need to find notes relevant to a clinical topic or question rather than a specific patient.'
RETURN
  SELECT
    TEXT        AS page_content,
    map(
      'doc_uri', ROW_ID,
      'HADM_ID', HADM_ID
    )           AS metadata
  FROM vector_search(
    -- UPDATE THIS to match your vector index name after creating it in the UI
    index   => 'hls_amer_catalog.clinical_workshop.note_events_vs_index',
    query   => query,
    num_results => 5
  );

-- Test after vector index is created:
-- SELECT * FROM hls_amer_catalog.clinical_workshop.clinical_notes_vector_search('patient with respiratory failure on ventilator');
