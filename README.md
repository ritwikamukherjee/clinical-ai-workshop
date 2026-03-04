# Clinical AI Assistant Workshop
**Databricks | HLS Payer Series | 2-3 hour session**

A hands-on workshop for new Databricks users that demonstrates building a clinical AI assistant using:
- **KIE** — Extract structured fields from clinical PDFs using `ai_extract()`
- **Knowledge Assistant** — Semantic search over 20,000 clinical notes via Vector Search
- **UC Functions** — SQL-defined agent tools (get labs, admissions, notes)
- **Supervisor Agent** — Orchestrates Genie (managed MCP) + UC functions + Knowledge Assistant

All data is synthetic (MIMIC-III de-identified, cohort-scoped to 1,590 admissions).

---

## Repository Structure

```
clinical_workshop/
├── parquet/                     # Source data — load once via setup notebook
│   ├── note_events_20000/       # 20,000 clinical notes (KA corpus)
│   ├── admissions/              # 1,590 hospital admissions
│   ├── patients/                # 1,325 patients
│   ├── lab_events/              # 883,423 lab results (filtered to cohort)
│   ├── d_labitems/              # 753 lab item definitions (lookup)
│   ├── diagnoses_icd/           # 15,566 ICD-9 diagnosis codes per admission
│   └── d_icd_diagnoses/         # 14,567 ICD-9 code descriptions (lookup)
├── pdfs/                        # 30 clinical note PDFs for KIE module
├── notebooks/
│   ├── 00_setup.py              # Run once — creates schema, loads all tables
│   └── 01_create_functions.sql  # Creates 5 UC functions (agent bricks)
└── README.md                    # This file
```

---

## Prerequisites

- Databricks workspace with Unity Catalog enabled
- A catalog you have `CREATE SCHEMA` permission on (default: `hls_amer_catalog`)
- A running SQL Warehouse or Serverless compute
- Access to `databricks-gte-large-en` embedding model endpoint

---

## Step 0 — Deploy Data (Instructor / Pre-workshop)

### Option A: CLI (recommended)
```bash
# Authenticate to your workspace
databricks auth login https://<your-workspace>.cloud.databricks.com --profile=workshop

# Create schema and volumes
databricks --profile=workshop sql execute \
  "CREATE SCHEMA IF NOT EXISTS hls_amer_catalog.clinical_workshop"
databricks --profile=workshop sql execute \
  "CREATE VOLUME IF NOT EXISTS hls_amer_catalog.clinical_workshop.raw_data"
databricks --profile=workshop sql execute \
  "CREATE VOLUME IF NOT EXISTS hls_amer_catalog.clinical_workshop.clinical_pdfs"

# Upload data files
databricks --profile=workshop fs cp -r parquet/ \
  dbfs:/Volumes/hls_amer_catalog/clinical_workshop/raw_data/parquet/

# Upload PDFs
databricks --profile=workshop fs cp -r pdfs/ \
  dbfs:/Volumes/hls_amer_catalog/clinical_workshop/clinical_pdfs/
```

### Option B: Workspace UI
1. In Catalog Explorer, create schema `hls_amer_catalog.clinical_workshop`
2. Create two volumes: `raw_data` and `clinical_pdfs`
3. Drag-and-drop the `parquet/` folder into `raw_data`
4. Drag-and-drop all PDFs into `clinical_pdfs`

### Run the setup notebook
Import `notebooks/00_setup.py` into your workspace and run it.
This loads all Parquet files into managed Delta tables (~5 min).

---

## Module 1 — KIE: Extract from PDFs (~20 min)

**Goal:** Show how `ai_extract()` turns unstructured clinical PDFs into structured data.

### Step 1.1 — Browse the PDFs
Catalog Explorer → `hls_amer_catalog` → `clinical_workshop` → `clinical_pdfs` volume → click any PDF

### Step 1.2 — Run extraction with ai_extract()
Open a SQL notebook and run:

```sql
-- Extract structured fields from raw clinical note text
SELECT
  SUBJECT_ID,
  HADM_ID,
  CHARTDATE,
  ai_extract(TEXT, NAMED_STRUCT(
    'diagnosis',       'string: Primary and secondary diagnoses documented in this note',
    'medications',     'string: Medications administered or ordered',
    'procedures',      'string: Clinical procedures performed',
    'follow_up_plan',  'string: Planned next steps or discharge instructions',
    'patient_status',  'string: Overall patient condition at time of note'
  )) AS extracted
FROM hls_amer_catalog.clinical_workshop.note_events_20000
LIMIT 10;
```

