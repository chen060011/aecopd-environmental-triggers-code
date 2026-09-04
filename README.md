# AECOPD environmental triggers

Analysis code for the multicentre case-crossover study of acute exacerbations of COPD, reconstructed symptom onset, influenza activity, air pollution, meteorological exposures, and clinical susceptibility.

## Scope

The repository contains code only. Patient-level EHR records, clinical text, manually annotated records, exposure matrices, surveillance tables, derived result tables, figures, local model files, credentials, and machine-specific directories are intentionally excluded.

The workflow is split into:

1. External exposure preparation: county-level raster aggregation and weekly-to-daily influenza expansion.
2. Clinical-variable extraction: local, schema-constrained LLM extraction with validation and no credential embedded in code.
3. Symptom-onset reconstruction and phenotype construction.
4. Case-crossover control-day construction and lagged exposure expansion.
5. Conditional logistic regression, subgroup interaction testing, temperature DLNM, pollutant distributed-lag models, and subtype Wald contrasts in R.
6. LLM extraction performance evaluation in Python.

Plotting scripts are intentionally excluded. This repository retains analysis and table-generation code only.

## Reproducible input boundary

The scripts accept user-supplied files through command-line arguments or environment variables. The repository never assumes a local drive, user name, hospital name, or private directory.

The minimum event-level analysis table must contain:

- `match_id`: matched case-control set identifier
- `is_case`: 1 for case day and 0 for control day
- `cluster_id` or another patient-level cluster identifier
- `date`: analysis date
- `holiday`: public-holiday indicator
- lagged exposure columns such as `Tavg_lag0` through `Tavg_lag21`
- the clinical grouping columns used by the requested subgroup analysis

A schema template is provided in `config/analysis_input_schema.json`. It contains column names and definitions only.

## Python environment

```text
uv venv
uv pip install -r requirements.txt
```

Run the external-data utilities:

```text
python python/00_prepare_external_exposures.py raster-to-county \
  --raster-dir <raster-directory> \
  --counties <county-boundary-file> \
  --county-id <county-column> \
  --variable Tavg \
  --output <county-date-output.csv> \
  --kelvin-to-celsius

python python/00_prepare_external_exposures.py influenza-weekly-to-daily \
  --input <weekly-influenza-table> \
  --output <daily-influenza-table.csv> \
  --week-start week_start \
  --interpolate
```

Run clinical extraction against a local Ollama-compatible endpoint. The endpoint is local by default; no remote API key is required by the repository:

```text
python python/01_extract_ehr_information.py \
  --input <deidentified-clinical-table> \
  --output <extracted-variables.csv> \
  --text-columns chief_complaint present_illness past_history \
  --retain-columns record_key event_date
```

This is the information-extraction code. It extracts acute symptom duration, eight symptom domains, smoking history, and eighteen comorbidities through a local Ollama-compatible endpoint. See `docs/clinical_information_extraction.md` and `config/clinical_extraction_schema.json`. Input text is not copied to the output unless its column is explicitly requested with `--retain-columns`.

Evaluate an annotated reference table:

```text
python python/04_evaluate_llm_extraction.py \
  --input <reference-and-prediction-table> \
  --output <metrics.csv> \
  --task duration \
  --reference duration_reference \
  --prediction duration_prediction
```

Reconstruct onset dates and derive prespecified groupings:

```text
python python/02_reconstruct_onset_and_phenotypes.py \
  --input <extracted-variables.csv> \
  --output <onset-and-phenotypes.csv> \
  --visit-date visit_date \
  --duration duration_days \
  --max-duration 14
```

Construct case-control records from the harmonised exposure files:

```text
python python/03_prepare_case_control.py
```

This last script reads file locations from `AECOPD_*_FILE` environment variables and writes to `AECOPD_OUTPUT_DIR`. It is deliberately not run without private inputs.

A symptom coded `mild` is treated as the reference category because the manuscript contrast is `present/severe` versus `absent/mild`. Missing or unobserved symptom values remain missing.

## R environment

The statistical workflow was organised for R 4.3.3. Install the packages listed in `r/required_packages.R`, then set:

```text
AECOPD_ANALYSIS_INPUT=<case-control-csv>
AECOPD_DATA_DIR=<data-directory>
AECOPD_OUTPUT_DIR=<results-directory>
```

Main analysis:

```text
Rscript r/01_main_analysis.R
```

For a leave-one-centre-out run, set `AECOPD_EXCLUDE_CENTRE` to the centre code and rerun the same main script. `AECOPD_CENTRE_VAR` can be used when the centre column has a different name.

Subtype contrast:

```text
Rscript r/02_subtype_wald_contrast.R
```

The main R analysis includes overall, heating-season, non-heating-season, lag 0–7, aggregated-window, temperature DLNM, pollutant distributed-lag, subgroup, and FDR-adjusted interaction outputs. The heating season is parameterised as 20 October through 6 April. Major COVID-19 wave indicators are parameterised in the R scripts and can be changed before analysis. The R scripts write analysis tables and diagnostics but do not generate manuscript figures.

## Statistical conventions retained

- Time-stratified case-crossover matching by calendar month and day of week is the primary strategy.
- Symmetric ±7, ±14, and ±21 day referent selection is the sensitivity strategy.
- Other event dates from the same patient are excluded from control days.
- Patient-level cluster-robust variance is used for recurrent events.
- Environmental models control for concurrent influenza positivity according to the prespecified model family.
- Temperature DLNMs use a 0–21 day lag window with natural cubic splines.
- Interaction p values are adjusted with the Benjamini–Hochberg FDR procedure.
- Counts and percentages are never included as example data in this repository.

## Data governance

Use only de-identified, governance-approved data. Do not commit EHR text, manually annotated records, patient identifiers, residence information, raw surveillance PDFs, derived tables containing sample-level rows, local model outputs, API keys, or generated result files.
