#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import requests

SYMPTOMS = [
    "cough",
    "sputum",
    "dyspnea",
    "wheeze",
    "chest_tightness",
    "fever",
    "fatigue",
    "nocturnal_symptoms",
]

SYMPTOM_SOURCE_KEYS = {
    "cough": "咳嗽分组",
    "sputum": "咳痰分组",
    "dyspnea": "呼吸困难分组",
    "wheeze": "喘息分组",
    "chest_tightness": "胸闷分组",
    "fever": "发热分组",
    "fatigue": "乏力分组",
    "nocturnal_symptoms": "夜间症状分组",
}

COMORBIDITIES = [
    "diabetes",
    "hypertension",
    "hyperlipidemia",
    "coronary_heart_disease",
    "heart_failure",
    "atrial_fibrillation",
    "stroke",
    "anxiety_depression",
    "osteoporosis",
    "gastroesophageal_reflux",
    "bronchiectasis",
    "lung_cancer",
    "pulmonary_embolism",
    "renal_insufficiency",
    "hepatic_insufficiency",
    "anemia",
]

TASKS = ("symptoms", "smoking", "comorbidities")


def robust_json_parse(raw_text: str) -> dict[str, Any]:
    """Parse a single JSON object from an Ollama response."""
    if not raw_text:
        raise ValueError("Empty model response")
    text = raw_text.strip()
    text = re.sub(r"<think>[\s\S]*?</think>", "", text).strip()
    fenced = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if fenced:
        text = fenced.group(1).strip()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", text)
        if not match:
            raise
        value = json.loads(match.group(0))
    if not isinstance(value, dict):
        raise TypeError("Model output is not a JSON object")
    return value


def _number(value: Any, lower: float, upper: float) -> float | None:
    if value in (None, "", -1, "-1"):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if np.isfinite(number) and lower <= number <= upper else None


def _binary(value: Any) -> int | None:
    if value in (0, "0", False):
        return 0
    if value in (1, "1", True):
        return 1
    return None


def _symptom_value(value: Any) -> str | None:
    if value is None or value == -1 or "缺失" in str(value):
        return None
    text = str(value)
    if text.startswith("轻度"):
        return "mild"
    if text.startswith(("严重", "重度")):
        return "severe"
    if text.startswith("无"):
        return "absent"
    if text.startswith("有"):
        return "present"
    return None


def normalize_symptoms(result: dict[str, Any]) -> dict[str, Any]:
    groups = result.get("symptom_groups")
    if not isinstance(groups, dict):
        groups = {}
    duration = _number(result.get("acute_exacerbation_duration"), 0, 365)
    return {
        "duration_days": 0.0 if duration is None else duration,
        "symptoms": {
            field: _symptom_value(groups.get(source_key))
            for field, source_key in SYMPTOM_SOURCE_KEYS.items()
        },
        "acute_exacerbation": _binary(result.get("acute_exacerbation")),
        "has_copd_history": _binary(result.get("has_copd_history")),
    }


def normalize_smoking(result: dict[str, Any]) -> dict[str, Any]:
    raw_status = result.get("smoking_status")
    status = {0: "never", 1: "former", 2: "current", "0": "never", "1": "former", "2": "current"}.get(raw_status)
    smoking_years = _number(result.get("smoking_years"), 0, 100)
    cigarettes = _number(result.get("cigarettes_per_day"), 0, 200)
    cessation = _number(result.get("quit_smoking_years"), 0, 100)
    pack_years = _number(result.get("pack_years"), 0, 500)
    if status == "never":
        smoking_years = cigarettes = cessation = pack_years = 0.0
    elif smoking_years is not None and cigarettes is not None:
        pack_years = round(smoking_years * cigarettes / 20, 1)
    return {
        "status": status,
        "smoking_years": smoking_years,
        "cigarettes_per_day": cigarettes,
        "cessation_years": cessation,
        "pack_years": pack_years,
    }


