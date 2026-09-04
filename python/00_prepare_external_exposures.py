#!/usr/bin/env python
from __future__ import annotations

import argparse
import re
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
import xarray as xr
from rasterio.io import MemoryFile
from rasterio.mask import mask
from rasterio.transform import from_bounds

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


def transform_values(
    values: np.ndarray,
    kelvin_to_celsius: bool,
    pascal_to_hpa: bool,
    valid_min: float | None,
    valid_max: float | None,
) -> np.ndarray:
    values = np.asarray(values, dtype=float).copy()
    values[~np.isfinite(values)] = np.nan
    if kelvin_to_celsius:
        values -= 273.15
    if pascal_to_hpa:
        values /= 100.0
    if valid_min is not None:
        values[values < valid_min] = np.nan
    if valid_max is not None:
        values[values > valid_max] = np.nan
    return values


def county_rows_from_raster(
    source: rasterio.io.DatasetReader,
    counties: gpd.GeoDataFrame,
    county_id: str,
    date: pd.Timestamp,
    variable: str,
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    geo = counties.to_crs(source.crs)
    for record in geo.itertuples(index=False):
        try:
            array, _ = mask(source, [record.geometry], crop=True, filled=False)
            mean = valid_mean(array[0].filled(np.nan), source.nodata)
        except ValueError:
            mean = np.nan
        rows.append({county_id: getattr(record, county_id), "date": date, variable: mean})
    return rows


def aggregate_geotiffs(
    raster_dir: Path,
    counties_path: Path,
    county_id: str,
    variable: str,
    output: Path,
    kelvin_to_celsius: bool,
    pascal_to_hpa: bool,
    valid_min: float | None,
    valid_max: float | None,
) -> None:
    counties = gpd.read_file(counties_path)[[county_id, "geometry"]].dropna(subset=[county_id, "geometry"])
    files = sorted(path for path in raster_dir.rglob("*") if path.suffix.lower() in {".tif", ".tiff"})
    if not files:
        raise FileNotFoundError(f"No GeoTIFF files found under {raster_dir}")
    rows: list[dict[str, object]] = []
    for raster_path in files:
        date = date_from_name(raster_path)
        with rasterio.open(raster_path) as source:
            values = transform_values(
                source.read(1), kelvin_to_celsius, pascal_to_hpa, valid_min, valid_max
            )
            profile = source.profile.copy()
            profile.update(dtype="float64", nodata=np.nan, count=1)
            with MemoryFile() as memory, memory.open(**profile) as transformed:
                transformed.write(values, 1)
                rows.extend(county_rows_from_raster(transformed, counties, county_id, date, variable))
    write_rows(rows, county_id, variable, output)


def daily_netcdf_arrays(
    path: Path,
    data_variable: str,
    time_coordinate: str,
    latitude_coordinate: str,
    longitude_coordinate: str,
    daily_statistic: str,
    kelvin_to_celsius: bool,
    pascal_to_hpa: bool,
    valid_min: float | None,
    valid_max: float | None,
) -> list[tuple[pd.Timestamp, np.ndarray, np.ndarray, np.ndarray]]:
    with xr.open_dataset(path) as dataset:
        if data_variable not in dataset:
            raise KeyError(f"{data_variable} not found in {path.name}")
        array = dataset[data_variable].squeeze(drop=True)
        if time_coordinate in array.dims:
            resampler = array.resample({time_coordinate: "1D"})
            array = getattr(resampler, daily_statistic)(skipna=True)
        else:
            array = array.expand_dims({time_coordinate: [date_from_name(path)]})
        required = {time_coordinate, latitude_coordinate, longitude_coordinate}
        if not required.issubset(array.dims):
            raise ValueError(f"Expected dimensions {sorted(required)} in {path.name}; got {array.dims}")
        extra = [dim for dim in array.dims if dim not in required]
        if extra:
            raise ValueError(f"Unsupported extra dimensions in {path.name}: {extra}")
        array = array.transpose(time_coordinate, latitude_coordinate, longitude_coordinate)
        dates = pd.to_datetime(array[time_coordinate].values)
        latitudes = np.asarray(array[latitude_coordinate].values, dtype=float)
        longitudes = np.asarray(array[longitude_coordinate].values, dtype=float)
        if np.nanmax(longitudes) > 180:
            longitudes = ((longitudes + 180) % 360) - 180
        lat_order = np.argsort(latitudes)[::-1]
        lon_order = np.argsort(longitudes)
        latitudes = latitudes[lat_order]
        longitudes = longitudes[lon_order]
        output = []
        for index, date in enumerate(dates):
            values = np.asarray(array.isel({time_coordinate: index}).values, dtype=float)
            values = values[np.ix_(lat_order, lon_order)]
            values = transform_values(
                values, kelvin_to_celsius, pascal_to_hpa, valid_min, valid_max
            )
            output.append((pd.Timestamp(date).normalize(), latitudes, longitudes, values))
        return output


def aggregate_netcdf(
    netcdf_dir: Path,
    counties_path: Path,
    county_id: str,
    data_variable: str,
    variable: str,
    output: Path,
    time_coordinate: str,
    latitude_coordinate: str,
    longitude_coordinate: str,
    daily_statistic: str,
    kelvin_to_celsius: bool,
    pascal_to_hpa: bool,
    valid_min: float | None,
    valid_max: float | None,
) -> None:
    counties = gpd.read_file(counties_path)[[county_id, "geometry"]].dropna(subset=[county_id, "geometry"])
    files = sorted(path for path in netcdf_dir.rglob("*") if path.suffix.lower() in {".nc", ".nc4"})
    if not files:
        raise FileNotFoundError(f"No NetCDF files found under {netcdf_dir}")
    rows: list[dict[str, object]] = []
    for path in files:
        for date, latitudes, longitudes, values in daily_netcdf_arrays(
            path, data_variable, time_coordinate, latitude_coordinate, longitude_coordinate,
            daily_statistic, kelvin_to_celsius, pascal_to_hpa, valid_min, valid_max,
        ):
            if len(latitudes) < 2 or len(longitudes) < 2:
                raise ValueError("At least two latitude and longitude coordinates are required")
            dx = float(np.median(np.diff(np.sort(longitudes))))
            dy = float(np.median(np.diff(np.sort(latitudes))))
            transform = from_bounds(
                float(longitudes.min() - dx / 2), float(latitudes.min() - dy / 2),
                float(longitudes.max() + dx / 2), float(latitudes.max() + dy / 2),
                len(longitudes), len(latitudes),
            )
            with MemoryFile() as memory, memory.open(
                driver="GTiff", height=len(latitudes), width=len(longitudes), count=1,
                dtype="float64", crs="EPSG:4326", transform=transform, nodata=np.nan,
            ) as raster:
                raster.write(values, 1)
                rows.extend(county_rows_from_raster(raster, counties, county_id, date, variable))
    write_rows(rows, county_id, variable, output)


def write_rows(rows: list[dict[str, object]], county_id: str, variable: str, output: Path) -> None:
    result = pd.DataFrame(rows)
    result[variable] = pd.to_numeric(result[variable], errors="coerce")
    result = result.groupby([county_id, "date"], as_index=False)[variable].mean().sort_values([county_id, "date"])
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
    value_cols = [column for column in data.columns if column not in {week_start, week_end}]
    rows: list[pd.Series] = []
    for _, row in data.iterrows():
        for date in pd.date_range(row[week_start], row[week_end], freq="D"):
            expanded = row[value_cols].copy()
            expanded["date"] = date
            rows.append(expanded)
    daily = pd.DataFrame(rows).sort_values("date").drop_duplicates("date", keep="last")
    daily = (
        daily.set_index("date")
        .reindex(pd.date_range(daily["date"].min(), daily["date"].max(), freq="D"))
        .rename_axis("date")
        .reset_index()
    )
    if interpolate:
        numeric = daily[value_cols].select_dtypes(include="number").columns
        daily[numeric] = daily[numeric].interpolate(method="linear", limit_area="inside")
    output.parent.mkdir(parents=True, exist_ok=True)
    daily.to_csv(output, index=False)


def merge_county_tables(inputs: list[Path], county_id: str, output: Path) -> None:
    merged: pd.DataFrame | None = None
    seen_values: set[str] = set()
    for path in inputs:
        table = pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path)
        if county_id not in table.columns or "date" not in table.columns:
            raise KeyError(f"{path.name} must contain {county_id} and date")
        table["date"] = pd.to_datetime(table["date"], errors="raise").dt.normalize()
        values = [column for column in table.columns if column not in {county_id, "date"}]
        duplicate = seen_values.intersection(values)
        if duplicate:
            raise ValueError(f"Duplicate value columns across inputs: {sorted(duplicate)}")
        seen_values.update(values)
        table = table.groupby([county_id, "date"], as_index=False)[values].mean(numeric_only=True)
        merged = table if merged is None else merged.merge(table, on=[county_id, "date"], how="outer")
    if merged is None:
        raise ValueError("At least one input table is required")
    output.parent.mkdir(parents=True, exist_ok=True)
    merged.sort_values([county_id, "date"]).to_csv(output, index=False)


