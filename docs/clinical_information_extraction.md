# Clinical information extraction

`python/01_extract_ehr_information.py` is the public, sample-free interface for the restricted EHR extraction stage. It does not contain records, prompts with real patients, credentials, or private endpoints.

## Extracted domains

The output schema contains:

- acute symptom duration in days;
- cough, sputum, dyspnea, wheeze, chest tightness, fever, fatigue, and nocturnal symptoms;
- smoking status, smoking years, cigarettes per day, cessation years, and pack-years;
- diabetes, hyperlipidemia, hypertension, coronary heart disease, heart failure, atrial fibrillation, stroke, anxiety/depression, osteoporosis, gastroesophageal reflux, asthma, emphysema, bronchiectasis, lung cancer, pulmonary embolism, renal insufficiency, hepatic insufficiency, and anemia.

The extractor only accepts explicitly documented information. Unmentioned symptoms and comorbidities remain `null`; they are not converted to negative findings. Smoking status is constrained to `never`, `former`, `current`, or `null`.

## Usage

```text
python python/01_extract_ehr_information.py \
  --input <deidentified-clinical-table> \
  --output <extracted-variables.csv> \
  --text-columns chief_complaint present_illness past_history \
  --retain-columns record_key event_date
```

The endpoint and model can be overridden with `--endpoint` and `--model`. The default endpoint is a loopback Ollama-compatible endpoint. No remote API credential is required by this repository.

## Governance boundary

The input table must be de-identified and approved for the analysis. Do not commit raw clinical text, model responses, manually adjudicated rows, patient identifiers, residence information, or record-level intermediate files. Use `04_evaluate_llm_extraction.py` only with an approved reference/prediction table stored outside the repository.
