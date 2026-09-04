#!/usr/bin/env python
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score, mean_absolute_error


def bootstrap_ci(values: np.ndarray, statistic, repeats: int = 1000, seed: int = 42) -> tuple[float, float]:
    rng = np.random.default_rng(seed)
    estimates = []
    for _ in range(repeats):
        sample = rng.integers(0, len(values), len(values))
        estimates.append(statistic(values[sample]))
    return tuple(np.quantile(estimates, [0.025, 0.975]))


def duration_metrics(data: pd.DataFrame, reference: str, prediction: str) -> dict[str, float]:
    pair = data[[reference, prediction]].apply(pd.to_numeric, errors="coerce").dropna().to_numpy(float)
    error = np.abs(pair[:, 1] - pair[:, 0])
    mae = float(error.mean())
    agreement = float((error <= 1).mean())
    mae_ci = bootstrap_ci(error, np.mean)
    agreement_ci = bootstrap_ci(error, lambda x: np.mean(x <= 1))
    return {
        "n": len(error), "mae": mae, "mae_ci_low": mae_ci[0], "mae_ci_high": mae_ci[1],
        "agreement_within_1_day": agreement,
        "agreement_ci_low": agreement_ci[0], "agreement_ci_high": agreement_ci[1],
    }


def classification_metrics(data: pd.DataFrame, reference: str, prediction: str) -> dict[str, float]:
    pair = data[[reference, prediction]].dropna()
    return {
        "n": len(pair),
        "accuracy": accuracy_score(pair[reference], pair[prediction]),
        "micro_f1": f1_score(pair[reference], pair[prediction], average="micro"),
        "macro_f1": f1_score(pair[reference], pair[prediction], average="macro"),
    }


def multilabel_metrics(data: pd.DataFrame, reference_prefix: str, prediction_prefix: str) -> dict[str, float]:
    ref_cols = sorted(c for c in data if c.startswith(reference_prefix))
    pred_cols = [prediction_prefix + c[len(reference_prefix):] for c in ref_cols]
    if not ref_cols or any(c not in data for c in pred_cols):
        raise KeyError("Reference and prediction multilabel columns do not align")
    reference = data[ref_cols].apply(pd.to_numeric, errors="coerce")
    prediction = data[pred_cols].apply(pd.to_numeric, errors="coerce")
    keep = ~(reference.isna() | prediction.isna()).any(axis=1)
    reference = reference.loc[keep].astype(int).to_numpy()
    prediction = prediction.loc[keep].astype(int).to_numpy()
    return {
        "n": len(reference),
        "micro_f1": f1_score(reference, prediction, average="micro", zero_division=0),
        "macro_f1": f1_score(reference, prediction, average="macro", zero_division=0),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--task", choices=["duration", "classification", "multilabel"], required=True)
    parser.add_argument("--reference")
    parser.add_argument("--prediction")
    parser.add_argument("--reference-prefix")
    parser.add_argument("--prediction-prefix")
    args = parser.parse_args()
    data = pd.read_excel(args.input) if args.input.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(args.input)
    if args.task == "duration":
        result = duration_metrics(data, args.reference, args.prediction)
    elif args.task == "classification":
        result = classification_metrics(data, args.reference, args.prediction)
    else:
        result = multilabel_metrics(data, args.reference_prefix, args.prediction_prefix)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([result]).to_csv(args.output, index=False)


if __name__ == "__main__":
    main()
