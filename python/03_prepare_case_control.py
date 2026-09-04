import calendar
import concurrent.futures
import hashlib
import os
import re
import time
import warnings
from datetime import timedelta
from pathlib import Path

import chinese_calendar as cc
import numpy as np
import pandas as pd
from tqdm import tqdm

warnings.filterwarnings("ignore")

TEMPERATURE_FILE = Path(os.getenv("AECOPD_TEMPERATURE_FILE", "data/temperature.csv"))

POLLUTANT_FILES = {name: Path(os.getenv(f"AECOPD_{name}_FILE", f"data/{name.lower()}.csv")) for name in ["PM25", "PM10", "SO2", "NO2", "CO", "O3"]}

HUMIDITY_FILES = {name: Path(os.getenv(f"AECOPD_{name}_FILE", f"data/{name.lower()}.csv")) for name in ["RHUM", "SHUM"]}

PRESSURE_FILES = {"PRES": Path(os.getenv("AECOPD_PRES_FILE", "data/pres.csv"))}

INFLUENZA_FILE = Path(os.getenv("AECOPD_INFLUENZA_FILE", "data/influenza.csv"))
PAT_FILE = Path(os.getenv("AECOPD_PATIENT_FILE", "data/analysis_input.csv"))

OUTPUT_DIR = Path(os.getenv("AECOPD_OUTPUT_DIR", "results"))
OUTPUT_PREFIX = os.getenv("AECOPD_OUTPUT_PREFIX", "case_control")
EVENT_DATE_SOURCE = os.getenv("AECOPD_EVENT_DATE_COL", "onset_date")

CONTROL_CONFIGS = [
    {
        "strategy": "monthly_weekday",
        "direction": "both",
        "max_controls": None,
        "symmetric_weeks": [1, 2, 3],
    },
    {
        "strategy": "symmetric_weekday",
        "direction": "both",
        "max_controls": None,
        "symmetric_weeks": [1, 2, 3],
    },
]

THREAD_NUM = 8
LAGS = list(range(int(os.getenv("AECOPD_MAX_LAG", "21")) + 1))
FLU_REGION = "north"
CLIP_METEO_BY_PATIENT_WINDOW = False

FLU_INTERPOLATE_TO_DAILY = True
FLU_INTERP_BOUNDARY = "clip"

EXTREME_TEMP_METHOD = "percentile"
EXTREME_HEAT_PERCENTILE = 95
EXTREME_COLD_PERCENTILE = 5
EXTREME_TEMP_BY_COUNTY = True

PATIENT_INFO_COLS = [
    "patient_id", "origin_id", "visit_seq", "county", "matched_name",
    "年龄", "性别", "咳嗽分组", "咳痰分组", "呼吸困难分组", "喘息分组", "肺气肿",
    "胸闷分组", "发热分组", "乏力分组", "夜间症状分组", "急性加重",
    "急性加重天数", "COPD病史", "吸烟状态", "吸烟年限(年)", "每日吸烟量(支)",
    "戒烟年限(年)", "包年数", "糖尿病", "高血压", "高血脂", "冠心病",
    "心力衰竭", "心房颤动", "脑卒中", "焦虑抑郁", "骨质疏松", "胃食管反流病",
    "支气管扩张", "肺癌", "肺栓塞", "肾功能不全", "肝功能不全", "贫血", "哮喘",
    "hospital_code",
    "visit_date", "onset_date", "事件日"
]

PHENOTYPE_INFO_COLS = [
    "smoking_status_std",
    "smoking_3cat",
    "smoking_pheno",
    "current_smoker_flag",
    "smoking_years_num",
    "cig_per_day_num",
    "quit_years_num",
    "pack_years_num",
    "pack_years_group",
    "fever_present",
    "sputum_present",
    "infective_score",
    "infective_pheno",
    "infective_pheno_strict",
    "wheeze_present",
    "chest_tightness_present",
    "night_symptom_present",
    "airway_reactive_score",
    "airway_reactive_pheno",
    "airway_reactive_pheno_strict",
    "cough_present",
    "event_pheno_4cat",
]

ANALYSIS_GROUP_COLS = [
    "grp_age_3cat",
    "grp_sex",
    "grp_cv_comorb",
    "grp_multimorbidity",
    "grp_metabolic_comorb",
    "grp_smoking_3cat",
    "grp_smoking_ever_never",
    "grp_pack_years_4cat",
    "grp_symptom_dominant_4cat",
    "grp_airway",
    "grp_airway_strict",
    "grp_never_smoker_airway",
    "grp_bx_grp",
    "grp_asthma_grp",
    "grp_emphysema_grp",
]



VAR_LABEL_MAP = {
    "PM25": "PM2.5 (µg/m³)",
    "PM10": "PM10 (µg/m³)",
    "NO2": "NO₂ (µg/m³)",
    "SO2": "SO₂ (µg/m³)",
    "CO": "CO (mg/m³)",
    "O3": "O₃ (µg/m³)",

    "Tavg": "Mean temperature (°C)",
    "Tmax": "Maximum temperature (°C)",
    "Tmin": "Minimum temperature (°C)",
    "EHT": "Extreme high temperature day",
    "ELT": "Extreme low temperature day",

    "RHUM": "Relative humidity (%)",
    "SHUM": "Specific humidity (kg/kg)",
    "PRES": "Atmospheric pressure (hPa)",

    "检测数": "Influenza tests",
    "阳性数": "Positive tests",
    "阳性率": "Positivity rate",

    "A型占比": "Influenza A (%)",
    "B型占比": "Influenza B (%)",
    "A_H3N2占比": "A(H3N2) (%)",
    "A_H1N1占比": "A(H1N1)pdm09 (%)",
    "A_unsubtyped占比": "A unsubtyped (%)",
    "B_未分系占比": "B lineage unclassified (%)",
    "B_Victoria占比": "B/Victoria (%)",
    "B_Yamagata占比": "B/Yamagata (%)",

    "A型数量": "Influenza A detections",
    "B型数量": "Influenza B detections",
    "A_H3N2数量": "A(H3N2) detections",
    "A_H1N1数量": "A(H1N1)pdm09 detections",
    "A_unsubtyped数量": "A unsubtyped detections",
    "B_未分系数量": "B lineage unclassified detections",
    "B_Victoria数量": "B/Victoria detections",
    "B_Yamagata数量": "B/Yamagata detections",
}

ANALYSIS_VARS = list(VAR_LABEL_MAP.keys())

POLLUTANT_VARS = ["PM25", "PM10", "NO2", "SO2", "CO", "O3"]
TEMPERATURE_BASE_VARS = ["Tavg", "Tmax", "Tmin"]
TEMPERATURE_VARS = ["Tavg", "Tmax", "Tmin", "EHT", "ELT"]
HUMIDITY_VARS = ["RHUM", "SHUM"]
PRESSURE_VARS = ["PRES"]
INFLUENZA_VARS = [
    "检测数", "阳性数", "阳性率",
    "A型占比", "B型占比",
    "A_H3N2占比", "A_H1N1占比", "A_unsubtyped占比",
    "B_未分系占比", "B_Victoria占比", "B_Yamagata占比",
    "A型数量", "B型数量",
    "A_H3N2数量", "A_H1N1数量", "A_unsubtyped数量",
    "B_未分系数量", "B_Victoria数量", "B_Yamagata数量",
]

def _normalize_date_series(s: pd.Series) -> pd.Series:
    s = pd.to_datetime(s, errors="coerce")
    return s.dt.normalize()

def _normalize_date_col(df: pd.DataFrame, col: str) -> pd.DataFrame:
    if col in df.columns:
        df[col] = _normalize_date_series(df[col])
    return df

def _flatten_columns(df: pd.DataFrame) -> pd.DataFrame:
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [
            "_".join([str(x) for x in tup if str(x) != "nan"]).strip()
            for tup in df.columns
        ]
    df.columns = [str(c).strip() for c in df.columns]
    return df

def _dedupe_columns(df: pd.DataFrame, keep="first") -> pd.DataFrame:
    if df.columns.duplicated().any():
        dup = df.columns[df.columns.duplicated()].tolist()
        print(f"    [警告] 发现重复列名，将保留{keep}列，其余丢弃: {dup}")
        df = df.loc[:, ~df.columns.duplicated(keep=keep)]
    return df

def _pick_county_col(df: pd.DataFrame) -> str:
    candidates = []
    for c in df.columns:
        sc = str(c).strip()
        sl = sc.lower()
        if sl in ["county_name", "county", "countyname"]:
            candidates.append(c)
            continue
        if any(k in sl for k in ["county", "cnty", "admin"]):
            candidates.append(c)
            continue
        if any(k in sc for k in ["区县", "区/县", "区县名", "县", "地区", "行政区", "区名", "县名"]):
            candidates.append(c)
            continue

    if candidates:
        for c in candidates:
            if str(c).lower() == "county_name":
                return c
        return candidates[0]

    return df.columns[0]

def _ensure_single_id_col(df: pd.DataFrame, id_col_name: str) -> pd.DataFrame:
    if id_col_name in df.columns:
        obj = df[id_col_name]
        if isinstance(obj, pd.DataFrame):
            df[id_col_name] = obj.iloc[:, 0]
    return df

def _parse_yyyymmdd_from_col(col) -> pd.Timestamp:
    s = str(col).strip().replace(".0", "")
    m = re.search(r"(\d{8})", s)
    if not m:
        return pd.NaT
    return pd.to_datetime(m.group(1), format="%Y%m%d", errors="coerce")

def collapse_meteo_unique(meteo_df: pd.DataFrame) -> pd.DataFrame:
    meteo_df = meteo_df.copy()
    meteo_df = _normalize_date_col(meteo_df, "date")

    key_cols = ["county_name", "date"]
    for k in key_cols:
        if k not in meteo_df.columns:
            raise ValueError(f"meteo_df缺少关键列: {k}")

    numeric_cols = [
        c for c in meteo_df.columns
        if c not in key_cols and pd.api.types.is_numeric_dtype(meteo_df[c])
    ]

    before = len(meteo_df)
    collapsed = (
        meteo_df[key_cols + numeric_cols]
        .groupby(key_cols, as_index=False)
        .mean(numeric_only=True)
    )
    after = len(collapsed)

    print(f"    [压缩] meteo_df 行数: {before:,} -> {after:,}（county_name+date唯一）")
    return collapsed

def _find_first_existing_col(df: pd.DataFrame, candidates):
    for c in candidates:
        if c in df.columns:
            return c
    return None

