# Clinical AI Assistant Workshop
**Databricks | HLS Payer Series | 2-3 hour session**

A hands-on workshop for new Databricks users that demonstrates building a clinical AI assistant using:
- **Vector Search Index** — Embed 20,000 clinical notes for semantic retrieval
- **Knowledge Assistant (KA)** — RAG agent over clinical notes
- **KIE** — Extract structured fields from clinical PDFs using `ai_extract()`
- **Supervisor Agent** — Orchestrates Genie (managed MCP) + UC functions + Knowledge Assistant

All data is synthetic (MIMIC-III de-identified, cohort-scoped to 1,590 admissions).

---

## Repository Structure

```
clinical_workshop/
├── parquet/                     # Source data — loaded by setup notebook
│   ├── note_events_20000/       # 20,000 clinical notes (KA + VS corpus)
│   ├── admissions/              # 1,590 hospital admissions
│   ├── patients/                # 1,325 patients
│   ├── lab_events/              # 883,423 lab results (cohort-filtered)
│   ├── d_labitems/              # 753 lab item definitions (lookup)
│   ├── diagnoses_icd/           # 15,566 ICD-9 codes per admission
│   └── d_icd_diagnoses/         # 14,567 ICD-9 code descriptions (lookup)
├── pdfs/                        # 30 clinical note PDFs for KIE module
├── notebooks/
│   ├── 00_setup.py              # Run once — creates schema, loads tables
│   └── 01_create_functions.sql  # Creates 5 UC functions for Supervisor Agent
└── README.md                    # This file
```

---

## Prerequisites

- Databricks workspace with Unity Catalog enabled
- A catalog you have `CREATE SCHEMA` permission on
- Serverless compute or a running SQL Warehouse
- Access to `databricks-gte-large-en` embedding model endpoint

---

## Step 0 — Deploy Data (Instructor, Pre-workshop)

### Option A: CLI (fully automated)

```bash
# 1. Clone the repo
git clone https://github.com/ritwikamukherjee/clinical-ai-workshop
cd clinical-ai-workshop

# 2. Authenticate (opens browser for SSO)
databricks auth login https://<your-workspace>.cloud.databricks.com --profile=workshop

# 3. Create schema (catalog must already exist)
databricks --profile=workshop schemas create <schema> <catalog>

# 4. Create volumes
databricks --profile=workshop volumes create <catalog> <schema> raw_data MANAGED
databricks --profile=workshop volumes create <catalog> <schema> clinical_pdfs MANAGED

# 5. Upload Parquet files
databricks --profile=workshop fs cp -r parquet/ \
  dbfs:/Volumes/<catalog>/<schema>/raw_data/parquet/

# 6. Upload PDFs
databricks --profile=workshop fs cp -r pdfs/ \
  dbfs:/Volumes/<catalog>/<schema>/clinical_pdfs/

# 7. Import the setup notebook into the workspace
databricks --profile=workshop workspace import \
  /Shared/clinical_workshop/00_setup \
  --file notebooks/00_setup.py \
  --format SOURCE --language PYTHON --overwrite
```

Then open `/Shared/clinical_workshop/00_setup` in the workspace, set the **catalog** and **schema** widgets, and **Run All** to load the Delta tables (~5 min).

### Option B: Workspace UI
1. `git clone https://github.com/ritwikamukherjee/clinical-ai-workshop` locally
2. Catalog Explorer → create schema `<catalog>.<schema>`
3. Create two volumes: `raw_data` and `clinical_pdfs`
4. Drag-and-drop the `parquet/` folder into `raw_data/parquet/`
5. Drag-and-drop all PDFs into `clinical_pdfs/`
6. Import `notebooks/00_setup.py` via **Workspace → Import**
7. Set widgets, **Run All**

---

## Module 1 — Vector Search Index (~15 min)

**Goal:** Create a vector index on `note_events_20000`. This powers both the Knowledge Assistant and the `clinical_notes_vector_search` UC function.

### Step 1.1 — Create a Vector Search endpoint (if none exists)
Mosaic AI → Vector Search → **Create endpoint**
- Name: `workshop-vs-endpoint`
- Wait for status: **Online**