### Step 1.3 — Store extracted results as a Delta table
```sql
CREATE OR REPLACE TABLE hls_amer_catalog.clinical_workshop.note_events_extracted AS
SELECT
  SUBJECT_ID,
  HADM_ID,
  CHARTDATE,
  TEXT,
  ai_extract(TEXT, NAMED_STRUCT(
    'diagnosis',       'string: Primary diagnosis',
    'medications',     'string: Medications mentioned',
    'procedures',      'string: Procedures performed',
    'follow_up_plan',  'string: Follow-up plan',
    'patient_status',  'string: Patient status'
  )) AS extracted
FROM hls_amer_catalog.clinical_workshop.note_events_20000
LIMIT 100;
```

---

## Module 2 — Knowledge Base: Vector Search (~15 min)

**Goal:** Create a vector index on `note_events_20000` to power the Knowledge Assistant.

### Step 2.1 — Create a Vector Search endpoint (if not already exists)
Mosaic AI → Vector Search → Create endpoint → name: `workshop-vs-endpoint`

### Step 2.2 — Create the Vector Index (UI)
1. Go to **Catalog Explorer** → `hls_amer_catalog.clinical_workshop.note_events_20000`
2. Click **Create** → **Vector Search Index**
3. Configure:
   - **Index name**: `note_events_vs_index`
   - **Primary key**: `ROW_ID`
   - **Text column to embed**: `TEXT`
   - **Embedding model**: `databricks-gte-large-en`
   - **Sync**: Triggered
4. Click **Create** — indexing takes ~5-10 min for 20K rows

### Step 2.3 — Create the Knowledge Assistant
1. Mosaic AI → **Agents** → **New Agent**
2. Select type: **Knowledge Assistant**
3. Attach the vector index: `note_events_vs_index`
4. Set system prompt:
   ```
   This agent provides answers from MIMIC-III clinical notes. It can retrieve
   notes most relevant to the input query. Use it for population-level questions
   about diagnoses, treatments, and clinical patterns. Be concise.
   ```
5. Test with: `What are common causes of low oxygen saturation in ICU patients?`

---

## Module 3 — UC Functions: Agent Bricks (~20 min)

**Goal:** Create 5 SQL functions that the Supervisor Agent will call as tools.

Open a SQL notebook and run `notebooks/01_create_functions.sql` **block by block**.

| Function | What it does |
|---|---|
| `get_latest_admission(patient_id)` | Most recent admission for a patient |
| `get_abnormal_labs(admission_id)` | Abnormal lab results for an admission |
| `get_lab_type(item_id)` | Resolves lab item ID to label/category |
| `get_clinical_notes(admission_id, date)` | Notes for a specific admission + date |
| `clinical_notes_vector_search(query)` | Semantic search over note embeddings |

**Test each function after creation:**
```sql
-- Test 1: get_latest_admission
SELECT * FROM hls_amer_catalog.clinical_workshop.get_latest_admission(22);

-- Test 2: get_abnormal_labs (use HADM_ID from test 1 result)
SELECT * FROM hls_amer_catalog.clinical_workshop.get_abnormal_labs(135236);

-- Test 3: vector search
SELECT * FROM hls_amer_catalog.clinical_workshop.clinical_notes_vector_search(
  'patient on ventilator with respiratory failure'
);
```

---

## Module 4 — Genie Room: Structured Analytics (~10 min)

**Goal:** Create a Genie room over the structured tables for natural language SQL queries.

1. Go to **Genie** → **New Genie Room**
2. Add these tables:
   - `hls_amer_catalog.clinical_workshop.admissions`
   - `hls_amer_catalog.clinical_workshop.lab_events`
   - `hls_amer_catalog.clinical_workshop.d_labitems`
   - `hls_amer_catalog.clinical_workshop.diagnoses_icd`
   - `hls_amer_catalog.clinical_workshop.d_icd_diagnoses`
   - `hls_amer_catalog.clinical_workshop.patients`