def get_calendar_flags(date_val) -> dict:
    dt = pd.to_datetime(date_val, errors="coerce")
    if pd.isna(dt):
        return {
            "public_holiday": np.nan,
            "is_workday": np.nan,
            "is_weekend": np.nan,
        }

    try:
        d = dt.date()
        return {
            "public_holiday": int(cc.is_holiday(d)),
            "is_workday": int(cc.is_workday(d)),
            "is_weekend": int(dt.weekday() >= 5),
        }
    except Exception:  # noqa: BLE001
        return {
            "public_holiday": np.nan,
            "is_workday": np.nan,
            "is_weekend": np.nan,
        }

def get_needed_meteo_window(min_case: pd.Timestamp,
                            max_case: pd.Timestamp,
                            control_configs: list,
                            lags: list[int]) -> tuple[pd.Timestamp, pd.Timestamp]:
    min_case = pd.to_datetime(min_case).normalize()
    max_case = pd.to_datetime(max_case).normalize()
    max_lag = max(lags) if lags else 0

    back_pad = max_lag
    forward_pad = max_lag

    for cfg in control_configs:
        strategy = cfg.get("strategy", "monthly_weekday")
        if strategy == "monthly_weekday":
            back_pad = max(back_pad, max_lag + 31)
            forward_pad = max(forward_pad, max_lag + 31)
        elif strategy == "symmetric_weekday":
            weeks = cfg.get("symmetric_weeks", [1, 2, 3]) or [1, 2, 3]
            max_weeks = max([int(w) for w in weeks if pd.notna(w)] + [0])
            extra_days = max_weeks * 7
            back_pad = max(back_pad, max_lag + extra_days)
            forward_pad = max(forward_pad, max_lag + extra_days)

    meteo_min = (min_case - pd.Timedelta(days=back_pad)).normalize()
    meteo_max = (max_case + pd.Timedelta(days=forward_pad)).normalize()
    return meteo_min, meteo_max

def add_extreme_temperature_flags(
    temp_df: pd.DataFrame,
    method: str = "percentile",
    heat_percentile: float = 95,
    cold_percentile: float = 5,
    by_county: bool = True,
) -> pd.DataFrame:
    df = temp_df.copy()
    df = _normalize_date_col(df, "date")

    need_cols = ["county_name", "date", "Tmax", "Tmin"]
    for c in need_cols:
        if c not in df.columns:
            raise ValueError(f"温度数据缺少必要列: {c}")

    if method != "percentile":
        raise ValueError("当前脚本按用户要求固定使用 percentile 分位数法")

    def _safe_percentile(x, q):
        x = pd.to_numeric(x, errors="coerce").dropna()
        if x.shape[0] == 0:
            return np.nan
        return float(np.nanpercentile(x, q))

    if by_county:
        thresh = (
            df.groupby("county_name")
            .agg(
                heat_thresh=("Tmax", lambda x: _safe_percentile(x, heat_percentile)),
                cold_thresh=("Tmin", lambda x: _safe_percentile(x, cold_percentile)),
            )
            .reset_index()
        )
        df = df.merge(thresh, on="county_name", how="left")
    else:
        heat_thresh = _safe_percentile(df["Tmax"], heat_percentile)
        cold_thresh = _safe_percentile(df["Tmin"], cold_percentile)
        df["heat_thresh"] = heat_thresh
        df["cold_thresh"] = cold_thresh

    df["EHT"] = np.where(
        df["Tmax"].notna() & df["heat_thresh"].notna() & (df["Tmax"] >= df["heat_thresh"]),
        1, 0
    )
    df["ELT"] = np.where(
        df["Tmin"].notna() & df["cold_thresh"].notna() & (df["Tmin"] <= df["cold_thresh"]),
        1, 0
    )

    df["EHT"] = pd.to_numeric(df["EHT"], errors="coerce")
    df["ELT"] = pd.to_numeric(df["ELT"], errors="coerce")

    print("    极端温度定义完成（分位数法）")
    if by_county:
        print(f"    EHT = Tmax >= 各区县P{heat_percentile}")
        print(f"    ELT = Tmin <= 各区县P{cold_percentile}")
    else:
        print(f"    EHT = Tmax >= 全部样本P{heat_percentile}")
        print(f"    ELT = Tmin <= 全部样本P{cold_percentile}")

    keep_cols = ["county_name", "date", "Tavg", "Tmax", "Tmin", "EHT", "ELT", "heat_thresh", "cold_thresh"]
    keep_cols = [c for c in keep_cols if c in df.columns]
    return df[keep_cols].copy()

def _clean_text_series(s: pd.Series) -> pd.Series:
    return s.astype(str).str.strip().replace({
        "nan": np.nan,
        "NaN": np.nan,
        "None": np.nan,
        "": np.nan
    })

