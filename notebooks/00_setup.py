# Databricks notebook source
# MAGIC %md
# MAGIC # Workshop Setup: Clinical AI Assistant
# MAGIC Run this notebook once before the workshop. It will:
# MAGIC 1. Create the `hls_amer_catalog.clinical_workshop` schema
# MAGIC 2. Load all Delta tables from Parquet
# MAGIC 3. Upload clinical PDFs to a UC Volume
# MAGIC
# MAGIC **Estimated run time: ~5 minutes**

# COMMAND ----------
# MAGIC %md ## Configuration

# COMMAND ----------
CATALOG = "hls_amer_catalog"
SCHEMA  = "clinical_workshop"
# Path to the Parquet files — update if you stored them elsewhere
PARQUET_BASE = f"/Volumes/{CATALOG}/{SCHEMA}/raw_data/parquet"
PDF_VOLUME   = f"/Volumes/{CATALOG}/{SCHEMA}/clinical_pdfs"

# COMMAND ----------
# MAGIC %md ## Step 1: Create catalog, schema, and volumes

# COMMAND ----------
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")
print(f"Schema ready: {CATALOG}.{SCHEMA}")

spark.sql(f"""
  CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}.raw_data
  COMMENT 'Raw Parquet data files for workshop setup'
""")

spark.sql(f"""
  CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}.clinical_pdfs
  COMMENT 'Clinical note PDFs for the KIE (extraction) module'
""")
print("Volumes created")

# COMMAND ----------
# MAGIC %md ## Step 2: Load Delta tables from Parquet

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
# MAGIC %md ## Step 3: Verify table row counts

# COMMAND ----------
# MAGIC %sql
# MAGIC SELECT 'note_events_20000' as table_name, count(*) as rows FROM hls_amer_catalog.clinical_workshop.note_events_20000
# MAGIC UNION ALL SELECT 'admissions',     count(*) FROM hls_amer_catalog.clinical_workshop.admissions
# MAGIC UNION ALL SELECT 'patients',        count(*) FROM hls_amer_catalog.clinical_workshop.patients
# MAGIC UNION ALL SELECT 'lab_events',      count(*) FROM hls_amer_catalog.clinical_workshop.lab_events
# MAGIC UNION ALL SELECT 'd_labitems',      count(*) FROM hls_amer_catalog.clinical_workshop.d_labitems
# MAGIC UNION ALL SELECT 'diagnoses_icd',   count(*) FROM hls_amer_catalog.clinical_workshop.diagnoses_icd
# MAGIC UNION ALL SELECT 'd_icd_diagnoses', count(*) FROM hls_amer_catalog.clinical_workshop.d_icd_diagnoses

# COMMAND ----------
# MAGIC %md ## Step 4: Confirm PDFs uploaded to Volume
# MAGIC Upload the PDFs from the workshop repo to the clinical_pdfs volume before running this cell.
# MAGIC You can drag-and-drop in the Catalog Explorer UI under:
# MAGIC `hls_amer_catalog > clinical_workshop > clinical_pdfs`

# COMMAND ----------
import os
pdf_files = dbutils.fs.ls(PDF_VOLUME)
print(f"PDFs in volume: {len(pdf_files)}")
for f in pdf_files[:5]:
    print(f"  {f.name} ({f.size/1024:.1f} KB)")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Setup Complete!
# MAGIC
# MAGIC Next steps:
# MAGIC - **Module 1 (KIE)**: Go to Catalog Explorer, open `clinical_pdfs` volume, explore PDFs
# MAGIC - **Module 2 (Knowledge Base)**: Create vector index on `note_events_20000`
# MAGIC - **Module 3 (UC Functions)**: Run `01_create_functions.sql`
# MAGIC - **Module 4 (Supervisor Agent)**: Use the Agents UI
