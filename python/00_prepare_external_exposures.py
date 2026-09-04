#!/usr/bin/env python
from __future__ import annotations

import argparse
import re
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.mask import mask

DATE_PATTERNS = (r"(?P<date>20\d{6})", r"(?P<date>20\d{2}[-_]\d{2}[-_]\d{2})")


def date_from_name(path: Path) -> pd.Timestamp:
    for pattern in DATE_PATTERNS:
        match = re.search(pattern, path.stem)
        if match:
            return pd.to_datetime(match.group("date").replace("_", "-"), errors="raise")
    raise ValueError(f"No date found in filename: {path.name}")


def valid_mean(values: np.ndarray, nodata: float | None) -> float:
    values = np.asarray(values, dtype=float)
    if nodata is not None:
        values[values == nodata] = np.nan
    values[~np.isfinite(values)] = np.nan
    return float(np.nanmean(values)) if np.isfinite(values).any() else np.nan


def aggregate_rasters(
    raster_dir: Path,
    counties_path: Path,
    county_id: str,
    variable: str,
    output: Path,
    kelvin_to_celsius: bool,
    pascal_to_hpa: bool,
) -> None:
    counties = gpd.read_file(counties_path)[[county_id, "geometry"]].dropna(subset=[county_id, "geometry"])
    rows: list[dict[str, object]] = []
    files = sorted(p for p in raster_dir.rglob("*") if p.suffix.lower() in {".tif", ".tiff"})
    if not files:
        raise FileNotFoundError(f"No GeoTIFF files found under {raster_dir}")
    for raster_path in files:
        date = date_from_name(raster_path)
        with rasterio.open(raster_path) as src:
            geo = counties.to_crs(src.crs)
            for record in geo.itertuples(index=False):
                county_value = getattr(record, county_id)
                try:
                    array, _ = mask(src, [record.geometry], crop=True, filled=False)
                    values = array[0].filled(np.nan)
                    mean = valid_mean(values, src.nodata)
                except ValueError:
                    mean = np.nan
                if kelvin_to_celsius and np.isfinite(mean):
                    mean -= 273.15
                if pascal_to_hpa and np.isfinite(mean):
                    mean /= 100.0
                rows.append({county_id: county_value, "date": date, variable: mean})
    result = pd.DataFrame(rows).sort_values([county_id, "date"])
    output.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(output, index=False)


def expand_weekly_influenza(
    input_path: Path,
    output: Path,
    week_start: str,
    week_end: str | None,
    interpolate: bool,
) -> None:
    data = pd.read_excel(input_path) if input_path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(input_path)
    data[week_start] = pd.to_datetime(data[week_start], errors="raise")
    if week_end:
        data[week_end] = pd.to_datetime(data[week_end], errors="raise")
    else:
        week_end = "__week_end"
        data[week_end] = data[week_start] + pd.Timedelta(days=6)
    value_cols = [c for c in data.columns if c not in {week_start, week_end}]
    rows: list[pd.Series] = []
    for _, row in data.iterrows():
        for date in pd.date_range(row[week_start], row[week_end], freq="D"):
            expanded = row[value_cols].copy()
            expanded["date"] = date
            rows.append(expanded)
    daily = pd.DataFrame(rows).sort_values("date").drop_duplicates("date", keep="last")
    if interpolate:
        numeric = daily[value_cols].select_dtypes(include="number").columns
        daily[numeric] = daily[numeric].interpolate(limit_direction="both")
    output.parent.mkdir(parents=True, exist_ok=True)
    daily.to_csv(output, index=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    raster = sub.add_parser("raster-to-county")
    raster.add_argument("--raster-dir", type=Path, required=True)
    raster.add_argument("--counties", type=Path, required=True)
    raster.add_argument("--county-id", required=True)
    raster.add_argument("--variable", required=True)
    raster.add_argument("--output", type=Path, required=True)
    raster.add_argument("--kelvin-to-celsius", action="store_true")
    raster.add_argument("--pascal-to-hpa", action="store_true")

    flu = sub.add_parser("influenza-weekly-to-daily")
    flu.add_argument("--input", type=Path, required=True)
    flu.add_argument("--output", type=Path, required=True)
    flu.add_argument("--week-start", default="week_start")
    flu.add_argument("--week-end")
    flu.add_argument("--interpolate", action="store_true")

    args = parser.parse_args()
    if args.command == "raster-to-county":
        aggregate_rasters(args.raster_dir, args.counties, args.county_id, args.variable, args.output, args.kelvin_to_celsius, args.pascal_to_hpa)
    else:
        expand_weekly_influenza(args.input, args.output, args.week_start, args.week_end, args.interpolate)


if __name__ == "__main__":
    main()
