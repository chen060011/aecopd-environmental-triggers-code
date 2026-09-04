import importlib.util
from pathlib import Path

import pandas as pd
import xarray as xr

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
    assert result.loc[result["smoking_pack_years"] == 0, "grp_pack_years_4cat"].iloc[0] == "0"


def test_onset_window_sensitivity_writes_all_caps(tmp_path):
    module = load("onset_sensitivity", "05_build_onset_window_sensitivity.py")
    data = pd.DataFrame({"visit_date": ["2024-01-10", "2024-01-10"], "duration_days": [14, 21]})
    audit = module.build_window_sets(data, tmp_path, "visit_date", "duration_days", [14, 21, 30])
    assert audit["included_records"].tolist() == [1, 2, 2]
    assert (tmp_path / "onset_window_audit.csv").exists()


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


def test_production_ehr_extraction_normalization_keeps_missing_values():
    module = load("ehr_extract", "01_extract_ehr_information.py")
    symptoms = module.normalize_symptoms(
        {
            "acute_exacerbation_duration": 3,
            "symptom_groups": {"咳嗽分组": "严重咳嗽"},
            "acute_exacerbation": 1,
            "has_copd_history": -1,
        }
    )
    smoking = module.normalize_smoking({"smoking_status": -1})
    comorbidities = module.normalize_comorbidities({"hypertension": -1, "diabetes": 0})
    assert symptoms["duration_days"] == 3
    assert symptoms["symptoms"]["cough"] == "severe"
    assert symptoms["symptoms"]["sputum"] is None
    assert symptoms["acute_exacerbation"] == 1
    assert symptoms["has_copd_history"] is None
    assert smoking["status"] is None
    assert comorbidities["hypertension"] is None
    assert comorbidities["diabetes"] == 0


def test_production_ehr_extraction_smoking_and_json_rules():
    module = load("ehr_rules", "01_extract_ehr_information.py")
    assert module.robust_json_parse('```json\n{"smoking_status": 0}\n```') == {"smoking_status": 0}
    never = module.normalize_smoking({"smoking_status": 0, "smoking_years": -1})
    assert never == {
        "status": "never",
        "smoking_years": 0.0,
        "cigarettes_per_day": 0.0,
        "cessation_years": 0.0,
        "pack_years": 0.0,
    }
    current = module.normalize_smoking(
        {"smoking_status": 2, "smoking_years": 30, "cigarettes_per_day": 20, "pack_years": -1}
    )
    assert current["status"] == "current"
    assert current["pack_years"] == 30
    assert len(module.COMORBIDITIES) == 16


def test_production_ehr_extraction_calls_each_task_once():
    module = load("ehr_calls", "01_extract_ehr_information.py")
    calls = []

    def fake_call(endpoint, model, prompt, timeout, retries):
        calls.append(prompt)
        if "symptom_groups" in prompt:
            return {
                "symptom_groups": {"咳嗽分组": "轻度咳嗽"},
                "acute_exacerbation": 1,
                "acute_exacerbation_duration": 2,
                "has_copd_history": 1,
            }
        if "smoking_status" in prompt:
            return {"smoking_status": 0}
        return {"diabetes": 1}

    module.call_ollama_generate = fake_call
    result = module.extract_record(
        "http://127.0.0.1:11434/api/generate",
        "gemma3:27b-it-qat",
        "咳嗽加重2天",
        "现病史文本",
        "既往史文本",
        "否认吸烟史",
    )
    assert len(calls) == 3
    assert result["duration_days"] == 2
    assert result["smoking"]["status"] == "never"
    assert result["comorbidities"]["diabetes"] == 1


def test_gemma_ollama_generate_contract():
    module = load("ehr_ollama", "01_extract_ehr_information.py")
    captured = {}

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"response": '{"smoking_status": 0}'}

    class FakeSession:
        trust_env = True

        def post(self, endpoint, json, timeout):
            captured.update({"endpoint": endpoint, "payload": json, "timeout": timeout})
            return FakeResponse()

    module.requests.Session = FakeSession
    result = module.call_ollama_generate(
        "http://127.0.0.1:11434/api/generate",
        "gemma3:27b-it-qat",
        "prompt",
    )
    assert result == {"smoking_status": 0}
    assert captured["payload"] == {
        "model": "gemma3:27b-it-qat",
        "prompt": "prompt",
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 2000},
    }
    assert captured["timeout"] == 120


def test_netcdf_daily_temperature_conversion(tmp_path):
    module = load("external_netcdf", "00_prepare_external_exposures.py")
    path = tmp_path / "cmfd.nc"
    times = pd.date_range("2024-01-01", periods=4, freq="12h")
    dataset = xr.Dataset(
        {"temp": (("time", "lat", "lon"), [[[273.15, 274.15], [275.15, 276.15]]] * 4)},
        coords={"time": times, "lat": [40.0, 41.0], "lon": [120.0, 121.0]},
    )
    dataset.to_netcdf(path)
    arrays = module.daily_netcdf_arrays(
        path, "temp", "time", "lat", "lon", "mean", True, False, None, None
    )
    assert len(arrays) == 2
    assert arrays[0][3].min() == 0
    assert arrays[0][3].max() == 3


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


def test_case_control_defaults_and_airway_completeness():
    module = load("case_control_defaults", "03_prepare_case_control.py")
    assert [item["strategy"] for item in module.CONTROL_CONFIGS] == [
        "monthly_weekday", "symmetric_weekday"
    ]
    assert module.LAGS == list(range(22))
    assert module.FLU_INTERPOLATE_TO_DAILY is True
    data = pd.DataFrame(
        {
            "sym_wheeze": [1, 1],
            "sym_chest": [0, None],
            "sym_night": [None, None],
            "grp_smoking_ever_never": ["Never", "Never"],
        }
    )
    result = module.add_all_analysis_groups(data)
    assert result.loc[0, "grp_airway"] == "Airway-reactive"
    assert pd.isna(result.loc[1, "grp_airway"])
    assert result.loc[0, "grp_airway_strict"] == "Non-airway-reactive-strict"