def _std_smoking_status(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    mapping = {
        "从不吸烟": "Never",
        "已戒烟": "Former",
        "当前吸烟": "Current",
        "信息缺失无法判断": "Unknown",
    }
    out = s.map(mapping)
    out = out.fillna("Unknown")
    return out

def _is_present_severe(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    mapping = {
        "有/严重": 1.0,
        "无/轻度": 0.0,
        "信息缺失": np.nan,
        "分析失败": np.nan,
    }
    return pd.to_numeric(s.map(mapping), errors="coerce")

def _to_numeric_with_missing(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    s = s.replace({
        "信息缺失": np.nan,
        "信息缺失无法判断": np.nan,
        "分析失败": np.nan,
    })
    return pd.to_numeric(s, errors="coerce")

def _binary_present_loose(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    mapping = {
        "有/严重": 1.0,
        "无/轻度": 0.0,
        "信息缺失": np.nan,
        "信息缺失无法判断": np.nan,
        "分析失败": np.nan,
    }
    return pd.to_numeric(s.map(mapping), errors="coerce")

def _binary_yes_no_loose(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    mapping = {
        "有": 1.0,
        "无": 0.0,
        "是": 1.0,
        "否": 0.0,
        "1": 1.0,
        "0": 0.0,
        "信息缺失": np.nan,
        "信息缺失无法判断": np.nan,
        "分析失败": np.nan,
    }
    return pd.to_numeric(s.map(mapping), errors="coerce")

def _safe_numeric(series: pd.Series) -> pd.Series:
    s = _clean_text_series(series)
    s = s.replace({
        "信息缺失": np.nan,
        "信息缺失无法判断": np.nan,
        "分析失败": np.nan,
    })
    return pd.to_numeric(s, errors="coerce")

def _label_from_binary(series: pd.Series, yes_label="Yes", no_label="No") -> pd.Series:
    out = pd.Series(pd.NA, index=series.index, dtype="object")
    out.loc[series == 1] = yes_label
    out.loc[series == 0] = no_label
    return out

def _group_any_present(df: pd.DataFrame, columns: list[str]) -> pd.Series:
    values = df[columns].apply(pd.to_numeric, errors="coerce")
    out = pd.Series(pd.NA, index=df.index, dtype="object")
    out.loc[values.eq(1).any(axis=1)] = "Yes"
    out.loc[values.eq(0).all(axis=1)] = "No"
    return out

def _cut_age_3cat(series: pd.Series) -> pd.Series:
    x = _safe_numeric(series)
    out = pd.Series(pd.NA, index=series.index, dtype="object")
    out.loc[x < 65] = "<65"
    out.loc[(x >= 65) & (x < 75)] = "65-74"
    out.loc[x >= 75] = ">=75"
    return out

def _cut_ae_days(series: pd.Series) -> pd.Series:
    x = _safe_numeric(series)
    out = pd.Series(pd.NA, index=series.index, dtype="object")
    out.loc[x <= 3] = "<=3"
    out.loc[(x > 3) & (x <= 7)] = "4-7"
    out.loc[x > 7] = ">7"
    return out

def _cut_pack_years_4cat(series: pd.Series) -> pd.Series:
    x = _safe_numeric(series)
    out = pd.Series(pd.NA, index=series.index, dtype="object")
    out.loc[x == 0] = "0"
    out.loc[(x > 0) & (x < 20)] = ">0-<20"
    out.loc[(x >= 20) & (x < 40)] = "20-<40"
    out.loc[x >= 40] = ">=40"
    return out


def add_ai_phenotypes(df_in: pd.DataFrame) -> pd.DataFrame:
    print("\n4.1 添加 AI-derived phenotype（按真实分布）")
    df = df_in.copy()

    if "吸烟状态" in df.columns:
        df["smoking_status_std"] = _std_smoking_status(df["吸烟状态"])
    else:
        df["smoking_status_std"] = "Unknown"

    df["smoking_3cat"] = df["smoking_status_std"]

    df["smoking_pheno"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[df["smoking_status_std"] == "Never", "smoking_pheno"] = "Never smoker"
    df.loc[df["smoking_status_std"].isin(["Former", "Current"]), "smoking_pheno"] = "Ever smoker"

    current_flag = pd.Series(np.nan, index=df.index, dtype="float")
    current_flag.loc[df["smoking_status_std"] == "Current"] = 1
    current_flag.loc[df["smoking_status_std"].isin(["Never", "Former"])] = 0
    df["current_smoker_flag"] = current_flag

    df["smoking_years_num"] = _to_numeric_with_missing(df["吸烟年限(年)"]) if "吸烟年限(年)" in df.columns else np.nan
    df["cig_per_day_num"] = _to_numeric_with_missing(df["每日吸烟量(支)"]) if "每日吸烟量(支)" in df.columns else np.nan
    df["quit_years_num"] = _to_numeric_with_missing(df["戒烟年限(年)"]) if "戒烟年限(年)" in df.columns else np.nan
    df["pack_years_num"] = _to_numeric_with_missing(df["包年数"]) if "包年数" in df.columns else np.nan

    df["pack_years_group"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[df["pack_years_num"] == 0, "pack_years_group"] = "0"
    df.loc[(df["pack_years_num"] > 0) & (df["pack_years_num"] < 20), "pack_years_group"] = ">0 to <20"
    df.loc[df["pack_years_num"] >= 20, "pack_years_group"] = ">=20"

    cough_col = "咳嗽分组"
    fever_col = "发热分组"
    sputum_col = "咳痰分组"

    df["cough_present"] = _is_present_severe(df[cough_col]) if cough_col in df.columns else pd.Series(np.nan, index=df.index)
    df["fever_present"] = _is_present_severe(df[fever_col]) if fever_col in df.columns else pd.Series(np.nan, index=df.index)
    df["sputum_present"] = _is_present_severe(df[sputum_col]) if sputum_col in df.columns else pd.Series(np.nan, index=df.index)

    infective_sum = df[["fever_present", "sputum_present"]].sum(axis=1, min_count=1)
    infective_nonmissing_n = df[["fever_present", "sputum_present"]].notna().sum(axis=1)

    df["infective_score"] = np.where(infective_nonmissing_n > 0, infective_sum, np.nan)

    df["infective_pheno"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[infective_nonmissing_n > 0, "infective_pheno"] = "Non-infective"
    df.loc[(infective_nonmissing_n > 0) & (infective_sum >= 1), "infective_pheno"] = "Infective-predominant"

    df["infective_pheno_strict"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[infective_nonmissing_n >= 2, "infective_pheno_strict"] = "Non-infective"
    df.loc[(infective_nonmissing_n >= 2) & (infective_sum == 2), "infective_pheno_strict"] = "Infective-predominant"

    wheeze_col = "喘息分组"
    chest_col = "胸闷分组"
    night_col = "夜间症状分组"

    df["wheeze_present"] = _is_present_severe(df[wheeze_col]) if wheeze_col in df.columns else pd.Series(np.nan, index=df.index)
    df["chest_tightness_present"] = _is_present_severe(df[chest_col]) if chest_col in df.columns else pd.Series(np.nan, index=df.index)
    df["night_symptom_present"] = _is_present_severe(df[night_col]) if night_col in df.columns else pd.Series(np.nan, index=df.index)

    airway_sum = df[["wheeze_present", "chest_tightness_present", "night_symptom_present"]].sum(axis=1, min_count=2)
    airway_nonmissing_n = df[["wheeze_present", "chest_tightness_present", "night_symptom_present"]].notna().sum(axis=1)

    df["airway_reactive_score"] = np.where(airway_nonmissing_n >= 2, airway_sum, np.nan)

    df["airway_reactive_pheno"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[airway_nonmissing_n >= 2, "airway_reactive_pheno"] = "Non-airway-reactive"
    df.loc[(airway_nonmissing_n >= 2) & (airway_sum >= 1), "airway_reactive_pheno"] = "Airway-reactive"

    df["airway_reactive_pheno_strict"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[airway_nonmissing_n >= 2, "airway_reactive_pheno_strict"] = "Non-airway-reactive"
    df.loc[(airway_nonmissing_n >= 2) & (airway_sum >= 2), "airway_reactive_pheno_strict"] = "Airway-reactive"

    df["event_pheno_4cat"] = pd.Series(pd.NA, index=df.index, dtype="object")
    df.loc[
        (df["infective_pheno"] == "Infective-predominant") &
        (df["airway_reactive_pheno"] == "Airway-reactive"),
        "event_pheno_4cat"
    ] = "Mixed infective + airway-reactive"

    df.loc[
        (df["infective_pheno"] == "Infective-predominant") &
        (df["airway_reactive_pheno"] == "Non-airway-reactive"),
        "event_pheno_4cat"
    ] = "Infective-predominant only"

    df.loc[
        (df["infective_pheno"] == "Non-infective") &
        (df["airway_reactive_pheno"] == "Airway-reactive"),
        "event_pheno_4cat"
    ] = "Airway-reactive only"

    df.loc[
        (df["infective_pheno"] == "Non-infective") &
        (df["airway_reactive_pheno"] == "Non-airway-reactive"),
        "event_pheno_4cat"
    ] = "Neither phenotype"

    return df

def add_all_analysis_groups(df_in: pd.DataFrame) -> pd.DataFrame:
    print("\n4.2 添加全部分析分组（A-E）")
    df = df_in.copy()

    if "年龄" in df.columns:
        df["grp_age_3cat"] = _cut_age_3cat(df["年龄"])

    if "性别" in df.columns:
        s = _clean_text_series(df["性别"])
        out = pd.Series(pd.NA, index=df.index, dtype="object")
        out.loc[s.str.contains("男", na=False)] = "Male"
        out.loc[s.str.contains("女", na=False)] = "Female"
        df["grp_sex"] = out

    if "吸烟状态" in df.columns:
        df["grp_smoking_3cat"] = _std_smoking_status(df["吸烟状态"])

        ever_never = pd.Series(pd.NA, index=df.index, dtype="object")
        ever_never.loc[df["grp_smoking_3cat"] == "Never"] = "Never"
        ever_never.loc[df["grp_smoking_3cat"].isin(["Former", "Current"])] = "Ever"
        df["grp_smoking_ever_never"] = ever_never

    if "包年数" in df.columns:
        df["grp_pack_years_4cat"] = _cut_pack_years_4cat(df["包年数"])

    symptom_map = {
        "咳嗽分组": "sym_cough",
        "咳痰分组": "sym_sputum",
        "呼吸困难分组": "sym_dyspnea",
        "喘息分组": "sym_wheeze",
        "胸闷分组": "sym_chest",
        "发热分组": "sym_fever",
        "乏力分组": "sym_fatigue",
        "夜间症状分组": "sym_night",
    }

    for raw_col, new_col in symptom_map.items():
        if raw_col in df.columns:
            df[new_col] = _binary_present_loose(df[raw_col])

    if "sym_night" in df.columns:
        grp = pd.Series(pd.NA, index=df.index, dtype="object")
        grp.loc[df["sym_night"] == 1] = "Yes"
        grp.loc[df["sym_night"] == 0] = "No"
        df["grp_night_symptom_grp"] = grp

    symptom_cols = [c for c in [
        "sym_cough", "sym_sputum", "sym_dyspnea", "sym_wheeze",
        "sym_chest", "sym_fever", "sym_fatigue", "sym_night"
    ] if c in df.columns]

    if symptom_cols:
        df["grp_symptom_count"] = df[symptom_cols].sum(axis=1, min_count=len(symptom_cols))
        burden = pd.Series(pd.NA, index=df.index, dtype="object")
        burden.loc[df["grp_symptom_count"] <= 1] = "0-1"
        burden.loc[(df["grp_symptom_count"] >= 2) & (df["grp_symptom_count"] <= 3)] = "2-3"
        burden.loc[df["grp_symptom_count"] >= 4] = ">=4"
        df["grp_symptom_burden"] = burden

    if {"sym_fever", "sym_sputum"}.issubset(df.columns):
        infective_known = df[["sym_fever", "sym_sputum"]].notna().all(axis=1)
        infective = infective_known & ((df["sym_fever"] == 1) | (df["sym_sputum"] == 1))
        infective_score = df[["sym_fever", "sym_sputum"]].sum(axis=1, min_count=2)

        infective_grp = pd.Series(pd.NA, index=df.index, dtype="object")
        infective_grp.loc[infective] = "Infective"
        infective_grp.loc[infective_known & ~infective] = "Non-infective"
        df["grp_infective"] = infective_grp

        infective_3cat = pd.Series(pd.NA, index=df.index, dtype="object")
        infective_3cat.loc[infective_score == 0] = "0"
        infective_3cat.loc[infective_score == 1] = "1"
        infective_3cat.loc[infective_score == 2] = "2"
        df["grp_infective_3cat"] = infective_3cat

    if {"sym_wheeze", "sym_chest", "sym_night"}.issubset(df.columns):
        airway_known = df[["sym_wheeze", "sym_chest", "sym_night"]].notna().sum(axis=1) >= 2
        airway = airway_known & (
            (df["sym_wheeze"] == 1) |
            (df["sym_chest"] == 1) |
            (df["sym_night"] == 1)
        )
        airway_score = df[["sym_wheeze", "sym_chest", "sym_night"]].sum(axis=1, min_count=2)

        airway_grp = pd.Series(pd.NA, index=df.index, dtype="object")
        airway_grp.loc[airway] = "Airway-reactive"
        airway_grp.loc[airway_known & ~airway] = "Non-airway-reactive"
        df["grp_airway"] = airway_grp

        strict = pd.Series(pd.NA, index=df.index, dtype="object")
        strict.loc[airway_known & airway_score.ge(2)] = "Airway-reactive-strict"
        strict.loc[airway_known & airway_score.lt(2)] = "Non-airway-reactive-strict"
        df["grp_airway_strict"] = strict

        airway_score_grp = pd.Series(pd.NA, index=df.index, dtype="object")
        airway_score_grp.loc[airway_score == 0] = "0"
        airway_score_grp.loc[airway_score == 1] = "1"
        airway_score_grp.loc[airway_score == 2] = "2"
        airway_score_grp.loc[airway_score >= 3] = ">=3"
        df["grp_airway_4cat_score"] = airway_score_grp

    if {"grp_infective", "grp_airway"}.issubset(df.columns):
        event4 = pd.Series(pd.NA, index=df.index, dtype="object")
        event4.loc[
            (df["grp_infective"] == "Infective") &
            (df["grp_airway"] == "Airway-reactive")
        ] = "Mixed"
        event4.loc[
            (df["grp_infective"] == "Infective") &
            (df["grp_airway"] == "Non-airway-reactive")
        ] = "Infective only"
        event4.loc[
            (df["grp_infective"] == "Non-infective") &
            (df["grp_airway"] == "Airway-reactive")
        ] = "Airway only"
        event4.loc[
            (df["grp_infective"] == "Non-infective") &
            (df["grp_airway"] == "Non-airway-reactive")
        ] = "Neither"
        df["grp_event_4cat"] = event4

    if {"sym_dyspnea", "grp_infective"}.issubset(df.columns):
        grp = pd.Series(pd.NA, index=df.index, dtype="object")
        grp.loc[
            (df["sym_dyspnea"] == 1) &
            (df["grp_infective"] == "Non-infective")
        ] = "Dyspnea-dominant"
        grp.loc[df["grp_infective"].notna() & ~(
            (df["sym_dyspnea"] == 1) & (df["grp_infective"] == "Non-infective")
        )] = "Other"
        df["grp_dyspnea_dominant"] = grp

    if {"sym_cough", "sym_sputum"}.issubset(df.columns):
        grp = pd.Series(pd.NA, index=df.index, dtype="object")
        grp.loc[
            (df["sym_cough"] == 1) & (df["sym_sputum"] == 1)
        ] = "Yes"
        complete = df[["sym_cough", "sym_sputum"]].notna().all(axis=1)
        grp.loc[complete & ~(
            (df["sym_cough"] == 1) & (df["sym_sputum"] == 1)
        )] = "No"
        df["grp_chronic_bronchitic_proxy"] = grp

    if {"sym_fever", "sym_fatigue"}.issubset(df.columns):
        grp = pd.Series(pd.NA, index=df.index, dtype="object")
        grp.loc[
            (df["sym_fever"] == 1) | (df["sym_fatigue"] == 1)
        ] = "Yes"
        complete = df[["sym_fever", "sym_fatigue"]].notna().all(axis=1)
        grp.loc[complete & ~(
            (df["sym_fever"] == 1) | (df["sym_fatigue"] == 1)
        )] = "No"
        df["grp_systemic_proxy"] = grp

    simple_binary_cols = {
        "肺气肿": "grp_emphysema",
        "急性加重": "grp_ae_flag",
        "COPD病史": "grp_copd_history",
        "哮喘": "grp_asthma",
        "糖尿病": "com_dm",
        "高血压": "com_htn",
        "高血脂": "com_hld",
        "冠心病": "com_chd",
        "心力衰竭": "com_hf",
        "心房颤动": "com_af",
        "脑卒中": "com_stroke",
        "焦虑抑郁": "com_anxdep",
        "骨质疏松": "com_osteo",
        "胃食管反流病": "com_gerd",
        "支气管扩张": "com_bx",
        "肺癌": "com_lungca",
        "肺栓塞": "com_pe",
        "肾功能不全": "com_renal",
        "肝功能不全": "com_hepatic",
        "贫血": "com_anemia",
    }

    for raw_col, new_col in simple_binary_cols.items():
        if raw_col in df.columns:
            tmp = _binary_present_loose(df[raw_col])
            tmp2 = _binary_yes_no_loose(df[raw_col])
            out = pd.Series(tmp, index=df.index, dtype="float")
            out = out.where(~out.isna(), tmp2)
            df[new_col] = out
            df[new_col + "_grp"] = _label_from_binary(out, "Yes", "No")

    if "com_stroke" in df.columns:
        df["grp_stroke_grp"] = _label_from_binary(df["com_stroke"], "Yes", "No")

    if "grp_asthma" in df.columns:
        arh = pd.Series(pd.NA, index=df.index, dtype="object")
        arh.loc[df["grp_asthma"] == 1] = "Asthma"
        arh.loc[df["grp_asthma"] == 0] = "Non-asthma"
        df["grp_arh_strict"] = arh

    if "急性加重天数" in df.columns:
        df["grp_ae_days_3cat"] = _cut_ae_days(df["急性加重天数"])

    cv_cols = [c for c in ["com_htn", "com_chd", "com_hf", "com_af", "com_stroke"] if c in df.columns]
    metabolic_cols = [c for c in ["com_dm", "com_hld"] if c in df.columns]
    psych_cols = [c for c in ["com_anxdep"] if c in df.columns]
    resp_cols = [c for c in ["com_bx", "com_lungca", "com_pe", "grp_asthma"] if c in df.columns]
    frailty_cols = [c for c in ["com_renal", "com_hepatic", "com_anemia"] if c in df.columns]

    if cv_cols:
        df["grp_cv_comorb"] = _group_any_present(df, cv_cols)

    if metabolic_cols:
        df["grp_metabolic_comorb"] = _group_any_present(df, metabolic_cols)

    if psych_cols:
        df["grp_psych_comorb"] = _group_any_present(df, psych_cols)

    if resp_cols:
        df["grp_resp_comorb"] = _group_any_present(df, resp_cols)

    if frailty_cols:
        df["grp_frailty_comorb"] = _group_any_present(df, frailty_cols)

    all_com_cols = [c for c in [
        "com_dm", "com_htn", "com_hld", "com_chd", "com_hf", "com_af", "com_stroke",
        "com_anxdep", "com_osteo", "com_gerd", "com_bx", "com_lungca", "com_pe",
        "com_renal", "com_hepatic", "com_anemia", "grp_asthma", "grp_emphysema"
    ] if c in df.columns]

    if all_com_cols:
        comorbidity_values = df[all_com_cols].apply(pd.to_numeric, errors="coerce")
        df["multimorbidity_count"] = comorbidity_values.sum(axis=1, min_count=len(all_com_cols))
        mm = pd.Series(pd.NA, index=df.index, dtype="object")
        mm.loc[df["multimorbidity_count"] == 0] = "0"
        mm.loc[(df["multimorbidity_count"] >= 1) & (df["multimorbidity_count"] <= 2)] = "1-2"
        mm.loc[df["multimorbidity_count"] >= 3] = ">=3"
        df["grp_multimorbidity"] = mm

    if {"grp_smoking_ever_never", "grp_sex"}.issubset(df.columns):
        grp = pd.Series("No", index=df.index, dtype="object")
        grp.loc[
            (df["grp_sex"] == "Female") &
            (df["grp_smoking_ever_never"] == "Never")
        ] = "Yes"
        df["grp_female_never_smoker"] = grp

    if {"grp_smoking_ever_never", "grp_airway"}.issubset(df.columns):
        out = pd.Series(pd.NA, index=df.index, dtype="object")
        out.loc[
            (df["grp_smoking_ever_never"] == "Never") &
            (df["grp_airway"] == "Airway-reactive")
        ] = "Never + Airway"
        out.loc[
            (df["grp_smoking_ever_never"] == "Never") &
            (df["grp_airway"] == "Non-airway-reactive")
        ] = "Never + Non-airway"
        out.loc[
            (df["grp_smoking_ever_never"] == "Ever") &
            (df["grp_airway"] == "Airway-reactive")
        ] = "Ever + Airway"
        out.loc[
            (df["grp_smoking_ever_never"] == "Ever") &
            (df["grp_airway"] == "Non-airway-reactive")
        ] = "Ever + Non-airway"
        df["grp_never_smoker_airway"] = out

    need_symptom_dominant_cols = ["sym_cough", "sym_sputum", "sym_wheeze"]
    if all(c in df.columns for c in need_symptom_dominant_cols):
        grp = pd.Series(pd.NA, index=df.index, dtype="object")
        complete = df[need_symptom_dominant_cols].notna().all(axis=1)
        grp.loc[complete] = "Mixed / unclassified"

        cough = df["sym_cough"]
        sputum = df["sym_sputum"]
        wheeze = df["sym_wheeze"]

        mask1 = complete & (sputum == 1) & (wheeze == 0)
        grp.loc[mask1] = "Sputum-dominant"

        mask2 = complete & (~mask1) & (wheeze == 1) & (sputum == 0)
        grp.loc[mask2] = "Wheeze-dominant"

        mask3 = complete & (~mask1) & (~mask2) & (cough == 1) & (sputum == 0) & (wheeze == 0)
        grp.loc[mask3] = "Cough-dominant"

        df["grp_symptom_dominant_4cat"] = grp

    if "com_bx" in df.columns:
        df["grp_bx_grp"] = _label_from_binary(df["com_bx"], "Yes", "No")

    if ("grp_asthma" in df.columns) and ("grp_asthma_grp" not in df.columns):
        df["grp_asthma_grp"] = _label_from_binary(df["grp_asthma"], "Yes", "No")

    if ("grp_emphysema" in df.columns) and ("grp_emphysema_grp" not in df.columns):
        df["grp_emphysema_grp"] = _label_from_binary(df["grp_emphysema"], "Yes", "No")

    return df

def print_phenotype_summary(df: pd.DataFrame):
    cols = [
        "smoking_status_std",
        "smoking_3cat",
        "smoking_pheno",
        "current_smoker_flag",
        "pack_years_group",
        "infective_pheno",
        "infective_pheno_strict",
        "infective_score",
        "airway_reactive_pheno",
        "airway_reactive_pheno_strict",
        "airway_reactive_score",
        "event_pheno_4cat",
    ]

    print("\n[检查] AI-derived phenotype 分布：")
    for c in cols:
        if c in df.columns:
            print(f"\n--- {c} ---")
            print(df[c].value_counts(dropna=False))

def print_group_summary(df: pd.DataFrame):
    print("\n[检查] 分析分组分布：")
    for c in ANALYSIS_GROUP_COLS:
        if c in df.columns:
            print(f"\n--- {c} ---")
            print(df[c].value_counts(dropna=False))

def get_monthly_weekday_controls(case_date: pd.Timestamp,
                                 direction: str = "both",
                                 max_controls: int | None = None) -> list[pd.Timestamp]:
    case_date = pd.to_datetime(case_date).normalize()
    year, month = case_date.year, case_date.month
    wday = case_date.weekday()

    last_day = calendar.monthrange(year, month)[1]
    month_start = pd.Timestamp(year=year, month=month, day=1)
    month_end = pd.Timestamp(year=year, month=month, day=last_day)

    all_days = pd.date_range(month_start, month_end, freq="D")
    candidates = [d.normalize() for d in all_days if d.weekday() == wday and d.normalize() != case_date]

    if direction == "past":
        candidates = [d for d in candidates if d < case_date]
    elif direction == "future":
        candidates = [d for d in candidates if d > case_date]
    elif direction != "both":
        raise ValueError("direction must be one of: both/past/future")

    if max_controls is not None:
        candidates = sorted(candidates, key=lambda d: abs((d - case_date).days))[:max_controls]
        candidates = sorted(candidates)

    return candidates

def get_symmetric_weekday_controls(case_date: pd.Timestamp,
                                   direction: str = "both",
                                   weeks: list[int] | None = None) -> list[pd.Timestamp]:
    case_date = pd.to_datetime(case_date).normalize()
    weeks = [1, 2, 3] if weeks is None else weeks

    candidates = []
    for k in weeks:
        if k is None or pd.isna(k):
            continue
        k = int(k)
        if k <= 0:
            continue

        if direction in ["both", "past"]:
            candidates.append(case_date - pd.Timedelta(days=7 * k))
        if direction in ["both", "future"]:
            candidates.append(case_date + pd.Timedelta(days=7 * k))

    if direction not in ["both", "past", "future"]:
        raise ValueError("direction must be one of: both/past/future")

    candidates = sorted(set(pd.to_datetime(candidates).normalize()))
    candidates = [d for d in candidates if d != case_date]
    return candidates

def get_control_dates(case_date: pd.Timestamp,
                      strategy: str = "monthly_weekday",
                      direction: str = "both",
                      max_controls: int | None = None,
                      symmetric_weeks: list[int] | None = None) -> list[pd.Timestamp]:
    if strategy == "monthly_weekday":
        return get_monthly_weekday_controls(
            case_date=case_date,
            direction=direction,
            max_controls=max_controls
        )
    elif strategy == "symmetric_weekday":
        return get_symmetric_weekday_controls(
            case_date=case_date,
            direction=direction,
            weeks=symmetric_weeks
        )
    else:
        raise ValueError("strategy must be one of: monthly_weekday / symmetric_weekday")

def interpolate_flu_weekly_to_daily(
    flu_df: pd.DataFrame,
    date_col: str = "date",
    start_date: pd.Timestamp | None = None,
    end_date: pd.Timestamp | None = None,
    boundary: str = "clip",
) -> pd.DataFrame:
    if flu_df is None or flu_df.empty:
        return pd.DataFrame()

    df = flu_df.copy()
    df = _normalize_date_col(df, date_col)
    df = df.dropna(subset=[date_col]).sort_values(date_col)

    num_cols = [c for c in df.columns if c != date_col and pd.api.types.is_numeric_dtype(df[c])]
    keep_cols = [date_col] + num_cols + [c for c in df.columns if c not in ([date_col] + num_cols)]
    df = df[keep_cols].copy()

    if df[date_col].duplicated().any():
        df = df.groupby(date_col, as_index=False)[num_cols].mean(numeric_only=True).merge(
            df[[date_col] + [c for c in keep_cols if c not in ([date_col] + num_cols)]].drop_duplicates(date_col),
            on=date_col,
            how="left",
        )

    min_d = df[date_col].min()
    max_d = df[date_col].max()

    start_date = min_d if start_date is None else pd.to_datetime(start_date).normalize()
    end_date = max_d if end_date is None else pd.to_datetime(end_date).normalize()

    if boundary == "clip":
        start_use = max(start_date, min_d)
        end_use = min(end_date, max_d)
    elif boundary == "extend":
        start_use = start_date
        end_use = end_date
    else:
        raise ValueError("boundary must be 'clip' or 'extend'")

    if start_use > end_use:
        return pd.DataFrame({"date": pd.date_range(start_date, end_date, freq="D")})

    daily_index = pd.date_range(start_use, end_use, freq="D")

    df2 = df.set_index(date_col).sort_index()

    non_num_cols = [c for c in df2.columns if c not in num_cols]
    non_num_static = None
    if non_num_cols:
        non_num_static = df2[non_num_cols].iloc[0:1].copy()

    daily_num = df2[num_cols].reindex(df2.index.union(daily_index)).sort_index()
    daily_num = daily_num.interpolate(method="time", limit_direction="both" if boundary == "extend" else "forward")
    daily_num = daily_num.reindex(daily_index)

    out = daily_num.reset_index().rename(columns={"index": "date"})
    if non_num_static is not None:
        for c in non_num_cols:
            out[c] = non_num_static.iloc[0][c]

    return out

class DataLoader:
    @staticmethod
    def load_temperature_data(path: Path) -> pd.DataFrame:
        print(f"1.1 加载气温数据: {path.name}")
        df = pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path, encoding="utf-8-sig", low_memory=False)
        df = _flatten_columns(df)
        df = _dedupe_columns(df)

        if "date" in df.columns and any(column in df.columns for column in TEMPERATURE_BASE_VARS):
            if "county_name" not in df.columns:
                df = df.rename(columns={_pick_county_col(df): "county_name"})
            df["date"] = _normalize_date_series(df["date"])
            for column in TEMPERATURE_BASE_VARS:
                if column in df.columns:
                    df[column] = pd.to_numeric(df[column], errors="coerce")
            daily_temp = df[["county_name", "date"] + [column for column in TEMPERATURE_BASE_VARS if column in df.columns]].copy()
            daily_temp = daily_temp.groupby(["county_name", "date"], as_index=False).mean(numeric_only=True)
            if not {"Tmax", "Tmin"}.issubset(daily_temp.columns):
                raise ValueError("Long-format temperature input must contain Tavg, Tmax and Tmin")
            daily_temp = add_extreme_temperature_flags(
                daily_temp,
                method=EXTREME_TEMP_METHOD,
                heat_percentile=EXTREME_HEAT_PERCENTILE,
                cold_percentile=EXTREME_COLD_PERCENTILE,
                by_county=EXTREME_TEMP_BY_COUNTY,
            )
            return daily_temp

        if "county_name" not in df.columns:
            ccol = _pick_county_col(df)
            if ccol != "county_name":
                df = df.rename(columns={ccol: "county_name"})

        df = _ensure_single_id_col(df, "county_name")
        df["county_name"] = df["county_name"].astype(str).str.strip()
        df = df.dropna(subset=["county_name"])

        time_cols = [c for c in df.columns if c not in {"county_gb", "county_name"}]
        df_melted = pd.melt(
            df,
            id_vars=["county_name"] + (["county_gb"] if "county_gb" in df.columns else []),
            value_vars=time_cols,
            var_name="datetime_str",
            value_name="temperature"
        )

        s = df_melted["datetime_str"].astype(str).str.strip().str.replace(".0", "", regex=False)
        df_melted["datetime"] = pd.to_datetime(s, format="%Y%m%d%H", errors="coerce")
        df_melted["date"] = df_melted["datetime"].dt.normalize()
        df_melted["temperature"] = pd.to_numeric(df_melted["temperature"], errors="coerce")
        df_melted = df_melted.dropna(subset=["date"])

        daily_temp = (
            df_melted.groupby(["county_name", "date"])["temperature"]
            .agg(Tmax="max", Tmin="min", Tavg="mean")
            .reset_index()
        )

        keep_base_cols = ["county_name", "date"] + [c for c in TEMPERATURE_BASE_VARS if c in daily_temp.columns]
        daily_temp = daily_temp[keep_base_cols].copy()

        daily_temp = (
            daily_temp.groupby(["county_name", "date"], as_index=False)[
                [c for c in TEMPERATURE_BASE_VARS if c in daily_temp.columns]
            ].mean(numeric_only=True)
        )

        daily_temp = add_extreme_temperature_flags(
            daily_temp,
            method=EXTREME_TEMP_METHOD,
            heat_percentile=EXTREME_HEAT_PERCENTILE,
            cold_percentile=EXTREME_COLD_PERCENTILE,
            by_county=EXTREME_TEMP_BY_COUNTY,
        )

        print(f"    每日温度+极端温度数据形状: {daily_temp.shape}")
        return daily_temp

    @staticmethod
    def _read_excel_robust(path: Path) -> pd.DataFrame:
        df = pd.read_excel(path)
        df = _flatten_columns(df)
        df = df.dropna(axis=1, how="all")
        df = _dedupe_columns(df)
        return df

    @staticmethod
    def _prepare_county_name(df: pd.DataFrame) -> pd.DataFrame:
        df = _flatten_columns(df)
        df = _dedupe_columns(df)

        ccol = _pick_county_col(df)

        if "county_name" in df.columns and ccol != "county_name":
            df = df.rename(columns={"county_name": "county_name__old"})

        df = df.rename(columns={ccol: "county_name"})
        df = _dedupe_columns(df)
        df = _ensure_single_id_col(df, "county_name")

        df["county_name"] = df["county_name"].astype(str).str.strip()
        df = df.dropna(subset=["county_name"])
        return df

    @staticmethod
    def load_pollutant_data(path: Path, pollutant_name: str) -> pd.DataFrame:
        print(f"1.2 加载{pollutant_name}数据: {path.name}")
        df = DataLoader._read_excel_robust(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path, encoding="utf-8-sig", low_memory=False)
        df = _flatten_columns(df)
        df = _dedupe_columns(df)
        df = DataLoader._prepare_county_name(df)

        if "date" in df.columns and pollutant_name in df.columns:
            df["date"] = _normalize_date_series(df["date"])
            df[pollutant_name] = pd.to_numeric(df[pollutant_name], errors="coerce")
            return df.groupby(["county_name", "date"], as_index=False)[pollutant_name].mean()

        drop_cols = {"county_name", "county_gb", "county_name__old"}
        date_cols = [c for c in df.columns if c not in drop_cols]

        df_melted = pd.melt(
            df,
            id_vars=["county_name"],
            value_vars=date_cols,
            var_name="date_str",
            value_name=pollutant_name
        )

        df_melted["date"] = df_melted["date_str"].apply(_parse_yyyymmdd_from_col)
        df_melted["date"] = _normalize_date_series(df_melted["date"])
        df_melted = df_melted.dropna(subset=["date"])
        df_melted[pollutant_name] = pd.to_numeric(df_melted[pollutant_name], errors="coerce")

        result = (
            df_melted.groupby(["county_name", "date"], as_index=False)[pollutant_name]
            .mean(numeric_only=True)
        )
        print(f"    {pollutant_name}数据形状: {result.shape}")
        return result

    @staticmethod
    def load_pivot_csv(path: Path, value_name: str) -> pd.DataFrame:
        print(f"加载{value_name}数据: {path.name}")
        df = pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path, encoding="utf-8-sig", low_memory=False)
        df = _flatten_columns(df)
        df = df.dropna(axis=1, how="all")
        df = _dedupe_columns(df)

        df = DataLoader._prepare_county_name(df)

        if "date" in df.columns and value_name in df.columns:
            df["date"] = _normalize_date_series(df["date"])
            df[value_name] = pd.to_numeric(df[value_name], errors="coerce")
            return df.groupby(["county_name", "date"], as_index=False)[value_name].mean()

        drop_cols = {"county_name", "county_gb", "county_name__old"}
        date_cols = [c for c in df.columns if c not in drop_cols]

        df_melted = pd.melt(
            df,
            id_vars=["county_name"],
            value_vars=date_cols,
            var_name="date_str",
            value_name=value_name
        )

        df_melted["date"] = df_melted["date_str"].apply(_parse_yyyymmdd_from_col)
        df_melted["date"] = _normalize_date_series(df_melted["date"])
        df_melted = df_melted.dropna(subset=["date"])
        df_melted[value_name] = pd.to_numeric(df_melted[value_name], errors="coerce")

        result = (
            df_melted.groupby(["county_name", "date"], as_index=False)[value_name]
            .mean(numeric_only=True)
        )
        print(f"    {value_name}数据形状: {result.shape}")
        return result

    @staticmethod
    def load_influenza_data(path: Path, region: str = "north") -> pd.DataFrame:
        print(f"1.5 加载流感数据: {path.name} | 区域: {region}")
        df = pd.read_excel(path)
        df = _flatten_columns(df)
        df = _dedupe_columns(df)

        if "日期" not in df.columns:
            for col in df.columns:
                if ("日期" in str(col)) or ("date" in str(col).lower()):
                    df = df.rename(columns={col: "日期"})
                    break
        if "日期" not in df.columns:
            print("    [警告] 流感文件未找到日期列，返回空")
            return pd.DataFrame()

        df["date"] = _normalize_date_series(df["日期"])
        df = df.dropna(subset=["date"])

        prefix = "北方" if region == "north" else "南方"
        wanted = [f"{prefix}{v}" for v in INFLUENZA_VARS]

        use_cols = ["date"] + [c for c in wanted if c in df.columns]
        if use_cols == ["date"]:
            cand = [c for c in df.columns if str(c).startswith(prefix)]
            use_cols = ["date"] + cand
            if use_cols == ["date"]:
                print(f"    [警告] 未找到 {prefix} 相关列，返回空")
                return pd.DataFrame()
            else:
                print(f"    [提示] 未完整命中预设流感变量，暂使用所有 {prefix} 开头列")

        sub = df[use_cols].copy()

        rename = {}
        for c in sub.columns:
            if c == "date":
                continue
            cc_ = str(c)
            if cc_.startswith(prefix):
                cc_ = cc_.replace(prefix, "", 1)
            rename[c] = cc_
        sub = sub.rename(columns=rename)

        keep_cols = ["date"] + [c for c in INFLUENZA_VARS if c in sub.columns]
        sub = sub[keep_cols].copy()

        for c in sub.columns:
            if c != "date":
                sub[c] = pd.to_numeric(sub[c], errors="coerce")

        num_cols = [c for c in sub.columns if c != "date" and pd.api.types.is_numeric_dtype(sub[c])]
        sub = sub.groupby("date", as_index=False)[num_cols].mean(numeric_only=True)
        sub["flu_region"] = region

        found_vars = [c for c in INFLUENZA_VARS if c in sub.columns]
        missing_vars = [c for c in INFLUENZA_VARS if c not in sub.columns]

        print(f"    流感数据形状: {sub.shape}")
        print(f"    已保留流感变量({len(found_vars)}): {found_vars}")
        if missing_vars:
            print(f"    [提示] 流感文件缺少以下变量({len(missing_vars)}): {missing_vars}")

        return sub

def merge_all_data_optimized(temperature_df, pollutant_dfs, humidity_dfs, pressure_dfs, influenza_df):
    print("\n1.6 合并气象、污染物、湿度、气压和流感数据")

    merged_df = temperature_df.copy()
    merged_df = _normalize_date_col(merged_df, "date")
    merged_df["county_name"] = merged_df["county_name"].astype(str).str.strip()

    temp_keep = ["county_name", "date"] + [c for c in TEMPERATURE_VARS if c in merged_df.columns]
    extra_temp_cols = [c for c in ["heat_thresh", "cold_thresh"] if c in merged_df.columns]
    merged_df = merged_df[temp_keep + extra_temp_cols].copy()

    print(f"    初始数据（气温）: {merged_df.shape}")

    for df in pollutant_dfs.values():
        if df is not None and not df.empty:
            df = _normalize_date_col(df, "date")
            df["county_name"] = df["county_name"].astype(str).str.strip()
            keep_cols = ["county_name", "date"] + [c for c in POLLUTANT_VARS if c in df.columns]
            df = df[keep_cols].copy()
            merged_df = merged_df.merge(df, on=["county_name", "date"], how="left")

    for df in humidity_dfs.values():
        if df is not None and not df.empty:
            df = _normalize_date_col(df, "date")
            df["county_name"] = df["county_name"].astype(str).str.strip()
            keep_cols = ["county_name", "date"] + [c for c in HUMIDITY_VARS if c in df.columns]
            df = df[keep_cols].copy()
            merged_df = merged_df.merge(df, on=["county_name", "date"], how="left")

    for df in pressure_dfs.values():
        if df is not None and not df.empty:
            df = _normalize_date_col(df, "date")
            df["county_name"] = df["county_name"].astype(str).str.strip()
            keep_cols = ["county_name", "date"] + [c for c in PRESSURE_VARS if c in df.columns]
            df = df[keep_cols].copy()
            merged_df = merged_df.merge(df, on=["county_name", "date"], how="left")

    if influenza_df is not None and not influenza_df.empty:
        influenza_df = _normalize_date_col(influenza_df, "date")
        flu_keep = ["date"] + [c for c in INFLUENZA_VARS if c in influenza_df.columns]
        if "flu_region" in influenza_df.columns:
            flu_keep.append("flu_region")
        influenza_df = influenza_df[flu_keep].copy()
        merged_df = merged_df.merge(influenza_df, on="date", how="left")

    print(f"    合并后数据形状(未压缩): {merged_df.shape}")
    merged_df = collapse_meteo_unique(merged_df)

    final_keep = ["county_name", "date"] + [c for c in ANALYSIS_VARS if c in merged_df.columns]
    extra_keep = [c for c in ["heat_thresh", "cold_thresh"] if c in merged_df.columns]
    if "flu_region" in merged_df.columns:
        extra_keep.append("flu_region")
    merged_df = merged_df[final_keep + extra_keep].copy()

    print(f"    最终合并数据形状(已压缩): {merged_df.shape}")
    print(f"    最终保留分析变量: {[c for c in ANALYSIS_VARS if c in merged_df.columns]}")
    return merged_df

def load_patients_optimized(path: Path) -> pd.DataFrame:
    print(f"\n2. 加载患者数据: {path.name}")
    df = pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path)
    df = _flatten_columns(df)
    df = _dedupe_columns(df)

    event_col = _find_first_existing_col(df, [EVENT_DATE_SOURCE, "onset_date", "事件日"])
    if event_col is None or "county" not in df.columns:
        print("    错误：患者表缺少事件日期或county列")
        return pd.DataFrame()
    if "序号" not in df.columns:
        id_col = _find_first_existing_col(df, ["patient_id", "cluster_id", "origin_id"])
        if id_col is None:
            print("    错误：患者表缺少去标识化患者ID")
            return pd.DataFrame()
        df["序号"] = df[id_col].astype(str)

    df["事件日"] = _normalize_date_series(df[event_col])
    if "visit_date" in df.columns:
        df["visit_date"] = _normalize_date_series(df["visit_date"])
    elif "就诊日期_dt" in df.columns:
        df["visit_date"] = _normalize_date_series(df["就诊日期_dt"])
    elif "就诊日期" in df.columns:
        df["visit_date"] = _normalize_date_series(df["就诊日期"])
    else:
        df["visit_date"] = pd.NaT

    onset_col = _find_first_existing_col(df, ["onset_date", "回推起始日", "回推起始日_dt"])
    df["onset_date"] = _normalize_date_series(df[onset_col]) if onset_col is not None else df["事件日"]
    df = df.dropna(subset=["事件日"])

    if "hospital_code" in df.columns:
        df["hospital_code"] = df["hospital_code"].astype(str).str.strip()
    elif "医院" in df.columns:
        hospital_names = df["医院"].astype(str).str.strip()
        hospital_codes = {name: f"H{i+1:02d}" for i, name in enumerate(hospital_names.dropna().unique())}
        df["hospital_code"] = hospital_names.map(hospital_codes)
    else:
        df["hospital_code"] = "H01"

    df = df.sort_values(["hospital_code", "序号", "事件日"]).reset_index(drop=True)
    df["origin_id"] = df["hospital_code"] + "_" + df["序号"].astype(str)
    df["visit_seq"] = df.groupby("origin_id").cumcount()
    df["patient_id"] = df["origin_id"] + "_V" + df["visit_seq"].astype(str)

    df["match_id"] = df["patient_id"]
    df["cluster_id"] = df["origin_id"]

    if df["patient_id"].duplicated().any():
        print("    [警告] patient_id存在重复！使用哈希兜底")
        for idx, row in df.iterrows():
            unique_str = f"{row['hospital_code']}_{row['序号']}_{row['事件日']}_{idx}"
            hid = hashlib.md5(unique_str.encode()).hexdigest()[:12]
            df.loc[idx, "patient_id"] = hid
            df.loc[idx, "match_id"] = hid

    print(f"    有效记录数: {len(df)}")
    print(f"    唯一患者数（origin_id / cluster_id）: {df['origin_id'].nunique()}")
    print(f"    唯一事件数（match_id）: {df['match_id'].nunique()}")
    return df

def match_county_optimized(meteo_df: pd.DataFrame, pat_df: pd.DataFrame) -> pd.DataFrame:
    print("\n3. 区县名称匹配")
    meteo_counties = set(meteo_df["county_name"].dropna().astype(str).str.strip().unique())

    clean_name_map = {}
    for county in meteo_counties:
        clean = str(county).strip()
        clean = clean.replace("市", "").replace("区", "").replace("县", "").replace("自治", "")
        clean_name_map[clean] = county

    def match_single(pat_county):
        if pd.isna(pat_county):
            return None
        raw = str(pat_county).strip()
        if raw in meteo_counties:
            return raw
        clean = raw.replace("市", "").replace("区", "").replace("县", "").replace("自治", "")
        if clean in clean_name_map:
            return clean_name_map[clean]
        for m in meteo_counties:
            if raw in str(m) or str(m) in raw:
                return m
        return None

    pat_df = pat_df.copy()
    pat_df["matched_name"] = pat_df["county"].apply(match_single)

    ok = pat_df["matched_name"].notna().sum()
    print(f"    匹配成功 {ok}/{len(pat_df)} ({ok/len(pat_df):.2%})")
    return pat_df

def add_patient_group_labels_optimized(pat_df: pd.DataFrame) -> pd.DataFrame:
    print("\n4. 添加患者基础标签")
    df = pat_df.copy()

    if "年龄" in df.columns:
        df["年龄"] = pd.to_numeric(df["年龄"], errors="coerce").clip(0, 120)
        df["age_group"] = np.where(df["年龄"] >= 65, "≥65岁", "<65岁")

    if "性别" in df.columns:
        df["sex_group"] = df["性别"].astype(str).str.strip().map({
            "男": "男", "女": "女", "Male": "男", "Female": "女"
        })

    if "吸烟状态" in df.columns:
        smoke_map = {"从不吸烟": "不吸烟", "当前吸烟": "吸烟", "已戒烟": "戒烟"}
        df["smoke_group"] = df["吸烟状态"].map(smoke_map)

    if "事件日" in df.columns:
        month_day = df["事件日"].dt.strftime("%m-%d")
        heating = (month_day >= "10-20") | (month_day <= "04-06")
        df["season"] = np.where(heating, "heating", "non_heating")

    return df

class ExposurePreprocessor:
    def __init__(self, meteo_df: pd.DataFrame, lags: list):
        self.meteo_df = meteo_df.copy()
        self.meteo_df = _normalize_date_col(self.meteo_df, "date")
        self.lags = lags
        self.max_lag = max(lags) if lags else 0
        self._build_indexes()

    def _build_indexes(self):
        self.county_data = {}
        self.exposure_cache = {}

        for county_name in self.meteo_df["county_name"].dropna().unique():
            cdf = self.meteo_df[self.meteo_df["county_name"] == county_name].copy()
            cdf = _normalize_date_col(cdf, "date")

            numeric_cols = [
                c for c in cdf.columns
                if c in ANALYSIS_VARS and pd.api.types.is_numeric_dtype(cdf[c])
            ]
            cdf = cdf.groupby("date", as_index=False)[numeric_cols].mean(numeric_only=True)
            cdf = cdf.set_index("date").sort_index()
            self.county_data[county_name] = cdf

    @staticmethod
    def _to_scalar(v):
        if isinstance(v, pd.Series):
            return float(np.nanmean(v.values))
        if isinstance(v, (np.ndarray, list)):
            return float(np.nanmean(np.array(v, dtype=float)))
        return v

    def get_exposure(self, county_name: str, target_date: pd.Timestamp) -> dict:
        if pd.isna(county_name) or pd.isna(target_date):
            return {}

        target_date = pd.to_datetime(target_date, errors="coerce")
        if pd.isna(target_date):
            return {}
        target_date = target_date.normalize()

        cache_key = f"{county_name}_{target_date.strftime('%Y%m%d')}"
        if cache_key in self.exposure_cache:
            return self.exposure_cache[cache_key]

        exposure_data = {}
        if county_name not in self.county_data:
            self.exposure_cache[cache_key] = exposure_data
            return exposure_data

        cdf = self.county_data[county_name]
        binary_extreme_vars = {"EHT", "ELT"}

        for var in cdf.columns:
            lag_values = []
            for lag in self.lags:
                lag_date = target_date - timedelta(days=lag)
                if lag_date in cdf.index:
                    v = cdf.loc[lag_date, var]
                    v = self._to_scalar(v)
                    lag_values.append(v)
                else:
                    lag_values.append(np.nan)

            for lag, v in zip(self.lags, lag_values):
                exposure_data[f"{var}_lag{lag}"] = v

            lag_0_2 = lag_values[:3]
            valid_0_2 = [x for x in lag_0_2 if not pd.isna(x)]

            if len(valid_0_2) >= 2:
                exposure_data[f"{var}_avg_lag0_2"] = float(np.nanmean(valid_0_2))
                exposure_data[f"{var}_max_lag0_2"] = float(np.nanmax(valid_0_2))
            else:
                exposure_data[f"{var}_avg_lag0_2"] = np.nan
                exposure_data[f"{var}_max_lag0_2"] = np.nan

            for window_end in range(1, min(7, len(lag_values) - 1) + 1):
                window = lag_values[: window_end + 1]
                valid_window = [x for x in window if not pd.isna(x)]
                minimum_valid = 2 if window_end <= 2 else 4
                exposure_data[f"{var}_avg_lag0_{window_end}"] = (
                    float(np.nanmean(valid_window))
                    if len(valid_window) >= minimum_valid else np.nan
                )

            lag_0_7 = lag_values[:8]
            valid_0_7 = [x for x in lag_0_7 if not pd.isna(x)]

            if var in binary_extreme_vars:
                if len(valid_0_2) >= 2:
                    exposure_data[f"{var}_count_lag0_2"] = int(np.nansum(valid_0_2))
                    exposure_data[f"{var}_any_lag0_2"] = int(np.nansum(valid_0_2) >= 1)
                else:
                    exposure_data[f"{var}_count_lag0_2"] = np.nan
                    exposure_data[f"{var}_any_lag0_2"] = np.nan

                if len(valid_0_7) >= 4:
                    exposure_data[f"{var}_count_lag0_7"] = int(np.nansum(valid_0_7))
                    exposure_data[f"{var}_any_lag0_7"] = int(np.nansum(valid_0_7) >= 1)
                else:
                    exposure_data[f"{var}_count_lag0_7"] = np.nan
                    exposure_data[f"{var}_any_lag0_7"] = np.nan

        self.exposure_cache[cache_key] = exposure_data
        return exposure_data

class BatchProcessor:
    def __init__(self,
                 strategy="monthly_weekday",
                 direction="past",
                 max_controls=None,
                 symmetric_weeks=None):
        self.strategy = strategy
        self.direction = direction
        self.max_controls = max_controls
        self.symmetric_weeks = [1, 2, 3] if symmetric_weeks is None else symmetric_weeks

    def process_batch(self, batch_data: list, exposure_preprocessor: ExposurePreprocessor) -> list:
        results = []

        for row in batch_data:
            if pd.isna(row.get("matched_name", None)) or pd.isna(row.get("事件日", None)):
                continue

            case_date = pd.to_datetime(row["事件日"], errors="coerce")
            if pd.isna(case_date):
                continue
            case_date = case_date.normalize()

            county_name = row["matched_name"]

            patient_event_dates = row.get("all_event_dates_for_origin", set())
            if not isinstance(patient_event_dates, set):
                patient_event_dates = set(pd.to_datetime(list(patient_event_dates), errors="coerce").dropna())

            patient_event_dates = {
                pd.Timestamp(x).normalize()
                for x in pd.to_datetime(list(patient_event_dates), errors="coerce").dropna()
            }

            case_exposure = exposure_preprocessor.get_exposure(county_name, case_date)
            results.append(self._create_record(
                row=row,
                date=case_date,
                is_case=1,
                exposure_data=case_exposure,
                control_date_source="case"
            ))

            control_dates = get_control_dates(
                case_date=case_date,
                strategy=self.strategy,
                direction=self.direction,
                max_controls=self.max_controls,
                symmetric_weeks=self.symmetric_weeks
            )

            filtered_control_dates = []
            for d in control_dates:
                dn = pd.to_datetime(d).normalize()
                if dn in patient_event_dates:
                    continue
                filtered_control_dates.append(dn)

            for control_date in filtered_control_dates:
                control_exposure = exposure_preprocessor.get_exposure(county_name, control_date)
                results.append(self._create_record(
                    row=row,
                    date=control_date,
                    is_case=0,
                    exposure_data=control_exposure,
                    control_date_source=self.strategy
                ))

        return results

    def _create_record(self, row: pd.Series, date: pd.Timestamp, is_case: int,
                       exposure_data: dict, control_date_source: str) -> dict:
        cal_flags = get_calendar_flags(date)

        record = {
            "match_id": row.get("match_id", ""),
            "cluster_id": row.get("cluster_id", ""),
            "patient_id": row.get("patient_id", ""),
            "origin_id": row.get("origin_id", ""),
            "visit_seq": row.get("visit_seq", 0),

            "date": pd.to_datetime(date).normalize(),
            "event_date": pd.to_datetime(row.get("事件日", pd.NaT), errors="coerce"),
            "is_case": is_case,
            "control_date_source": control_date_source,

            "county": row.get("county", ""),
            "matched_name": row.get("matched_name", ""),
            "hospital_code": row.get("hospital_code", ""),

            "public_holiday": cal_flags["public_holiday"],
            "is_workday": cal_flags["is_workday"],
            "is_weekend": cal_flags["is_weekend"],
        }

        for attr in PATIENT_INFO_COLS:
            if attr in row.index and attr not in record:
                record[attr] = row[attr]

        for group_col in ["age_group", "sex_group", "smoke_group", "season"]:
            if group_col in row.index:
                record[group_col] = row[group_col]

        for pheno_col in PHENOTYPE_INFO_COLS:
            if pheno_col in row.index:
                record[pheno_col] = row[pheno_col]

        for grp_col in ANALYSIS_GROUP_COLS:
            if grp_col in row.index:
                record[grp_col] = row[grp_col]

        record.update(exposure_data)
        return record

def run_single_strategy(
    strategy_config: dict,
    pat_matched: pd.DataFrame,
    meteo_df: pd.DataFrame,
    output_dir: Path,
    output_prefix: str,
    thread_num: int,
):
    strategy = strategy_config.get("strategy", "monthly_weekday")
    direction = strategy_config.get("direction", "both")
    max_controls = strategy_config.get("max_controls", None)
    symmetric_weeks = strategy_config.get("symmetric_weeks", [1, 2, 3])

    print("\n" + "=" * 88)
    print(f"开始运行策略: {strategy}")
    print(f"对照方向: {direction}")
    print(f"最大对照数: {max_controls}")
    print(f"对称周设置: {symmetric_weeks}")
    print("=" * 88)

    start_time = time.time()

    print("\n步骤3: 构建暴露索引")
    exposure_preprocessor = ExposurePreprocessor(meteo_df, LAGS)

    print(f"\n步骤4: 多线程处理（{thread_num}线程）")
    batch_processor = BatchProcessor(
        strategy=strategy,
        direction=direction,
        max_controls=max_controls,
        symmetric_weeks=symmetric_weeks
    )

    patient_chunks = np.array_split(pat_matched, max(1, thread_num * 4))

    all_results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=thread_num) as executor:
        futures = []
        for chunk in patient_chunks:
            chunk_list = [row for _, row in chunk.iterrows()]
            futures.append(executor.submit(batch_processor.process_batch, chunk_list, exposure_preprocessor))

        for fut in tqdm(concurrent.futures.as_completed(futures), total=len(futures), desc=f"{strategy} 处理进度"):
            all_results.extend(fut.result())

    results_df = pd.DataFrame(all_results)

    if results_df.empty:
        print(f"错误：策略 {strategy} 未生成任何病例/对照记录")
        return None

    set_status = results_df.groupby("match_id")["is_case"].agg(
        n_case=lambda values: int((values == 1).sum()),
        n_control=lambda values: int((values == 0).sum()),
    )
    valid_sets = set_status.index[(set_status["n_case"] == 1) & (set_status["n_control"] >= 1)]
    excluded_sets = int(set_status.shape[0] - len(valid_sets))
    results_df = results_df[results_df["match_id"].isin(valid_sets)].copy()
    print(f"    剔除无有效病例-对照组合的匹配集: {excluded_sets}")
    if results_df.empty:
        print(f"错误：策略 {strategy} 筛选后无有效匹配集")
        return None

    sort_cols = [c for c in ["cluster_id", "match_id", "is_case", "date"] if c in results_df.columns]
    results_df = results_df.sort_values(sort_cols).reset_index(drop=True)

    print("\n[统计] 结果数据统计：")
    print(f"    策略: {strategy}")
    print(f"    总记录数: {len(results_df):,}")
    print(f"    病例数: {results_df['is_case'].sum():,}")
    print(f"    对照数: {(results_df['is_case'] == 0).sum():,}")
    print(f"    唯一匹配集(match_id): {results_df['match_id'].nunique():,}")
    print(f"    唯一聚类(cluster_id): {results_df['cluster_id'].nunique():,}")

    match_ids = results_df.loc[results_df["is_case"] == 1, "match_id"].unique()
    controls_per_case = []
    for mid in match_ids:
        tmp = results_df[results_df["match_id"] == mid]
        controls_per_case.append((tmp["is_case"] == 0).sum())

    if controls_per_case:
        print(f"    平均每个病例的对照日数: {np.mean(controls_per_case):.2f}")
        print(f"    最小对照日数: {np.min(controls_per_case)}")
        print(f"    最大对照日数: {np.max(controls_per_case)}")

    check_case_n = results_df.groupby("match_id")["is_case"].sum()
    bad_match = (check_case_n != 1).sum()
    print(f"    病例数不等于1的匹配集数: {bad_match}")

    merged_check = results_df[["cluster_id", "match_id", "date", "is_case"]].copy()
    event_dates_all = results_df.loc[results_df["is_case"] == 1, ["cluster_id", "date"]].drop_duplicates()
    ctrl_rows = merged_check[merged_check["is_case"] == 0].merge(
        event_dates_all.assign(is_other_event_date=1),
        on=["cluster_id", "date"],
        how="left"
    )
    n_conflict = int((ctrl_rows["is_other_event_date"] == 1).sum())
    print(f"    对照日与同患者事件日冲突数（应为0）: {n_conflict}")

    base_cols = [
        "match_id", "cluster_id", "patient_id", "origin_id", "visit_seq",
        "date", "event_date", "is_case", "control_date_source",
        "county", "matched_name", "hospital_code",
        "public_holiday", "is_workday", "is_weekend"
    ]

    patient_cols_keep = [c for c in PATIENT_INFO_COLS if c in results_df.columns and c not in base_cols]
    simple_group_cols = [c for c in ["age_group", "sex_group", "smoke_group", "season"] if c in results_df.columns]
    pheno_cols_keep = [c for c in PHENOTYPE_INFO_COLS if c in results_df.columns]
    analysis_group_cols_keep = [c for c in ANALYSIS_GROUP_COLS if c in results_df.columns]

    exposure_cols = [c for c in results_df.columns if c not in (
        base_cols + patient_cols_keep + simple_group_cols + pheno_cols_keep + analysis_group_cols_keep
    )]

    ordered_cols = [c for c in base_cols if c in results_df.columns] \
        + patient_cols_keep \
        + simple_group_cols \
        + pheno_cols_keep \
        + analysis_group_cols_keep \
        + exposure_cols

    results_df = results_df[ordered_cols].copy()

    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f"{output_prefix}_{strategy}.csv"
    results_df.to_csv(output_file, index=False, encoding="utf-8-sig")

    print("\n[检查] lag0 缺失率(若列存在)：")
    for v in ANALYSIS_VARS:
        col = f"{v}_lag0"
        if col in results_df.columns:
            miss = results_df[col].isna().mean() * 100
            print(f"    {col}: {miss:.1f}%")

    eht_elt_cols = [c for c in results_df.columns if c.startswith(("EHT_", "ELT_"))]
    if eht_elt_cols:
        print("\n[检查] EHT / ELT 扩展变量：")
        print(eht_elt_cols)

    if "public_holiday" in results_df.columns:
        print("\n[检查] 日历变量分布：")
        print(results_df[["public_holiday", "is_workday", "is_weekend"]].apply(
            lambda x: x.value_counts(dropna=False)
        ).fillna(0))

    print("\n[检查] case-crossover 展开后 phenotype 分布：")
    print_phenotype_summary(results_df)

    print("\n[检查] case-crossover 展开后 analysis groups 分布：")
    print_group_summary(results_df)

    print("\n[检查] 同一 match_id 内 phenotype / groups 一致性：")
    for c in [
        "smoking_pheno", "infective_pheno", "airway_reactive_pheno", "event_pheno_4cat",
        *ANALYSIS_GROUP_COLS
    ]:
        if c in results_df.columns:
            n_inconsistent = (results_df.groupby("match_id")[c].nunique(dropna=False) > 1).sum()
            print(f"    {c}: 不一致 match_id 数 = {n_inconsistent}")

    total_time = time.time() - start_time
    print("\n处理完成！")
    print(f"策略: {strategy}")
    print(f"总时间: {total_time:.2f}秒")
    print(f"输出: {output_file}")
    print("\n后续R建议：")
    print('  STRATA_VAR  <- "match_id"')
    print('  CLUSTER_VAR <- "cluster_id"')
    print('  可加入协变量: public_holiday / is_workday / is_weekend')

    return {
        "strategy": strategy,
        "output_file": str(output_file),
        "n_total": len(results_df),
        "n_case": int(results_df["is_case"].sum()),
        "n_control": int((results_df["is_case"] == 0).sum()),
        "n_match": int(results_df["match_id"].nunique()),
        "n_cluster": int(results_df["cluster_id"].nunique()),
        "avg_controls": float(np.mean(controls_per_case)) if controls_per_case else np.nan,
        "min_controls": int(np.min(controls_per_case)) if controls_per_case else np.nan,
        "max_controls": int(np.max(controls_per_case)) if controls_per_case else np.nan,
        "conflict_controls": n_conflict,
    }

def main():
    print("=" * 88)
    print("开始病例交叉设计分析（双策略主干 + public_holiday + 极端温度 + 全部分组 + AI phenotype）")
    print(f"滞后天数: {LAGS}")
    print(f"线程数: {THREAD_NUM}")
    print(f"流感区域: {FLU_REGION}")
    print(f"流感插值到日尺度: {FLU_INTERPOLATE_TO_DAILY} | boundary={FLU_INTERP_BOUNDARY}")
    print("极端温度定义：")
    print(f"    方法: {EXTREME_TEMP_METHOD}")
    print(f"    极端高温: Tmax >= P{EXTREME_HEAT_PERCENTILE}")
    print(f"    极端低温: Tmin <= P{EXTREME_COLD_PERCENTILE}")
    print(f"    是否按区县分别计算阈值: {EXTREME_TEMP_BY_COUNTY}")
    print("将运行的对照策略：")
    for cfg in CONTROL_CONFIGS:
        print(f"    - strategy={cfg['strategy']}, direction={cfg['direction']}, "
              f"max_controls={cfg['max_controls']}, symmetric_weeks={cfg['symmetric_weeks']}")
    print("=" * 88)

    print("\n[信息] 本次分析暴露变量：")
    for v in ANALYSIS_VARS:
        print(f"    - {v}: {VAR_LABEL_MAP[v]}")

    global_start_time = time.time()

    pat_df = load_patients_optimized(PAT_FILE)
    if pat_df.empty:
        print("错误：患者数据为空")
        return

    event_dates_map = (
        pat_df.groupby("origin_id")["事件日"]
        .apply(lambda s: set(pd.to_datetime(s, errors="coerce").dropna().dt.normalize()))
        .to_dict()
    )
    pat_df["all_event_dates_for_origin"] = pat_df["origin_id"].map(event_dates_map)

    min_case = pat_df["事件日"].min()
    max_case = pat_df["事件日"].max()

    meteo_min, meteo_max = get_needed_meteo_window(min_case, max_case, CONTROL_CONFIGS, LAGS)

    print(f"\n[信息] 患者事件日范围: {min_case.date()} ~ {max_case.date()}")
    print(f"[信息] 基于全部策略所需的暴露日期范围: {meteo_min.date()} ~ {meteo_max.date()}")

    print("\n步骤1: 加载环境数据")
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, THREAD_NUM)) as executor:
        temp_future = executor.submit(DataLoader.load_temperature_data, TEMPERATURE_FILE)

        poll_futures = {
            n: executor.submit(DataLoader.load_pollutant_data, p, n)
            for n, p in POLLUTANT_FILES.items() if p.exists()
        }
        hum_futures = {
            n: executor.submit(DataLoader.load_pivot_csv, p, n)
            for n, p in HUMIDITY_FILES.items() if p.exists()
        }
        pres_futures = {
            n: executor.submit(DataLoader.load_pivot_csv, p, n)
            for n, p in PRESSURE_FILES.items() if p.exists()
        }
        flu_future = executor.submit(DataLoader.load_influenza_data, INFLUENZA_FILE, FLU_REGION)

        temperature_df = temp_future.result()
        pollutant_dfs = {n: f.result() for n, f in poll_futures.items()}
        humidity_dfs = {n: f.result() for n, f in hum_futures.items()}
        pressure_dfs = {n: f.result() for n, f in pres_futures.items()}
        influenza_df = flu_future.result()

    if FLU_INTERPOLATE_TO_DAILY and influenza_df is not None and not influenza_df.empty:
        print("\n[修复] 流感数据进行日尺度线性插值")
        before_shape = influenza_df.shape
        influenza_df_daily = interpolate_flu_weekly_to_daily(
            influenza_df,
            date_col="date",
            start_date=meteo_min,
            end_date=meteo_max,
            boundary=FLU_INTERP_BOUNDARY
        )
        print(f"    流感插值前: {before_shape} -> 插值后(日): {influenza_df_daily.shape}")
        influenza_df = influenza_df_daily

    meteo_df = merge_all_data_optimized(
        temperature_df, pollutant_dfs, humidity_dfs, pressure_dfs, influenza_df
    )

    if CLIP_METEO_BY_PATIENT_WINDOW:
        meteo_df = meteo_df[(meteo_df["date"] >= meteo_min) & (meteo_df["date"] <= meteo_max)].copy()
        print(f"\n[裁剪] meteo_df 裁剪后形状: {meteo_df.shape}")

    print("\n步骤2: 区县匹配")
    pat_df = match_county_optimized(meteo_df, pat_df)
    pat_matched = pat_df[pat_df["matched_name"].notna()].copy()
    if pat_matched.empty:
        print("错误：无匹配患者")
        return
    print(f"    匹配成功记录数: {len(pat_matched)}")

    pat_matched = add_patient_group_labels_optimized(pat_matched)
    pat_matched = add_ai_phenotypes(pat_matched)
    pat_matched = add_all_analysis_groups(pat_matched)

    print_phenotype_summary(pat_matched)
    print_group_summary(pat_matched)

    all_run_summaries = []
    for cfg in CONTROL_CONFIGS:
        summary = run_single_strategy(
            strategy_config=cfg,
            pat_matched=pat_matched,
            meteo_df=meteo_df,
            output_dir=OUTPUT_DIR,
            output_prefix=OUTPUT_PREFIX,
            thread_num=THREAD_NUM,
        )
        if summary is not None:
            all_run_summaries.append(summary)

    print("\n" + "=" * 88)
    print("全部策略运行完成，总结如下：")
    for s in all_run_summaries:
        print(f"\n策略: {s['strategy']}")
        print(f"    输出文件: {s['output_file']}")
        print(f"    总记录数: {s['n_total']:,}")
        print(f"    病例数: {s['n_case']:,}")
        print(f"    对照数: {s['n_control']:,}")
        print(f"    匹配集数: {s['n_match']:,}")
        print(f"    聚类数: {s['n_cluster']:,}")
        print(f"    平均每病例对照日数: {s['avg_controls']:.2f}" if pd.notna(s['avg_controls']) else "    平均每病例对照日数: NaN")
        print(f"    最小对照日数: {s['min_controls']}")
        print(f"    最大对照日数: {s['max_controls']}")
        print(f"    对照冲突数: {s['conflict_controls']}")

    total_time = time.time() - global_start_time
    print(f"\n总耗时: {total_time:.2f}秒")
    print("=" * 88)

if __name__ == "__main__":
    main()
