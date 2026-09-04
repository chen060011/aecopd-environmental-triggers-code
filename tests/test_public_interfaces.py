import importlib.util
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "python" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_onset_reconstruction_and_group_rules():
    module = load("onset", "02_reconstruct_onset_and_phenotypes.py")
    data = pd.DataFrame(
        {
            "visit_date": ["2024-01-10", "2024-01-10", "2024-01-10"],
            "duration_days": [3, 21, 2],
            "age": [64, 75, 70],
            "sex": ["M", "F", "F"],
            "smoking_status": ["never", "former", "unknown"],
            "smoking_pack_years": [0, 30, None],
            "symptom_cough": ["present", "absent", "present"],
            "symptom_sputum": ["absent", "present", "absent"],
            "symptom_wheeze": ["absent", "absent", "present"],
            "comorbidity_hypertension": [0, 1, None],
            "comorbidity_diabetes": [0, 0, 1],
        }
    )
    result = module.derive(data, "visit_date", "duration_days", 14)
    assert len(result) == 2
    assert result["onset_date"].dt.strftime("%Y-%m-%d").tolist() == ["2024-01-07", "2024-01-08"]
    assert result.loc[result["smoking_status"] == "never", "grp_smoking_ever_never"].iloc[0] == "never"
    assert "unknown" not in set(result["grp_smoking_ever_never"].dropna())
    assert set(result["grp_symptom_dominant_4cat"]) == {"cough_dominant", "wheeze_dominant"}


def test_weekly_influenza_expansion():
    module = load("external", "00_prepare_external_exposures.py")
    data = pd.DataFrame({"week_start": ["2024-01-01"], "value": [2]})
    source = ROOT / "tests" / "_weekly_input.csv"
    output = ROOT / "tests" / "_daily_output.csv"
    data.to_csv(source, index=False)
    try:
        module.expand_weekly_influenza(source, output, "week_start", None, False)
        result = pd.read_csv(output)
        assert len(result) == 7
        assert result["value"].tolist() == [2] * 7
    finally:
        source.unlink(missing_ok=True)
        output.unlink(missing_ok=True)


def test_ehr_extraction_validation_keeps_unmentioned_fields_missing():
    module = load("ehr_extract", "01_extract_ehr_information.py")
    clean = module.validate(
        {
            "duration_days": 3,
            "symptoms": {"cough": "present"},
            "smoking": {"status": None},
            "comorbidities": {"hypertension": None, "diabetes": 0},
        }
    )
    assert clean["symptoms"]["cough"] == "present"
    assert clean["symptoms"]["sputum"] is None
    assert clean["smoking"]["status"] is None
    assert clean["comorbidities"]["hypertension"] is None
    assert clean["comorbidities"]["diabetes"] == 0


def test_missing_clinical_fields_remain_unknown():
    module = load("onset_missing", "02_reconstruct_onset_and_phenotypes.py")
    data = pd.DataFrame(
        {
            "visit_date": ["2024-01-10"],
            "duration_days": [1],
            "symptom_cough": [None],
            "symptom_sputum": [None],
            "symptom_wheeze": [None],
            "comorbidity_hypertension": [None],
            "comorbidity_diabetes": [None],
            "comorbidity_bronchiectasis": [None],
        }
    )
    result = module.derive(data, "visit_date", "duration_days", 14)
    assert pd.isna(result.loc[0, "grp_symptom_dominant_4cat"])
    assert pd.isna(result.loc[0, "grp_cv_comorb"])
    assert pd.isna(result.loc[0, "grp_multimorbidity"])
    assert pd.isna(result.loc[0, "grp_bx_grp"])


def test_case_control_group_interface_preserves_missing_and_asthma():
    module = load("case_control", "03_prepare_case_control.py")
    data = pd.DataFrame(
        {
            "sym_cough": [1, None],
            "sym_sputum": [0, None],
            "sym_wheeze": [0, None],
            "sym_dyspnea": [0, None],
            "sym_chest": [0, None],
            "sym_fever": [0, None],
            "sym_fatigue": [0, None],
            "sym_night": [0, None],
            "com_htn": [0, None],
            "com_chd": [0, None],
            "com_hf": [0, None],
            "com_af": [0, None],
            "com_stroke": [0, None],
            "grp_asthma": [1, None],
        }
    )
    result = module.add_all_analysis_groups(data)
    assert result.loc[0, "grp_asthma_grp"] == "Yes"
    assert pd.isna(result.loc[1, "grp_asthma_grp"])
    assert result.loc[0, "grp_cv_comorb"] == "No"
    assert pd.isna(result.loc[1, "grp_cv_comorb"])
    assert result.loc[0, "grp_symptom_dominant_4cat"] == "Cough-dominant"
    assert pd.isna(result.loc[1, "grp_symptom_dominant_4cat"])

    partial = pd.DataFrame(
        {
            "sym_cough": [None],
            "sym_sputum": [1],
            "sym_wheeze": [0],
        }
    )
    partial_result = module.add_all_analysis_groups(partial)
    assert pd.isna(partial_result.loc[0, "grp_symptom_dominant_4cat"])