### Step 1.2 — Create the index
1. Catalog Explorer → `<catalog>.<schema>.note_events_20000`
2. Click **Create** → **Vector Search Index**
3. Configure:
   - **Index name**: `note_events_vs_index`
   - **Primary key**: `ROW_ID`
   - **Text column to embed**: `TEXT`
   - **Embedding model**: `databricks-gte-large-en`
   - **Endpoint**: `workshop-vs-endpoint`
   - **Sync**: Triggered
4. Click **Create** — indexing ~5-10 min for 20K rows

### Step 1.3 — Verify the index
Mosaic AI → Vector Search → select `note_events_vs_index` → confirm **Status: Online**

> **Note:** Keep the index name handy — you'll use it as the `vs_index` widget value in `01_create_functions.sql`.

---

## Module 2 — Knowledge Assistant (~15 min)

**Goal:** Build a KA agent that does semantic retrieval over the vector index.

### Step 2.1 — Create the Knowledge Assistant
1. Mosaic AI → **Agents** → **New Agent**
2. Select type: **Knowledge Assistant**
3. Attach vector index: `note_events_vs_index`
4. When prompted for column mappings:
   - **Doc URI Column**: `ROW_ID` — unique note identifier, used as the citation reference so the agent can tell you which note it retrieved from
   - **Text Column**: `TEXT` — the raw clinical note text, used for semantic retrieval
