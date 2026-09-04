#!/usr/bin/env python
from __future__ import annotations

import argparse
from collections.abc import Callable
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score


def quantile_ci(estimates: list[float]) -> tuple[float, float]:
    return tuple(float(value) for value in np.quantile(estimates, [0.025, 0.975]))


def bootstrap_pairs(
    reference: np.ndarray,
    prediction: np.ndarray,
    statistic: Callable[[np.ndarray, np.ndarray], float],
    repeats: int = 1000,
    seed: int = 42,
) -> tuple[float, float]:
    rng = np.random.default_rng(seed)
    estimates = []
    for _ in range(repeats):
        sample = rng.integers(0, len(reference), len(reference))
        estimates.append(float(statistic(reference[sample], prediction[sample])))
    return quantile_ci(estimates)


def duration_metrics(data: pd.DataFrame, reference: str, prediction: str) -> dict[str, float]:
    pair = data[[reference, prediction]].apply(pd.to_numeric, errors="coerce").dropna().to_numpy(float)
    ref, pred = pair[:, 0], pair[:, 1]
    error = np.abs(pred - ref)
    difference = pred - ref
    mae_ci = bootstrap_pairs(ref, pred, lambda x, y: np.mean(np.abs(y - x)))
    agreement_ci = bootstrap_pairs(ref, pred, lambda x, y: np.mean(np.abs(y - x) <= 1))
    bias = float(np.mean(difference))
    difference_sd = float(np.std(difference, ddof=1)) if len(difference) > 1 else np.nan
    return {
        "n": len(error),
        "mae": float(error.mean()),
        "mae_ci_low": mae_ci[0],
        "mae_ci_high": mae_ci[1],
        "agreement_within_1_day": float((error <= 1).mean()),
        "agreement_ci_low": agreement_ci[0],
        "agreement_ci_high": agreement_ci[1],
        "bland_altman_bias": bias,
        "bland_altman_lower_limit": bias - 1.96 * difference_sd,
        "bland_altman_upper_limit": bias + 1.96 * difference_sd,
    }


def numeric_metrics(data: pd.DataFrame, reference: str, prediction: str) -> dict[str, float]:
    pair = data[[reference, prediction]].apply(pd.to_numeric, errors="coerce").dropna().to_numpy(float)
    ref, pred = pair[:, 0], pair[:, 1]
    ci = bootstrap_pairs(ref, pred, lambda x, y: np.mean(np.abs(y - x)))
    return {"n": len(ref), "mae": float(np.mean(np.abs(pred - ref))), "mae_ci_low": ci[0], "mae_ci_high": ci[1]}


def classification_metrics(data: pd.DataFrame, reference: str, prediction: str) -> dict[str, float]:
    pair = data[[reference, prediction]].dropna()
    ref = pair[reference].astype(str).to_numpy()
    pred = pair[prediction].astype(str).to_numpy()
    metrics = {
        "accuracy": lambda x, y: accuracy_score(x, y),
        "micro_f1": lambda x, y: f1_score(x, y, average="micro", zero_division=0),
        "macro_f1": lambda x, y: f1_score(x, y, average="macro", zero_division=0),
    }
    output: dict[str, float] = {"n": len(ref)}
    for name, statistic in metrics.items():
        output[name] = float(statistic(ref, pred))
        low, high = bootstrap_pairs(ref, pred, statistic)
        output[f"{name}_ci_low"] = low
        output[f"{name}_ci_high"] = high
    return output


def multilabel_metrics(data: pd.DataFrame, reference_prefix: str, prediction_prefix: str) -> dict[str, float]:
    ref_cols = sorted(column for column in data if column.startswith(reference_prefix))
    pred_cols = [prediction_prefix + column[len(reference_prefix):] for column in ref_cols]
    if not ref_cols or any(column not in data for column in pred_cols):
        raise KeyError("Reference and prediction multilabel columns do not align")
    reference = data[ref_cols].apply(pd.to_numeric, errors="coerce")
    prediction = data[pred_cols].apply(pd.to_numeric, errors="coerce")
    keep = ~(reference.isna() | prediction.isna()).any(axis=1)
    ref = reference.loc[keep].astype(int).to_numpy()
    pred = prediction.loc[keep].astype(int).to_numpy()
    metrics = {
        "micro_f1": lambda x, y: f1_score(x, y, average="micro", zero_division=0),
        "macro_f1": lambda x, y: f1_score(x, y, average="macro", zero_division=0),
    }
    output: dict[str, float] = {"n": len(ref)}
    for name, statistic in metrics.items():
        output[name] = float(statistic(ref, pred))
        low, high = bootstrap_pairs(ref, pred, statistic)
        output[f"{name}_ci_low"] = low
        output[f"{name}_ci_high"] = high
    return output