def add_spatial_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--counties", type=Path, required=True)
    parser.add_argument("--county-id", required=True)
    parser.add_argument("--variable", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--kelvin-to-celsius", action="store_true")
    parser.add_argument("--pascal-to-hpa", action="store_true")
    parser.add_argument("--valid-min", type=float)
    parser.add_argument("--valid-max", type=float)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    geotiff = subparsers.add_parser("geotiff-to-county")
    geotiff.add_argument("--raster-dir", type=Path, required=True)
    add_spatial_arguments(geotiff)

    netcdf = subparsers.add_parser("netcdf-to-county")
    netcdf.add_argument("--netcdf-dir", type=Path, required=True)
    netcdf.add_argument("--data-variable", required=True)
    netcdf.add_argument("--time-coordinate", default="time")
    netcdf.add_argument("--latitude-coordinate", default="lat")
    netcdf.add_argument("--longitude-coordinate", default="lon")
    netcdf.add_argument("--daily-statistic", choices=["mean", "min", "max"], default="mean")
    add_spatial_arguments(netcdf)

    influenza = subparsers.add_parser("influenza-weekly-to-daily")
    influenza.add_argument("--input", type=Path, required=True)
    influenza.add_argument("--output", type=Path, required=True)
    influenza.add_argument("--week-start", default="week_start")
    influenza.add_argument("--week-end")
    influenza.add_argument("--interpolate", action="store_true")

    merge = subparsers.add_parser("merge-county-tables")
    merge.add_argument("--inputs", nargs="+", type=Path, required=True)
    merge.add_argument("--county-id", default="county_name")
    merge.add_argument("--output", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "geotiff-to-county":
        aggregate_geotiffs(
            args.raster_dir, args.counties, args.county_id, args.variable, args.output,
            args.kelvin_to_celsius, args.pascal_to_hpa, args.valid_min, args.valid_max,
        )
    elif args.command == "netcdf-to-county":
        aggregate_netcdf(
            args.netcdf_dir, args.counties, args.county_id, args.data_variable, args.variable,
            args.output, args.time_coordinate, args.latitude_coordinate, args.longitude_coordinate,
            args.daily_statistic, args.kelvin_to_celsius, args.pascal_to_hpa,
            args.valid_min, args.valid_max,
        )
    elif args.command == "influenza-weekly-to-daily":
        expand_weekly_influenza(
            args.input, args.output, args.week_start, args.week_end, args.interpolate
        )
    else:
        merge_county_tables(args.inputs, args.county_id, args.output)


if __name__ == "__main__":
    main()
