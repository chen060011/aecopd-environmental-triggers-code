# Analysis map

This repository contains analysis code only. Plotting branches, generated figures, patient records, and record-level examples are excluded.

| Analysis component | Curated implementation |
|---|---|
| County-level raster aggregation and weekly influenza expansion | `python/00_prepare_external_exposures.py` |
| EHR information extraction with a local LLM | `python/01_extract_ehr_information.py` |
| Extraction output contract | `config/clinical_extraction_schema.json` |
| Symptom-onset reconstruction and prespecified clinical grouping | `python/02_reconstruct_onset_and_phenotypes.py` |
| Case-control referent construction and lag expansion | `python/03_prepare_case_control.py` |
| LLM extraction validation metrics | `python/04_evaluate_llm_extraction.py` |
| Main conditional logistic, DLNM, distributed-lag, subgroup and FDR interaction analyses | `r/01_main_analysis.R` |
| Leave-one-centre sensitivity analysis | `r/01_main_analysis.R` with `AECOPD_EXCLUDE_CENTRE` |
| H1N1 versus H3N2 formal Wald contrast | `r/02_subtype_wald_contrast.R` |

## Clinical extraction domains

The extraction interface covers acute symptom duration, eight respiratory/systemic symptom domains, smoking history, and eighteen prespecified comorbidities. Missing or unmentioned information remains missing rather than being converted to a negative finding. Detailed fields and usage are documented in `docs/clinical_information_extraction.md`.

## Deliberately excluded

- all Python and R figure-generation code;
- generated PNG, PDF, SVG and source-data figure files;
- hospital-specific duplicate notebooks;
- deleted, backup, preview and exploratory versions;
- raw EHR extraction notebooks containing credentials or clinical records;
- raw CHAP/CMFD files, surveillance PDFs, model caches and patient-level intermediate tables;
- duplicated R branches already covered by the integrated main analysis.

The final manuscript and supplementary-material copies were used to define the retained analysis scope. File modification time was used only as supporting evidence.
