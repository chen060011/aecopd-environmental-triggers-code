#!/usr/bin/env python
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

COMORBIDITIES = [
    "diabetes", "hyperlipidemia", "hypertension", "coronary_heart_disease",
    "heart_failure", "atrial_fibrillation", "stroke", "anxiety_depression",
    "osteoporosis", "gastroesophageal_reflux", "asthma", "emphysema",
    "bronchiectasis", "lung_cancer", "pulmonary_embolism", "renal_insufficiency",
    "hepatic_insufficiency", "anemia",
]


def positive(series: pd.Series) -> pd.Series:
    values = series.astype(str).str.lower()
    result = pd.Series(pd.NA, index=series.index, dtype="boolean")
    result.loc[values.isin({"1", "true", "yes", "present", "severe"})] = True
    result.loc[values.isin({"0", "false", "no", "absent", "mild"})] = False
    return result


def symptom_dominant(data: pd.DataFrame) -> pd.Series:
    cough = positive(data["symptom_cough"])
    sputum = positive(data["symptom_sputum"])
    wheeze = positive(data["symptom_wheeze"])
    known = pd.concat([sputum, wheeze, cough], axis=1).notna().all(axis=1)
    result = pd.Series(pd.NA, index=data.index, dtype="object")
    result.loc[known] = "mixed_or_non_dominant"
    result[known & sputum & ~wheeze] = "sputum_dominant"
    result[known & wheeze & ~sputum] = "wheeze_dominant"
    result[known & cough & ~sputum & ~wheeze] = "cough_dominant"
    return result


def derive(data: pd.DataFrame, visit_date: str, duration: str, max_duration: int) -> pd.DataFrame:
    data = data.copy()
    data[visit_date] = pd.to_datetime(data[visit_date], errors="coerce").dt.normalize()
    data[duration] = pd.to_numeric(data[duration], errors="coerce")
    valid = data[duration].between(0, max_duration, inclusive="both") & data[visit_date].notna()
    data = data.loc[valid].copy()
    data["onset_date"] = data[visit_date] - pd.to_timedelta(data[duration], unit="D")
    data["event_date"] = data["onset_date"]

    if "age" in data:
        data["grp_age_3cat"] = pd.cut(data["age"], [-np.inf, 64, 74, np.inf], labels=["under_65", "65_74", "75_or_older"])
    if "sex" in data:
        data["grp_sex"] = data["sex"].astype(str).str.strip().str.lower().replace({"m": "male", "f": "female"})
    if "smoking_status" in data:
        smoking = data["smoking_status"].astype(str).str.lower().replace({"nan": "unknown", "none": "unknown"})
        data["grp_smoking_3cat"] = smoking.where(smoking.isin({"never", "former", "current"}), "unknown")
        data["grp_smoking_ever_never"] = smoking.map({"never": "never", "former": "ever", "current": "ever"})
    if "smoking_pack_years" in data:
        pack_years = pd.to_numeric(data["smoking_pack_years"], errors="coerce")
        data["grp_pack_years_4cat"] = pd.cut(pack_years, [-np.inf, 0, 20, 40, np.inf], right=False, labels=["0", "gt0_lt20", "20_lt40", "40_or_more"])

    available = [f"comorbidity_{name}" for name in COMORBIDITIES if f"comorbidity_{name}" in data]
    if available:
        raw = data[available].apply(pd.to_numeric, errors="coerce")
        burden = raw.eq(1).sum(axis=1).where(raw.notna().all(axis=1))
        data["grp_multimorbidity"] = pd.cut(burden, [-1, 0, 2, np.inf], labels=["0", "1_2", "3_or_more"])
    ccvc = [f"comorbidity_{name}" for name in ["hypertension", "coronary_heart_disease", "heart_failure", "atrial_fibrillation", "stroke"] if f"comorbidity_{name}" in data]
    metabolic = [f"comorbidity_{name}" for name in ["diabetes", "hyperlipidemia"] if f"comorbidity_{name}" in data]
    if ccvc:
        values = data[ccvc].apply(pd.to_numeric, errors="coerce")
        group = pd.Series(pd.NA, index=data.index, dtype="object")
        group.loc[values.eq(1).any(axis=1)] = "yes"
        group.loc[values.eq(0).all(axis=1)] = "no"
        data["grp_cv_comorb"] = group
    if metabolic:
        values = data[metabolic].apply(pd.to_numeric, errors="coerce")
        group = pd.Series(pd.NA, index=data.index, dtype="object")
        group.loc[values.eq(1).any(axis=1)] = "yes"
        group.loc[values.eq(0).all(axis=1)] = "no"
        data["grp_metabolic_comorb"] = group

    required_symptoms = {"symptom_cough", "symptom_sputum", "symptom_wheeze"}
    if required_symptoms.issubset(data.columns):
        data["grp_symptom_dominant_4cat"] = symptom_dominant(data)
    airway = [c for c in ["symptom_wheeze", "symptom_chest_tightness", "symptom_nocturnal_symptoms"] if c in data]
    if airway:
        values = pd.concat([positive(data[c]) for c in airway], axis=1)
        group = pd.Series(pd.NA, index=data.index, dtype="object")
        group.loc[values.eq(True).any(axis=1)] = "airway"
        group.loc[values.eq(False).all(axis=1)] = "non_airway"
        data["grp_airway"] = group
    for name, group in [("bronchiectasis", "grp_bx_grp"), ("asthma", "grp_asthma_grp"), ("emphysema", "grp_emphysema_grp")]:
        column = f"comorbidity_{name}"
        if column in data:
            values = pd.to_numeric(data[column], errors="coerce")
            derived = pd.Series(pd.NA, index=data.index, dtype="object")
            derived.loc[values.eq(1)] = "yes"
            derived.loc[values.eq(0)] = "no"
            data[group] = derived
    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--visit-date", default="visit_date")
    parser.add_argument("--duration", default="duration_days")
    parser.add_argument("--max-duration", type=int, default=14)
    args = parser.parse_args()
    data = pd.read_excel(args.input) if args.input.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(args.input)
    result = derive(data, args.visit_date, args.duration, args.max_duration)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(args.output, index=False)


if __name__ == "__main__":
    main()