def stability_metrics(data: pd.DataFrame, model: str, task: str, score: str) -> pd.DataFrame:
    working = data[[model, task, score]].copy()
    working[score] = pd.to_numeric(working[score], errors="coerce")
    result = working.dropna(subset=[score]).groupby([model, task])[score].agg(["count", "mean", "std"]).reset_index()
    result["cv_percent"] = np.where(result["mean"].ne(0), result["std"] / result["mean"] * 100, np.nan)
    return result.rename(columns={"count": "n_runs", "mean": "mean_score", "std": "within_task_sd"})


def bootstrap_one_sample(values: np.ndarray, statistic: Callable[[np.ndarray], float], repeats: int, seed: int) -> tuple[float, float]:
    rng = np.random.default_rng(seed)
    estimates = []
    for _ in range(repeats):
        sample = values[rng.integers(0, len(values), len(values))]
        estimates.append(float(statistic(sample)))
    return quantile_ci(estimates)


def system_metrics(
    data: pd.DataFrame,
    model: str,
    task: str,
    latency: str,
    tokens: str,
    success: str,
    repeats: int = 1000,
) -> pd.DataFrame:
    working = data[[model, task, latency, tokens, success]].copy()
    for column in (latency, tokens, success):
        working[column] = pd.to_numeric(working[column], errors="coerce")
    working["throughput_tokens_per_second"] = working[tokens] / working[latency]
    rows = []
    for (model_value, task_value), group in working.groupby([model, task]):
        latency_values = group[latency].dropna().to_numpy(float)
        throughput_values = group["throughput_tokens_per_second"].replace([np.inf, -np.inf], np.nan).dropna().to_numpy(float)
        success_values = group[success].dropna().to_numpy(float)
        row = {model: model_value, task: task_value, "n_runs": len(group)}
        for name, values, statistic in [
            ("latency_seconds", latency_values, np.mean),
            ("throughput_tokens_per_second", throughput_values, np.mean),
            ("success_rate", success_values, np.mean),
        ]:
            row[name] = float(statistic(values)) if len(values) else np.nan
            if len(values):
                low, high = bootstrap_one_sample(values, statistic, repeats, 42)
            else:
                low, high = np.nan, np.nan
            row[f"{name}_ci_low"] = low
            row[f"{name}_ci_high"] = high
        rows.append(row)
    return pd.DataFrame(rows)


def model_ranking(
    data: pd.DataFrame,
    model: str,
    symptoms_micro_f1: str,
    smoking_accuracy: str,
    comorbidity_micro_f1: str,
) -> pd.DataFrame:
    result = data[[model, symptoms_micro_f1, smoking_accuracy, comorbidity_micro_f1]].copy()
    for column in (symptoms_micro_f1, smoking_accuracy, comorbidity_micro_f1):
        result[column] = pd.to_numeric(result[column], errors="coerce")
    result["overall_score"] = result[[symptoms_micro_f1, smoking_accuracy, comorbidity_micro_f1]].mean(axis=1, skipna=False)
    result = result.sort_values("overall_score", ascending=False).reset_index(drop=True)
    result["rank"] = np.arange(1, len(result) + 1)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--task", choices=["duration", "numeric", "classification", "multilabel", "stability", "system", "ranking"], required=True)
    parser.add_argument("--reference")
    parser.add_argument("--prediction")
    parser.add_argument("--reference-prefix")
    parser.add_argument("--prediction-prefix")
    parser.add_argument("--model-column", default="model")
    parser.add_argument("--task-column", default="task")
    parser.add_argument("--score-column", default="score")
    parser.add_argument("--latency-column", default="latency_seconds")
    parser.add_argument("--tokens-column", default="generated_tokens")
    parser.add_argument("--success-column", default="success")
    parser.add_argument("--symptoms-micro-f1-column", default="symptoms_micro_f1")
    parser.add_argument("--smoking-accuracy-column", default="smoking_accuracy")
    parser.add_argument("--comorbidity-micro-f1-column", default="comorbidity_micro_f1")
    args = parser.parse_args()

    data = pd.read_excel(args.input) if args.input.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(args.input)
    if args.task == "duration":
        result = pd.DataFrame([duration_metrics(data, args.reference, args.prediction)])
    elif args.task == "numeric":
        result = pd.DataFrame([numeric_metrics(data, args.reference, args.prediction)])
    elif args.task == "classification":
        result = pd.DataFrame([classification_metrics(data, args.reference, args.prediction)])
    elif args.task == "multilabel":
        result = pd.DataFrame([multilabel_metrics(data, args.reference_prefix, args.prediction_prefix)])
    elif args.task == "stability":
        result = stability_metrics(data, args.model_column, args.task_column, args.score_column)
    elif args.task == "system":
        result = system_metrics(
            data, args.model_column, args.task_column, args.latency_column,
            args.tokens_column, args.success_column,
        )
    else:
        result = model_ranking(
            data, args.model_column, args.symptoms_micro_f1_column,
            args.smoking_accuracy_column, args.comorbidity_micro_f1_column,
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(args.output, index=False)


if __name__ == "__main__":
    main()
