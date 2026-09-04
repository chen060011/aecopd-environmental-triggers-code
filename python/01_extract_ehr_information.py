#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

import pandas as pd
import requests

SYMPTOMS = ["cough", "sputum", "dyspnea", "wheeze", "chest_tightness", "fever", "fatigue", "nocturnal_symptoms"]
COMORBIDITIES = [
    "diabetes", "hyperlipidemia", "hypertension", "coronary_heart_disease",
    "heart_failure", "atrial_fibrillation", "stroke", "anxiety_depression",
    "osteoporosis", "gastroesophageal_reflux", "asthma", "emphysema",
    "bronchiectasis", "lung_cancer", "pulmonary_embolism", "renal_insufficiency",
    "hepatic_insufficiency", "anemia",
]

SYSTEM_PROMPT = (
    "Extract only explicitly documented clinical information. Return one valid JSON object, "
    "without Markdown or explanation. Use null when the text is insufficient. Do not infer an "
    "unmentioned condition as absent."
)


def prompt_for(text: str) -> str:
    schema = {
        "duration_days": None,
        "symptoms": {name: None for name in SYMPTOMS},
        "smoking": {
            "status": None,
            "smoking_years": None,
            "cigarettes_per_day": None,
            "cessation_years": None,
            "pack_years": None,
        },
        "comorbidities": {name: None for name in COMORBIDITIES},
    }
    return (
        "Extract documented symptom duration, symptoms, smoking history, and comorbidities. "
        "Symptom values must be one of present, absent, mild, severe, or null. Smoking status "
        "must be never, former, current, or null. Comorbidity values must be 1, 0, or null, "
        "where 0 is allowed only when explicitly negated. Convert duration expressions to days "
        "and prioritise the duration of acute worsening. Required schema:\n"
        f"{json.dumps(schema, ensure_ascii=False)}\nClinical text:\n{text}"
    )


def single_json(content: str) -> dict[str, Any]:
    content = content.strip()
    if content.startswith("```"):
        content = content.strip("`")
        if content.startswith("json"):
            content = content[4:].lstrip()
    value = json.loads(content)
    if not isinstance(value, dict):
        raise ValueError("Model output is not a JSON object")
    return value


def validate(result: dict[str, Any]) -> dict[str, Any]:
    duration = result.get("duration_days")
    if duration is not None:
        duration = float(duration)
        if not 0 <= duration <= 365:
            duration = None
    symptoms = result.get("symptoms") if isinstance(result.get("symptoms"), dict) else {}
    smoking = result.get("smoking") if isinstance(result.get("smoking"), dict) else {}
    comorbidities = result.get("comorbidities") if isinstance(result.get("comorbidities"), dict) else {}
    symptom_allowed = {"present", "absent", "mild", "severe", None}
    status = smoking.get("status")
    if status not in {"never", "former", "current", None}:
        status = None
    clean = {
        "duration_days": duration,
        "symptoms": {name: symptoms.get(name) if symptoms.get(name) in symptom_allowed else None for name in SYMPTOMS},
        "smoking": {"status": status},
        "comorbidities": {name: comorbidities.get(name) if comorbidities.get(name) in {0, 1, None} else None for name in COMORBIDITIES},
    }
    for field in ("smoking_years", "cigarettes_per_day", "cessation_years", "pack_years"):
        value = smoking.get(field)
        try:
            clean["smoking"][field] = None if value is None else max(0.0, float(value))
        except (TypeError, ValueError):
            clean["smoking"][field] = None
    if status == "never":
        for field in ("smoking_years", "cigarettes_per_day", "cessation_years", "pack_years"):
            clean["smoking"][field] = 0.0
    return clean


def infer(endpoint: str, model: str, text: str, timeout: int, retries: int) -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt_for(text)},
        ],
        "format": "json",
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 2000},
    }
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            response = requests.post(endpoint, json=payload, timeout=timeout)
            response.raise_for_status()
            body = response.json()
            content = body.get("message", {}).get("content") or body.get("response")
            return validate(single_json(content))
        except Exception as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(5 * 1.5**attempt)
    raise RuntimeError("Extraction failed after retries") from last_error


def flatten(result: dict[str, Any]) -> dict[str, Any]:
    flat = {"duration_days": result["duration_days"]}
    flat.update({f"symptom_{k}": v for k, v in result["symptoms"].items()})
    flat.update({f"smoking_{k}": v for k, v in result["smoking"].items()})
    flat.update({f"comorbidity_{k}": v for k, v in result["comorbidities"].items()})
    return flat


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--text-columns", nargs="+", required=True)
    parser.add_argument("--retain-columns", nargs="*", default=[])
    parser.add_argument("--model", default="gemma3:27b-it-qat")
    parser.add_argument("--endpoint", default="http://127.0.0.1:11434/api/chat")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--retries", type=int, default=3)
    args = parser.parse_args()

    data = pd.read_excel(args.input) if args.input.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(args.input)
    missing = [column for column in args.text_columns if column not in data.columns]
    if missing:
        raise KeyError(f"Missing text columns: {missing}")
    missing_retain = [column for column in args.retain_columns if column not in data.columns]
    if missing_retain:
        raise KeyError(f"Missing retained columns: {missing_retain}")
    extracted = []
    for row in data[args.text_columns].fillna("").astype(str).itertuples(index=False, name=None):
        text = "\n".join(value.strip() for value in row if value.strip())
        extracted.append(flatten(infer(args.endpoint, args.model, text, args.timeout, args.retries)) if text else {})
    retained = data[args.retain_columns].reset_index(drop=True) if args.retain_columns else pd.DataFrame(index=data.index)
    result = pd.concat([retained, pd.DataFrame(extracted)], axis=1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(args.output, index=False)


if __name__ == "__main__":
    main()