def normalize_comorbidities(result: dict[str, Any]) -> dict[str, int | None]:
    return {field: _binary(result.get(field)) for field in COMORBIDITIES}


def symptoms_prompt(chief_complaint: str, present_illness: str, past_history: str) -> str:
    return f"""您是一位专业的呼吸科医生，正在严格按照GOLD指南标准评估COPD患者的症状严重程度。

【主诉】
{chief_complaint}
【现病史】
{present_illness}
【既往史】
{past_history}

【GOLD指南标准化症状评估标准】
1. 咳嗽分组：轻度咳嗽(0)/严重咳嗽(1)/信息缺失无法判断(-1)
2. 咳痰分组：轻度咳痰(0)/严重咳痰(1)/信息缺失无法判断(-1)
3. 呼吸困难分组：无呼吸困难(0)/有呼吸困难(1)/信息缺失无法判断(-1)
4. 喘息分组：无喘息(0)/有喘息(1)/信息缺失无法判断(-1)
5. 胸闷分组：无胸闷(0)/有胸闷(1)/信息缺失无法判断(-1)
6. 发热分组：无发热(0)/有发热(1)/信息缺失无法判断(-1)
7. 乏力分组：无乏力(0)/有乏力(1)/信息缺失无法判断(-1)
8. 夜间症状分组：无夜间症状(0)/有夜间症状(1)/信息缺失无法判断(-1)

【急性加重天数判断规则】
1. 如果明确提到急性加重持续时间，直接使用（如“急性加重3天”→3）
2. 如果描述症状加重但未明确“急性加重”，根据症状持续时间判断（如“胸闷、气短1周”→7）
3. 优先考虑主诉中的时间信息，其次是现病史
4. 常见时间单位转换：1周=7天，1月=30天，半个月=15天
5. 如果提到“加重”但无具体时间，根据上下文判断（如“近日加重”按3天）
6. 如果无法取得具体天数，填0

急性加重字段：1=有急性加重，0=无急性加重，-1=信息缺失无法判断。

只返回一个完整JSON对象：
{{
  "symptom_groups": {{
    "咳嗽分组": "轻度咳嗽|严重咳嗽|信息缺失无法判断",
    "咳痰分组": "轻度咳痰|严重咳痰|信息缺失无法判断",
    "呼吸困难分组": "无呼吸困难|有呼吸困难|信息缺失无法判断",
    "喘息分组": "无喘息|有喘息|信息缺失无法判断",
    "胸闷分组": "无胸闷|有胸闷|信息缺失无法判断",
    "发热分组": "无发热|有发热|信息缺失无法判断",
    "乏力分组": "无乏力|有乏力|信息缺失无法判断",
    "夜间症状分组": "无夜间症状|有夜间症状|信息缺失无法判断"
  }},
  "acute_exacerbation": "0|1|-1",
  "acute_exacerbation_duration": "整数天数",
  "has_copd_history": "0|1|-1"
}}

时间提取示例：
1. “咳嗽、咳痰加重3天”→3
2. “胸闷、气短1周”→7
3. “呼吸困难加重半个月”→15
4. “近日症状加重”→3
5. “急性加重”但无时间→0
6. “慢性咳嗽，近期稳定”→0

最终输出只能是可由json.loads()直接解析的JSON对象，不要添加解释、说明或Markdown代码块。"""


