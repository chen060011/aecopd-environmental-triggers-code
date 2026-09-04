# Restricted data boundary

The public code begins at either a county-by-day external exposure table or a governance-approved structured clinical-event table.

Do not commit:

- direct or indirect patient identifiers;
- free-text clinical notes;
- addresses, geocoding requests, coordinates derived from residences, or address-to-county crosswalks;
- manually annotated records or record-level model predictions;
- raw model prompts containing clinical text;
- API credentials, SSH settings, service tokens, or private endpoints;
- patient-level case-control, subgroup, or model-result tables;
- local paths or filenames that reveal the storage layout of restricted data.

Permitted repository content includes variable definitions, JSON schemas, validation logic, model formulas, generic command-line interfaces, and analysis code that writes aggregate result tables.

Unmentioned comorbidities remain missing unless the source record explicitly negates the condition. Missing smoking status is not classified as never smoking. Any implementation that changes these rules must be documented as a distinct analysis version.
