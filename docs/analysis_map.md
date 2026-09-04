# Analysis map

| Analysis component | Implementation |
|---|---|
| CHAP/CMFD county-level aggregation and weekly influenza expansion | `python/00_prepare_external_exposures.py` |
| EHR information extraction | `python/01_extract_ehr_information.py` |
| Extraction output schema | `config/clinical_extraction_schema.json` |
| Production and benchmark model settings | `config/llm_model_registry.json` |
| Symptom-onset reconstruction and clinical grouping | `python/02_reconstruct_onset_and_phenotypes.py` |
| Case-control referent construction and lag expansion | `python/03_prepare_case_control.py` |
| LLM extraction metrics | `python/04_evaluate_llm_extraction.py` |
| 14-, 21-, and 30-day onset-window datasets | `python/05_build_onset_window_sensitivity.py` |
| Conditional logistic, temperature DLNM, subgroup and interaction analyses | `r/01_main_analysis.R` |
| Leave-one-centre analysis | `r/01_main_analysis.R` with `AECOPD_EXCLUDE_CENTRE` |
| H1N1 versus H3N2 Wald contrast | `r/02_subtype_wald_contrast.R` |

## Clinical variables

The extraction output contains acute-exacerbation duration, eight symptom domains, smoking history and sixteen comorbidity fields. Asthma and emphysema group variables are read from structured clinical fields during phenotype construction rather than from the sixteen-field comorbidity extraction output.

## Statistical settings

- The primary referent strategy matches case and control days by calendar month and day of week.
- The alternative referent strategy uses days 7, 14 and 21 before and after the event.
- Single-day models cover lag 0 through lag 7.
- Temperature DLNM uses lag 0 through lag 21, exposure-response natural spline df=4 and lag-response natural spline df=3.
- Overall and clinical-subgroup models use a common exposure IQR; seasonal models use the corresponding season-specific IQR.
- Recurrent events use patient-clustered variance.
- Interaction p values are adjusted with the Benjamini–Hochberg procedure.
