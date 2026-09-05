<img width="16816" height="11936" alt="GRAPHICAL ABSTRACT" src="https://github.com/user-attachments/assets/cfe74055-966a-4fcd-820a-ff98868d5d07" />

GRAPHICAL ABSTRACT Overview of the study. EHR: electronic health record; LLM: large language model; OR: odds ratio; CI: confidence interval; CCVC: cardio-cerebrovascular comorbidity.




# AECOPD environmental triggers

Analysis code for the multicentre case-crossover study of acute exacerbations of COPD, reconstructed symptom onset, influenza activity, air pollution, meteorological exposures, and clinical susceptibility.

## Workflow

1. External exposure preparation: CHAP GeoTIFF/CMFD NetCDF county-level aggregation and weekly-to-daily influenza expansion.
2. Clinical-variable extraction with Gemma 3 through the Ollama generate API.
3. Symptom-onset reconstruction and phenotype construction.
4. Case-crossover control-day construction and lagged exposure expansion.
5. Conditional logistic regression, subgroup interaction testing, temperature DLNM, and subtype Wald contrasts in R.
6. LLM extraction performance evaluation in Python.

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
python python/00_prepare_external_exposures.py geotiff-to-county \
  --raster-dir <raster-directory> \
  --counties <county-boundary-file> \
  --county-id <county-column> \
  --variable Tavg \
  --output <county-date-output.csv> \
  --kelvin-to-celsius

python python/00_prepare_external_exposures.py netcdf-to-county \
  --netcdf-dir <cmfd-netcdf-directory> \
  --counties <county-boundary-file> \
  --county-id county_name \
  --data-variable <temperature-variable> \
  --daily-statistic mean \
  --variable Tavg \
  --output <tavg-county-date.csv> \
  --kelvin-to-celsius

# Repeat with daily-statistic max/Tmax and min/Tmin, then merge the three tables.
python python/00_prepare_external_exposures.py merge-county-tables \
  --inputs <tavg-county-date.csv> <tmax-county-date.csv> <tmin-county-date.csv> \
  --county-id county_name \
  --output <temperature.csv>

python python/00_prepare_external_exposures.py influenza-weekly-to-daily \
  --input <weekly-influenza-table> \
  --output <daily-influenza-table.csv> \
  --week-start week_start \
  --interpolate
```

Run clinical extraction after starting Ollama with `gemma3:27b-it-qat` available:

```text
python python/01_extract_ehr_information.py \
  --input <clinical-table.xlsx> \
  --output <extracted-variables.csv> \
  --retain-columns record_key visit_date
```

Gemma 3 is used for structured extraction across the entire cohort. The extractor submits the symptoms/duration, smoking, and comorbidity tasks once per record, with up to three retries after failed requests. The seven-model, three-run workflow is the reference-set benchmark. Settings are recorded in `config/llm_model_registry.json`. Field definitions and command-line options are documented in `docs/clinical_information_extraction.md` and `config/clinical_extraction_schema.json`.

Evaluate an annotated reference table:

```text
python python/04_evaluate_llm_extraction.py \
  --input <reference-and-prediction-table> \
  --output <metrics.csv> \
  --task duration \
  --reference duration_reference \
  --prediction duration_prediction
```

The evaluation utility also supports `numeric`, `classification`, `multilabel`, `stability`, `system`, and `ranking` tasks. Duration output includes Bland–Altman bias and 95% limits of agreement; system output includes bootstrap intervals for latency, throughput, and success rate.

Reconstruct onset dates and derive prespecified groupings:

```text
python python/02_reconstruct_onset_and_phenotypes.py \
  --input <extracted-variables.csv> \
  --output <onset-and-phenotypes.csv> \
  --visit-date visit_date \
  --duration duration_days \
  --max-duration 14

python python/05_build_onset_window_sensitivity.py \
  --input <extracted-variables.csv> \
  --output-dir <onset-window-directory> \
  --visit-date visit_date \
  --duration duration_days \
  --caps 14 21 30
```

Construct case-control records from the harmonised exposure files:

```text
python python/03_prepare_case_control.py
```

This script reads file locations from `AECOPD_*_FILE` environment variables and writes to `AECOPD_OUTPUT_DIR`.

A symptom coded `mild` is treated as the reference category because the manuscript contrast is `present/severe` versus `absent/mild`. Missing or unobserved symptom values remain missing.

## R environment

The statistical workflow was organised for R 4.3.3. Install the packages listed in `r/required_packages.R`, then set:

```text
AECOPD_ANALYSIS_INPUT=<case-control-csv>
AECOPD_DATA_DIR=<data-directory>
AECOPD_OUTPUT_DIR=<results-directory>
AECOPD_CONTROL_STRATEGY=monthly_weekday
```

Main analysis:

```text
Rscript r/01_main_analysis.R
```

Run the same R script separately on the `monthly_weekday` and `symmetric_weekday` case-control tables, setting `AECOPD_CONTROL_STRATEGY` to the corresponding value. The 14-, 21-, and 30-day onset-window tables are likewise reconstructed and modelled separately.

For a leave-one-centre-out run, set `AECOPD_EXCLUDE_CENTRE` to the centre code and rerun the same main script. `AECOPD_CENTRE_VAR` can be used when the centre column has a different name.

Subtype contrast:

```text
Rscript r/02_subtype_wald_contrast.R
```

The main R analysis includes overall, heating-season, non-heating-season, lag 0–7, aggregated-window, temperature DLNM, subgroup, and FDR-adjusted interaction outputs. The heating season is parameterised as 20 October through 6 April. Major COVID-19 wave indicators are parameterised in the R scripts and can be changed before analysis.

## Statistical conventions retained

- Time-stratified case-crossover matching by calendar month and day of week is the primary strategy.
- Symmetric ±7, ±14, and ±21 day referent selection is the sensitivity strategy.
- Other event dates from the same patient are excluded from control days.
- Patient-level cluster-robust variance is used for recurrent events.
- Environmental models control for concurrent influenza positivity according to the prespecified model family.
- Temperature DLNMs use a 0–21 day lag window with natural cubic splines.
- Interaction p values are adjusted with the Benjamini–Hochberg FDR procedure.
