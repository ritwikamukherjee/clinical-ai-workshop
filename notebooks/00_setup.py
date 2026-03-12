# Databricks notebook source
# MAGIC %md
# MAGIC # Workshop Setup: Clinical AI Assistant
# MAGIC Run this notebook once before the workshop. It will:
# MAGIC 1. Create the schema and volumes in your chosen catalog
# MAGIC 2. Load all Delta tables from Parquet
# MAGIC 3. Confirm PDFs are in place
# MAGIC
# MAGIC **Estimated run time: ~5 minutes**

# COMMAND ----------
# MAGIC %md ## Step 1: Configure catalog and schema
# MAGIC Set the values below, then run all cells.

# COMMAND ----------
dbutils.widgets.text("catalog", "hls_amer_catalog", "Catalog")
dbutils.widgets.text("schema",  "clinical_workshop", "Schema")

CATALOG = dbutils.widgets.get("catalog")
SCHEMA  = dbutils.widgets.get("schema")

PARQUET_BASE = f"/Volumes/{CATALOG}/{SCHEMA}/raw_data/parquet"
PDF_VOLUME   = f"/Volumes/{CATALOG}/{SCHEMA}/clinical_pdfs"

print(f"Target:  {CATALOG}.{SCHEMA}")
print(f"Parquet: {PARQUET_BASE}")
print(f"PDFs:    {PDF_VOLUME}")

# COMMAND ----------
# MAGIC %md ## Step 2: Create schema and volumes

# COMMAND ----------
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")
print(f"Schema ready: {CATALOG}.{SCHEMA}")

spark.sql(f"""
  CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}.raw_data
  COMMENT 'Raw Parquet data files for workshop setup'
""")
spark.sql(f"""
  CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}.clinical_pdfs
  COMMENT 'Clinical note PDFs for the KIE extraction module'
""")
print("Volumes ready")

# COMMAND ----------
# MAGIC %md ## Step 3: Load Delta tables from Parquet

# COMMAND ----------
TABLES = [
    "note_events_20000",
    "admissions",
    "patients",
    "lab_events",
    "d_labitems",
    "diagnoses_icd",
    "d_icd_diagnoses",
]

for tbl in TABLES:
    parquet_path = f"{PARQUET_BASE}/{tbl}"
    df = spark.read.parquet(parquet_path)
    df.write.mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.{tbl}")
    count = spark.table(f"{CATALOG}.{SCHEMA}.{tbl}").count()
    print(f"  Loaded {tbl}: {count:,} rows")

print("\nAll tables loaded!")

# COMMAND ----------
# MAGIC %md ## Step 4: Verify row counts

# COMMAND ----------
counts = spark.sql(f"""
  SELECT 'note_events_20000' AS table_name, count(*) AS rows FROM {CATALOG}.{SCHEMA}.note_events_20000
  UNION ALL SELECT 'admissions',      count(*) FROM {CATALOG}.{SCHEMA}.admissions
  UNION ALL SELECT 'patients',        count(*) FROM {CATALOG}.{SCHEMA}.patients
  UNION ALL SELECT 'lab_events',      count(*) FROM {CATALOG}.{SCHEMA}.lab_events
  UNION ALL SELECT 'd_labitems',      count(*) FROM {CATALOG}.{SCHEMA}.d_labitems
  UNION ALL SELECT 'diagnoses_icd',   count(*) FROM {CATALOG}.{SCHEMA}.diagnoses_icd
  UNION ALL SELECT 'd_icd_diagnoses', count(*) FROM {CATALOG}.{SCHEMA}.d_icd_diagnoses
""")
display(counts)

# COMMAND ----------
# MAGIC %md ## Step 5: Confirm PDFs in volume
# MAGIC
# MAGIC Upload the PDFs from the workshop repo (`pdfs/` folder) to the `clinical_pdfs` volume.
# MAGIC You can drag-and-drop in Catalog Explorer:
# MAGIC `<catalog> > <schema> > clinical_pdfs`

# COMMAND ----------
try:
    pdf_files = dbutils.fs.ls(PDF_VOLUME)
    print(f"PDFs found in volume: {len(pdf_files)}")
    for f in pdf_files[:5]:
        print(f"  {f.name} ({f.size/1024:.1f} KB)")
    if len(pdf_files) < 30:
        print(f"\nWARNING: Expected 30 PDFs, found {len(pdf_files)}. Upload remaining files before Module 3 (KIE).")
except Exception as e:
    print(f"No PDFs found yet at {PDF_VOLUME}. Upload the pdfs/ folder before Module 3 (KIE).")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Setup Complete!
# MAGIC
# MAGIC **Workshop module order:**
# MAGIC 1. **Module 1 (Vector Search Index)** — Create a VS index on `note_events_20000` in Catalog Explorer
# MAGIC 2. **Module 2 (Knowledge Assistant)** — Build a KA agent using the VS index in Mosaic AI > Agents
# MAGIC 3. **Module 3 (KIE)** — Run `ai_extract()` on the PDFs in `clinical_pdfs` volume
# MAGIC 4. **Module 4 (UC Functions)** — Run `01_create_functions.sql` to register the tool functions
# MAGIC 5. **Module 5 (Supervisor Agent)** — Create a Genie room, then wire KA + Genie + UC functions into a Supervisor Agent
# MAGIC 6. **Module 6 (Evaluation)** *(Optional)* — Use MLflow Correctness and Completeness scorers to evaluate agent responses
