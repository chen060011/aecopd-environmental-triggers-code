#!/usr/bin/env python
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import pandas as pd


def load_reconstruction_module():
    path = Path(__file__).with_name("02_reconstruct_onset_and_phenotypes.py")
    spec = importlib.util.spec_from_file_location("onset_reconstruction", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_window_sets(
    data: pd.DataFrame,
    output_dir: Path,
    visit_date: str,
    duration: str,
    caps: list[int],
) -> pd.DataFrame:
    module = load_reconstruction_module()
    if not caps or any(cap < 0 for cap in caps):
        raise ValueError("Window caps must be non-negative integers")
    output_dir.mkdir(parents=True, exist_ok=True)
    summary = []
    for cap in sorted(set(caps)):
        result = module.derive(data, visit_date, duration, cap)
        filename = output_dir / f"onset_anchored_cap{cap}.csv"
        result.to_csv(filename, index=False)
        summary.append(
            {
                "window_cap_days": cap,
                "input_records": len(data),
                "included_records": len(result),
                "excluded_records": len(data) - len(result),
                "output_file": filename.name,
            }
        )
    audit = pd.DataFrame(summary)
    audit.to_csv(output_dir / "onset_window_audit.csv", index=False)
    return audit


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--visit-date", default="visit_date")
    parser.add_argument("--duration", default="duration_days")
    parser.add_argument("--caps", nargs="+", type=int, default=[14, 21, 30])
    args = parser.parse_args()

    data = pd.read_excel(args.input) if args.input.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(args.input)
    build_window_sets(data, args.output_dir, args.visit_date, args.duration, args.caps)


if __name__ == "__main__":
    main()
