# Clinical information extraction

`python/01_extract_ehr_information.py` extracts three groups of variables from clinical narratives:

- acute-exacerbation duration and eight symptom domains;
- smoking status and quantitative smoking history;
- sixteen comorbidity indicators.

The production workflow uses Gemma 3 (`gemma3:27b-it-qat`) through the Ollama generate API for structured extraction across the entire cohort. Each task is submitted once per record. Failed requests are retried up to three times with increasing timeouts. The model-comparison workflow is described in `config/llm_model_registry.json`.

## Input columns

The default text columns are:

- `chief_complaint`;
- `present_illness`;
- `past_history`;
- `吸烟史`.

Alternative column names can be supplied with command-line arguments.

## Usage

Start Ollama with the Gemma 3 model available, then run:

```text
python python/01_extract_ehr_information.py \
  --input <clinical-table.xlsx> \
  --output <extracted-variables.csv> \
  --retain-columns record_key visit_date
```

Available options include:

```text
--chief-complaint <column>
--present-illness <column>
--past-history <column>
--smoking-history <column>
--model <model-name>
--endpoint <ollama-generate-endpoint>
--timeout 120
--retries 3
```

The output contains only the columns requested through `--retain-columns` and the structured extraction fields. Source narratives are not copied automatically.

## Missing values

- Symptom information that cannot be assessed is returned as `null`.
- Smoking status is standardized to `never`, `former`, `current`, or `null`.
- Quantitative smoking fields are set to zero only for an explicitly documented never smoker; otherwise unavailable values remain `null`.
- Comorbidity fields use `1`, `0`, or `null`.
- Hour-level and multiple-duration expressions are flagged for review.