3. Set description:
   ```
   Clinical data warehouse for ICU patient cohort. Contains admissions,
   lab results, diagnoses, and patient demographics for 1,325 patients
   across 1,590 hospital stays. Data is synthetic (MIMIC-III).
   ```
4. Save and test with: `How many patients were admitted as emergencies?`

---

## Module 5 — Supervisor Agent (~20 min)

**Goal:** Wire everything together into one agent that routes questions intelligently.

1. Mosaic AI → **Agents** → **New Agent**
2. Select type: **Custom Agent** (or Supervisor)
3. Add tools:
   - **Knowledge Assistant** (from Module 2)
   - `get_latest_admission`
   - `get_abnormal_labs`
   - `get_lab_type`
   - `get_clinical_notes`
   - `clinical_notes_vector_search`
   - **Genie room** (managed MCP — from Module 4)
4. Set system prompt:
   ```
   You are a clinical supervisor agent. You answer questions using both
   structured clinical data and unstructured clinical notes.

   For structured data queries (labs, admissions, diagnoses, population stats):
   use get_latest_admission, get_abnormal_labs, get_lab_type, or the Genie tool.

   For specific patient notes on a known admission: use get_clinical_notes.

   For semantic search over note content: use clinical_notes_vector_search
   or the Knowledge Assistant.

   Always cite source metadata (HADM_ID, chart date) in your response.
   Be concise.
   ```
5. Test with the sample questions below

---

## Sample Demo Questions

### Patient-specific (structured + notes)
- *"What was patient 22's most recent admission and discharge plan?"*
  - Expected: uses `get_latest_admission` → `get_clinical_notes`
- *"Did patient 22 have any abnormal labs during their latest admission?"*
  - Expected: uses `get_latest_admission` → `get_abnormal_labs` → `get_lab_type`

### Population-level (Genie + KA)
- *"What are common diagnoses for patients with abdominal pain?"*
  - Expected: routes to Genie or `clinical_notes_vector_search`
- *"What are common causes of low oxygen saturation in ICU patients?"*
  - Expected: routes to Knowledge Assistant
- *"What diagnoses are most associated with repeated respiratory interventions?"*
  - Expected: routes to Knowledge Assistant or Genie

### Cross-modal
- *"What are common complications from vascular procedures?"*
  - Expected: Knowledge Assistant for narrative context

---

## Data Dictionary

### note_events_20000
| Column | Description |
|---|---|
| ROW_ID | Unique note identifier |
| SUBJECT_ID | Patient identifier |
| HADM_ID | Hospital admission identifier |
| CHARTDATE | Date the note was charted |
| CHARTTIME | Time the note was charted |
| CATEGORY | Note type (e.g., Nursing/other) |
| DESCRIPTION | Note subtype (e.g., Report) |
| TEXT | Full clinical note text |

### admissions
| Column | Description |
|---|---|
| SUBJECT_ID | Patient identifier |
| HADM_ID | Unique hospital admission ID |
| ADMITTIME | Admission timestamp |
| DISCHTIME | Discharge timestamp |
| ADMISSION_TYPE | Emergency / Elective / Newborn / Urgent |
| INSURANCE | Insurance type |
| DIAGNOSIS | Admission diagnosis |
| DISCHARGE_LOCATION | Where patient went after discharge |

### lab_events
| Column | Description |
|---|---|
| HADM_ID | Hospital admission identifier |
| ITEMID | Lab item identifier (join to d_labitems) |
| CHARTTIME | When the lab was resulted |
| VALUE | Result value (text) |
| VALUENUM | Result value (numeric) |
| VALUEUOM | Unit of measure |
| FLAG | `abnormal` if outside reference range |

---

## Notes for Instructors

- **Pre-create** the vector index (Module 2) before the session — it takes 5-10 min
- **Pre-create** the Genie room (Module 4) if time is tight
- The `clinical_notes_vector_search` UC function requires the vector index to exist first — update the index name in `01_create_functions.sql` if you used a different name
- All data is synthetic/de-identified — safe to use in any customer-facing session
- Parquet files total ~23 MB; PDFs total ~84 KB

---

*Built with Databricks Mosaic AI | MIMIC-III synthetic cohort | Workshop version 1.0*