def smoking_prompt(smoking_text: str, past_history: str) -> str:
    return f"""您是一位专业的呼吸科医生，正在分析患者的吸烟史信息。请综合吸烟史和既往史提取结构化信息。

【吸烟史】
{smoking_text}
【既往史】
{past_history}

字段：
1. 吸烟状态：0=从不吸烟，1=已戒烟，2=当前吸烟，-1=信息缺失无法判断
2. 吸烟年限（年）：未提及为-1
3. 每日吸烟量（支/天）：未提及为-1
4. 戒烟年限（年）：未提及为-1
5. pack-years：未提及或无法计算为-1

判断规则：
- 只有明确“从不吸烟”“无吸烟史”或“否认吸烟史”时，状态和全部定量字段设为0。
- 文本完全没有吸烟信息或无法判断吸烟状态时，全部字段设为-1。
- 明确有吸烟史但缺少某项定量信息时，只将缺少的字段设为-1。
- 只有吸烟年限和每日吸烟量都有明确数值时，才按(支/天÷20)×吸烟年限计算pack-years。
- 1月=1/12年，1天=1/365年。

示例：
- “否认吸烟史”→状态和全部定量字段为0
- “吸烟20年，每日20支，已戒烟5年”→状态1，20年，20支/天，戒烟5年，20 pack-years
- “有吸烟史”→状态2，其余定量字段为-1
- 空文本或“无特殊记载”→全部字段为-1

只返回一个完整JSON对象：
{{
  "smoking_status": "0|1|2|-1",
  "smoking_years": "数值或-1",
  "cigarettes_per_day": "数值或-1",
  "quit_smoking_years": "数值或-1",
  "pack_years": "数值或-1"
}}

最终输出只能是可由json.loads()直接解析的JSON对象。"""


def comorbidities_prompt(present_illness: str, past_history: str) -> str:
    return f"""您是一位专业的呼吸科医生，正在分析COPD患者的共病情况。

【现病史】
{present_illness}
【既往史】
{past_history}

请提取以下共病：糖尿病、高血压、高血脂、冠心病、心力衰竭、心房颤动、脑卒中、焦虑抑郁、骨质疏松、胃食管反流病、支气管扩张、肺癌、肺栓塞、肾功能不全、肝功能不全、贫血。

每个字段只能为0、1或-1：0=明确无，1=明确有，-1=信息不足或无法判断。仅根据文本中的明确诊断或描述判断，不要推测。

只返回包含以下全部键的一个完整JSON对象：
{{
  "diabetes": "0|1|-1",
  "hypertension": "0|1|-1",
  "hyperlipidemia": "0|1|-1",
  "coronary_heart_disease": "0|1|-1",
  "heart_failure": "0|1|-1",
  "atrial_fibrillation": "0|1|-1",
  "stroke": "0|1|-1",
  "anxiety_depression": "0|1|-1",
  "osteoporosis": "0|1|-1",
  "gastroesophageal_reflux": "0|1|-1",
  "bronchiectasis": "0|1|-1",
  "lung_cancer": "0|1|-1",
  "pulmonary_embolism": "0|1|-1",
  "renal_insufficiency": "0|1|-1",
  "hepatic_insufficiency": "0|1|-1",
  "anemia": "0|1|-1"
}}

最终输出只能是可由json.loads()直接解析的JSON对象。"""