5. Set the **knowledge source description** (helps the KA understand what it's searching over):
   ```
   20,000 de-identified ICU clinical notes from the MIMIC-III dataset covering
   nursing assessments, physician progress notes, discharge summaries, and
   procedure reports across 1,590 hospital admissions. Notes contain free-text
   narratives including vital signs, medications, diagnoses, and care plans.
   ```
6. Set the **Instructions** (system prompt):
   ```
   You are a clinical notes retrieval assistant. You search a corpus of ICU
   clinical notes to answer questions about patient care, diagnoses,
   treatments, and outcomes.

   Guidelines:
   - Always cite the ROW_ID of the note(s) you retrieved so the user can
     trace back to the source.
   - If multiple notes are relevant, summarize across them and list each
     ROW_ID.
   - Do not infer diagnoses or lab values that are not explicitly stated
     in the retrieved notes. If the notes are ambiguous or incomplete,
     say so.
   - For population-level questions (e.g., "what are common causes of X"),
     synthesize patterns across retrieved notes rather than citing a
     single case.
   - Be concise. Use clinical terminology appropriate for a healthcare
     professional audience.
   ```
7. **Save** the agent — you'll add it as a tool in Module 5 (Supervisor Agent)

### Step 2.2 — Test the Knowledge Assistant
Try these questions in the agent playground. Expected behavior is shown below each question.

**Example 1 — Topic-based retrieval:**
```
Q: What are common causes of low oxygen saturation in ICU patients?

Expected: The KA retrieves several notes mentioning desaturation events
and synthesizes common causes (e.g., pneumonia, ARDS, pulmonary embolism,
fluid overload). Each cause is backed by one or more ROW_ID citations.
```

**Example 2 — Specific clinical scenario:**
```
Q: What complications are documented after vascular surgery procedures?

Expected: The KA pulls notes from post-operative vascular cases and
summarizes documented complications (e.g., bleeding, infection, graft
occlusion), citing the relevant ROW_IDs.
```

**Example 3 — Care pattern question:**
```
Q: What diagnoses are most associated with repeated respiratory interventions?

Expected: The KA identifies notes where patients required multiple
intubations, ventilator adjustments, or respiratory therapy, and lists
the associated diagnoses with citations.
```

---

## Module 3 — Information Extraction (Agent Bricks) (~20 min)

**Goal:** Convert clinical PDFs to markdown using the **Use PDFs** workflow, then use Agent Bricks: Information Extraction to turn the parsed text into structured fields.

> **Prerequisites:**
> - Agent Bricks Preview enabled (Workspace settings → **Previews** → enable **Mosaic AI Agent Bricks**)
> - PDFs uploaded to the `clinical_pdfs` volume (see Setup Step 5)
> - A SQL Warehouse available to run the PDF conversion pipeline
>
> *Note: Agent Bricks is in Beta and may have regional availability limitations.*

### Step 3.1 — Browse the PDFs
Catalog Explorer → `<catalog>.<schema>` → `clinical_pdfs` volume → click any PDF to preview

### Step 3.2 — Convert PDFs to markdown with "Use PDFs"

PDFs are not natively supported in Information Extraction — they must first be converted to markdown. The **Use PDFs** button automates this by running an `ai_parse_document` pipeline as a workflow job.

1. Mosaic AI → **Agents** → click **Use PDFs**
2. **PDF folder**: select your Unity Catalog volume folder:
   `/Volumes/<catalog>/<schema>/clinical_pdfs/`
3. **Destination table**: where the converted markdown will be stored, e.g.:
   `<catalog>.<schema>.clinical_pdfs_parsed`
4. **SQL Warehouse**: select an available warehouse to run the conversion
5. Click **Start** — this creates a workflow job that runs `ai_parse_document` on each PDF
6. You'll be redirected to the **All workflows** tab — monitor the job until it completes

Once the job finishes, verify the parsed output:
```sql
SELECT * FROM <catalog>.<schema>.clinical_pdfs_parsed LIMIT 5;
```

> The pipeline converts each PDF into markdown text using `ai_parse_document`, extracting text, tables, headers, and other document elements. The resulting table can now be used as input for the extraction agent.

### Step 3.3 — Create the Information Extraction agent

1. Mosaic AI → **Agents** → click the **Information Extraction** tile → **Build**
2. **Agent name**: `clinical_pdf_extractor`
3. **Dataset type**: select **Unlabeled dataset**
4. **Data source**: select the parsed markdown table from Step 3.2:
   `<catalog>.<schema>.clinical_pdfs_parsed`
5. **Output schema** — verify or adjust the JSON schema. Use this for clinical notes:
   ```json
   {
     "diagnosis": "string: Primary and secondary diagnoses documented in this note",
     "medications": "string: Medications administered or ordered, including dosages if mentioned",
     "procedures": "string: Clinical procedures performed during this encounter",
     "follow_up_plan": "string: Planned next steps, discharge instructions, or pending orders",
     "patient_status": "string: Overall patient condition at time of note (e.g., stable, critical, improving)"
   }
   ```
6. **Model**: select **Optimize for Complexity** (clinical notes are long and nuanced)
7. Click **Create agent**

### Step 3.4 — Refine the extraction

1. In the **Build** tab, review the sample outputs for the first few PDFs
2. Use **thumbs up / thumbs down** to give feedback on each extraction
3. Adjust field descriptions in the **Output fields** section if the agent misinterprets a field
4. Optionally add **global instructions** to guide the agent:
   ```
   These are ICU clinical notes from de-identified patient records. Extract
   only information explicitly stated in the note. Do not infer diagnoses
   or medications not mentioned. If a field has no relevant information in
   the document, return null.
   ```
5. Click **Save and update** — iterate until the extractions look correct

### Step 3.5 — Test and deploy

**Test in the Playground:**
1. Click **Open in Playground** on the agent page
2. Submit a clinical note and verify the structured output
3. Click **Get code** to see SQL, Python, and curl examples

**Batch extraction via SQL** — use `ai_query` to run the agent across your notes table:
```sql
SELECT
  SUBJECT_ID,
  HADM_ID,
  CHARTDATE,
  ai_query(
    '<your-agent-endpoint-name>',
    TEXT
  ) AS extracted
FROM <catalog>.<schema>.note_events_20000
LIMIT 10;
```

**Store as a Delta table:**
```sql
CREATE OR REPLACE TABLE <catalog>.<schema>.note_events_extracted AS
SELECT
  SUBJECT_ID,
  HADM_ID,
  CHARTDATE,
  TEXT,
  ai_query(
    '<your-agent-endpoint-name>',
    TEXT
  ) AS extracted
FROM <catalog>.<schema>.note_events_20000
LIMIT 100;
```

Explore the results:
```sql
SELECT
  SUBJECT_ID,
  extracted.diagnosis,
  extracted.medications,
  extracted.patient_status
FROM <catalog>.<schema>.note_events_extracted
LIMIT 20;
```

> **Note:** The Information Extraction agent has a 128k token limit per document. Clinical notes in this dataset are well within this limit.

---

## Module 4 — UC Functions (~10 min)

**Goal:** Register the UC tool functions used by the Supervisor Agent.

Open `notebooks/01_create_functions.sql` in the SQL Editor.

Update the three `DECLARE` values at the top to match your environment:
```sql
DECLARE OR REPLACE catalog_name  = 'hls_amer_catalog';
DECLARE OR REPLACE schema_name   = 'clinical_workshop';
DECLARE OR REPLACE vs_index_name = 'note_events_vs_index';
```

Run all statements in order. A pre-flight check will verify the Vector Search index exists (Module 1). This creates 5 functions:

| Function | Input | What it does |
|---|---|---|
| `get_latest_admission(patient_id)` | SUBJECT_ID | Most recent admission record |
| `get_abnormal_labs(admission_id)` | HADM_ID | All abnormal lab results |
| `get_lab_type(item_id)` | ITEMID | Resolves lab ID to label/category |
| `get_clinical_notes(admission_id, date)` | HADM_ID + date | Notes for a specific admission + date |
| `clinical_notes_vector_search(query)` | free text | Semantic search over note embeddings |

**Test each function:**
```sql
-- Test 1
SELECT * FROM <catalog>.<schema>.get_latest_admission(22);

-- Test 2 (use HADM_ID from test 1)
SELECT * FROM <catalog>.<schema>.get_abnormal_labs(135236) LIMIT 10;

-- Test 3
SELECT * FROM <catalog>.<schema>.get_lab_type(51279);

-- Test 4
SELECT * FROM <catalog>.<schema>.get_clinical_notes(175562, '2143-01-18');

-- Test 5 (requires Module 1 complete)
SELECT * FROM <catalog>.<schema>.clinical_notes_vector_search('patient on ventilator with respiratory failure');
```

---

---

## Module 5 — Supervisor Agent (~35 min)

**Goal:** Wire the Knowledge Assistant, UC functions, and Genie into a single orchestrating agent.

### Step 5.1 — Create the Genie Room (Managed MCP)

1. **Genie** → **New Genie Room**
2. Add tables:
   - `<catalog>.<schema>.admissions`
   - `<catalog>.<schema>.lab_events`
   - `<catalog>.<schema>.d_labitems`
   - `<catalog>.<schema>.diagnoses_icd`
   - `<catalog>.<schema>.d_icd_diagnoses`
   - `<catalog>.<schema>.patients`
3. Set description:
   ```
   Clinical data warehouse for an ICU patient cohort. Contains admissions,
   lab results, diagnoses, and patient demographics for 1,325 patients across
   1,590 hospital stays. Data is synthetic (MIMIC-III).
   ```
4. **Save** — test with: `How many patients were admitted as emergencies?`

---

### Step 5.2 — Build the Supervisor Agent

1. Mosaic AI → **Agents** → **New Agent**
2. Select type: **Custom Agent** (or Supervisor)
3. Add tools:
   - **Knowledge Assistant** (from Module 2) — handles semantic search over clinical notes
   - `get_latest_admission`
   - `get_abnormal_labs`
   - `get_lab_type`
   - `get_clinical_notes`
   - **Genie room** (add as managed MCP tool from Step 5.1)
4. Set system prompt:
   ```
   You are a clinical supervisor agent that answers questions using structured
   clinical data, unstructured clinical notes, and published evidence.

   Routing guidelines:
   - For population-level or analytics questions (counts, trends, distributions):
     use the Genie tool.
   - For a specific patient's admission history: use get_latest_admission.
   - For a specific patient's lab results: use get_abnormal_labs, then
     get_lab_type to resolve item IDs.
   - For notes on a known admission date: use get_clinical_notes.
   - For semantic search over note content: use the Knowledge Assistant.

   Always cite source metadata (HADM_ID, chart date) in your response.
   Be concise.
   ```
5. **Save and test** with the sample questions below

---

## Sample Demo Questions

### Patient-specific
- *"What was patient 22's most recent admission and what was their discharge plan?"*
  > Agent should: `get_latest_admission(22)` → `get_clinical_notes(hadm_id, date)`
- *"Did patient 22 have any abnormal labs during their latest admission?"*
  > Agent should: `get_latest_admission(22)` → `get_abnormal_labs(hadm_id)` → `get_lab_type(item_id)`

### Population-level (Genie)
- *"How many patients were admitted as emergencies?"*
- *"What are the most common admission diagnoses in this cohort?"*

### Semantic (Knowledge Assistant)
- *"What are common causes of low oxygen saturation in ICU patients?"*
- *"What diagnoses are most associated with repeated respiratory interventions?"*
- *"What are common complications from vascular procedures?"*

---

## Module 6 — Evaluate with MLflow Scorers (Optional, ~20 min)

**Goal:** Use MLflow's built-in `Correctness` and `Completeness` scorers to evaluate the Supervisor Agent's responses against clinical ground truth.

> **Why programmatic?** The Correctness scorer requires ground truth (`expected_facts` or `expected_response`) to be attached to each trace. If you run the scorer from the Experiment → Traces UI without expectations logged, you'll see:
> `CUSTOM_METRIC_ERROR: Correctness scorer requires either expected_response or expected_facts in the expectations dictionary.`
>
> The programmatic approach below handles this correctly — either by passing expectations inline with `mlflow.genai.evaluate()`, or by logging them to existing traces with `mlflow.log_expectation()`.

### Overview

| Scorer | What it measures | Ground truth required? |
|---|---|---|
| **Correctness** | Are the facts in the response accurate? | **Yes** — needs `expected_facts` (list of statements) or `expected_response` (single string) |
| **Completeness** | Does the response address all parts of the question? | **No** — judges against the original query |

---

### Approach 1: Batch Evaluation with `mlflow.genai.evaluate()`

This is the simplest approach — pass questions, expectations, and scorers together. MLflow runs the agent, creates traces, and evaluates them in one step.

#### Step 1.1 — Create the evaluation dataset

Use `expected_facts` (a list of short, verifiable factual statements) rather than `expected_response`. This gives the Correctness judge flexibility since the agent's wording will vary across runs.

```python
import mlflow
from mlflow.genai.scorers import Correctness, Completeness

mlflow.set_experiment("/Shared/clinical_workshop/evaluation")

eval_dataset = [
    # --- Patient-specific: admission lookup ---
    {
        "inputs": {"query": "What was patient 22's most recent admission?"},
        "expectations": {
            "expected_facts": [
                "Patient 22 (SUBJECT_ID=22) has an admission record",
                "The response includes HADM_ID",
                "The response includes admission and discharge dates",
                "The admission type is specified (e.g., EMERGENCY, ELECTIVE)",
            ]
        },
    },
    # --- Patient-specific: abnormal labs ---
    {
        "inputs": {"query": "Did patient 22 have any abnormal labs during admission 135236?"},
        "expectations": {
            "expected_facts": [
                "The response identifies abnormal lab results for HADM_ID 135236",
                "Lab items are resolved to human-readable names (not just ITEMIDs)",
                "Units of measure are included for lab values",
            ]
        },
    },
    # --- Clinical notes retrieval ---
    {
        "inputs": {"query": "What do the clinical notes say about respiratory failure in ICU patients?"},
        "expectations": {
            "expected_facts": [
                "The response references specific clinical notes (ROW_IDs or HADM_IDs cited)",
                "Mentions respiratory-related findings (e.g., ventilator, intubation, O2 saturation)",
                "Does not fabricate diagnoses not present in the retrieved notes",
            ]
        },
    },
    # --- Population-level via Genie ---
    {
        "inputs": {"query": "How many patients were admitted as emergencies?"},
        "expectations": {
            "expected_facts": [
                "The response includes a specific count of emergency admissions",
                "The count is derived from the admissions table where ADMISSION_TYPE = 'EMERGENCY'",
            ]
        },
    },
    # --- Multi-step clinical reasoning ---
    {
        "inputs": {"query": "For patient 22, get their latest admission, check for abnormal labs, and summarize the clinical picture."},
        "expectations": {
            "expected_facts": [
                "The response includes the most recent admission details (HADM_ID, dates, diagnosis)",
                "Abnormal lab results are listed with resolved lab names",
                "A clinical summary ties the admission diagnosis to the lab findings",
                "Source metadata (HADM_ID, chart dates) is cited",
            ]
        },
    },
]
```

#### Step 1.2 — Run evaluation

```python
# Point to your deployed Supervisor Agent endpoint
predict_fn = mlflow.genai.to_predict_fn(
    "serving_endpoint",
    endpoint_name="<your-supervisor-agent-endpoint>",
)

# Run both scorers — Correctness uses expected_facts, Completeness uses the query
results = mlflow.genai.evaluate(
    data=eval_dataset,
    predict_fn=predict_fn,
    scorers=[
        Correctness(),
        Completeness(),
    ],
)

# View results — each row shows yes/no + rationale
results.tables["eval_results"]
```

Each result row includes:
- **`value`**: `"yes"` or `"no"`
- **`rationale`**: the judge's detailed explanation

Navigate to the experiment in MLflow UI → **Evaluation** tab to see results alongside traces.

---

### Approach 2: Log Expectations to Existing Traces

Use this when you already have traces (e.g., from the Agent Playground or production traffic) and want to annotate them with ground truth so the Correctness scorer can run.

> **This is what fixes the `CUSTOM_METRIC_ERROR`** — the scorer needs expectations attached to each trace before it can evaluate.

#### Step 2.1 — Log expectations to a trace

```python
import mlflow
from mlflow.entities import AssessmentSource
from mlflow.entities.assessment_source import AssessmentSourceType

# Get a trace_id from the Experiment → Traces tab in the MLflow UI
trace_id = "<your-trace-id>"

# Log expected_facts for the Correctness scorer
mlflow.log_expectation(
    trace_id=trace_id,
    name="expected_facts",
    value=[
        "Patient 22 (SUBJECT_ID=22) has an admission record",
        "The response includes HADM_ID",
        "The response includes admission and discharge dates",
        "The admission type is specified (e.g., EMERGENCY, ELECTIVE)",
    ],
    source=AssessmentSource(
        source_type=AssessmentSourceType.HUMAN,
        source_id="workshop_instructor",
    ),
)
```

#### Step 2.2 — Batch-annotate multiple traces

```python
# Map trace IDs to their expected facts
trace_expectations = {
    "<trace-id-admission-query>": [
        "Patient 22 has an admission record",
        "The response includes HADM_ID",
        "Admission and discharge dates are included",
    ],
    "<trace-id-abnormal-labs>": [
        "Abnormal lab results for HADM_ID 135236 are identified",
        "Lab items are resolved to human-readable names",
        "Units of measure are included",
    ],
    "<trace-id-respiratory-notes>": [
        "Specific clinical notes are cited (ROW_IDs or HADM_IDs)",
        "Respiratory-related findings are mentioned",
        "No fabricated diagnoses",
    ],
}

source = AssessmentSource(
    source_type=AssessmentSourceType.HUMAN,
    source_id="workshop_instructor",
)

for trace_id, facts in trace_expectations.items():
    mlflow.log_expectation(
        trace_id=trace_id,
        name="expected_facts",
        value=facts,
        source=source,
    )

print(f"Logged expectations for {len(trace_expectations)} traces")
```

After logging expectations, go back to **Experiment → Traces** and re-run the Correctness scorer — it will now find the `expected_facts` and evaluate correctly.

---

### Interpreting results

| Question type | Correctness catches | Completeness catches |
|---|---|---|
| Patient admission lookup | Wrong HADM_ID, fabricated dates | Missing admission type or diagnosis |
| Abnormal labs | Wrong lab values, unresolved ITEMIDs | Returned labs but forgot to resolve names |
| Clinical notes retrieval | Hallucinated diagnoses not in notes | Retrieved notes but didn't cite ROW_IDs |
| Population query (Genie) | Wrong count or misattributed filter | Gave count but didn't specify the filter used |
| Multi-step reasoning | Any factual error in the chain | Answered one sub-question but skipped others |

> **Tip:** Start with 5-10 eval examples covering your key question types. Expand the dataset as you identify failure modes. Write `expected_facts` as short, verifiable statements — not full expected responses.

---

## Data Dictionary

### note_events_20000
| Column | Description |
|---|---|
| ROW_ID | Unique note identifier (primary key for vector index) |
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

- **Pre-create** the vector index (Module 1) before the session — it takes 5-10 min to sync
- The `clinical_notes_vector_search` function requires the vector index to exist first — set the `vs_index_name` variable in `01_create_functions.sql` to match your index name
- All data is synthetic and de-identified — safe for any customer-facing session
- Parquet files: ~23 MB total | PDFs: ~84 KB total

---

*Built with Databricks Mosaic AI | MIMIC-III synthetic cohort | Workshop v1.0*