def call_ollama_generate(
    endpoint: str,
    model: str,
    prompt: str,
    timeout: int = 120,
    retries: int = 3,
    retry_delay: float = 3.0,
    backoff_factor: float = 1.5,
) -> dict[str, Any]:
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 2000},
    }
    last_error: Exception | None = None
    session = requests.Session()
    session.trust_env = False
    for attempt in range(retries):
        try:
            response = session.post(endpoint, json=payload, timeout=timeout * backoff_factor**attempt)
            response.raise_for_status()
            content = response.json()["response"]
            return robust_json_parse(content)
        except (requests.RequestException, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt + 1 < retries:
                time.sleep(retry_delay)
    raise RuntimeError("Structured extraction failed") from last_error


def empty_extraction() -> dict[str, Any]:
    return {
        "duration_days": None,
        "symptoms": {field: None for field in SYMPTOMS},
        "acute_exacerbation": None,
        "has_copd_history": None,
        "smoking": {
            "status": None,
            "smoking_years": None,
            "cigarettes_per_day": None,
            "cessation_years": None,
            "pack_years": None,
        },
        "comorbidities": {field: None for field in COMORBIDITIES},
    }


def extract_record(
    endpoint: str,
    model: str,
    chief_complaint: str,
    present_illness: str,
    past_history: str,
    smoking_history: str,
    timeout: int = 120,
    retries: int = 3,
) -> dict[str, Any]:
    result = empty_extraction()
    symptom_text = chief_complaint.strip() or present_illness.strip() or past_history.strip()
    if symptom_text:
        raw = call_ollama_generate(
            endpoint,
            model,
            symptoms_prompt(chief_complaint, present_illness, past_history),
            timeout,
            retries,
        )
        result.update(normalize_symptoms(raw))
    if smoking_history.strip() or past_history.strip():
        raw = call_ollama_generate(
            endpoint,
            model,
            smoking_prompt(smoking_history, past_history),
            timeout,
            retries,
        )
        result["smoking"] = normalize_smoking(raw)
    if present_illness.strip() or past_history.strip():
        raw = call_ollama_generate(
            endpoint,
            model,
            comorbidities_prompt(present_illness, past_history),
            timeout,
            retries,
        )
        result["comorbidities"] = normalize_comorbidities(raw)

    combined = f"{chief_complaint}\n{present_illness}"
    reasons = []
    if re.search(r"小时|钟头", combined):
        reasons.append("hour_expression")
    if len(re.findall(r"\d+(?:\.\d+)?\s*(?:天|日|周|星期|小时|月|年)", combined)) > 1:
        reasons.append("multiple_duration_expressions")
    result["duration_manual_review"] = bool(reasons)
    result["duration_review_reason"] = ";".join(reasons) if reasons else None
    return result


def flatten(result: dict[str, Any], model: str) -> dict[str, Any]:
    flat = {
        "extraction_model": model,
        "duration_days": result["duration_days"],
        "duration_manual_review": result.get("duration_manual_review", False),
        "duration_review_reason": result.get("duration_review_reason"),
        "acute_exacerbation": result.get("acute_exacerbation"),
        "has_copd_history": result.get("has_copd_history"),
    }
    flat.update({f"symptom_{key}": value for key, value in result["symptoms"].items()})
    flat.update({f"smoking_{key}": value for key, value in result["smoking"].items()})
    flat.update({f"comorbidity_{key}": value for key, value in result["comorbidities"].items()})
    return flat


def read_table(path: Path) -> pd.DataFrame:
    return pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path)


def write_table(data: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".xlsx":
        data.to_excel(path, index=False)
    else:
        data.to_csv(path, index=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract COPD symptoms, smoking history and comorbidities.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--chief-complaint", default="chief_complaint")
    parser.add_argument("--present-illness", default="present_illness")
    parser.add_argument("--past-history", default="past_history")
    parser.add_argument("--smoking-history", default="吸烟史")
    parser.add_argument("--retain-columns", nargs="*", default=[])
    parser.add_argument("--model", default="gemma3:27b-it-qat")
    parser.add_argument("--endpoint", default="http://127.0.0.1:11434/api/generate")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--retries", type=int, default=3)
    args = parser.parse_args()

    data = read_table(args.input)
    text_columns = [args.chief_complaint, args.present_illness, args.past_history, args.smoking_history]
    missing = [column for column in text_columns + args.retain_columns if column not in data.columns]
    if missing:
        raise KeyError(f"Missing input columns: {missing}")

    extracted = []
    for row in data[text_columns].fillna("").astype(str).itertuples(index=False, name=None):
        result = extract_record(args.endpoint, args.model, *row, args.timeout, args.retries)
        extracted.append(flatten(result, args.model))

    retained = data[args.retain_columns].reset_index(drop=True) if args.retain_columns else pd.DataFrame(index=data.index)
    write_table(pd.concat([retained, pd.DataFrame(extracted)], axis=1), args.output)


if __name__ == "__main__":
    main()
