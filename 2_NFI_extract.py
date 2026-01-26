from __future__ import annotations

import re
from pathlib import Path
import logging
import numpy as np
import pandas as pd
import geopandas as gpd
import rasterio

# ----------------------------
# User paths
# ----------------------------
nfi_path = Path(r"C:\Users\mabrown\Desktop\P6_admin\nfi_data\correct_NFI.shp")
grid_path = Path(r"S:\mbrown\FORCE_TSA_processing\grid_ch.gpkg")

# Root folder where your processed composites live
comp_root = Path(r"S:\mbrown\Madi_sentinel_2_comp")

# Output csv
out_csv = comp_root / "nfi_raster_FORCE.csv"

# Which products to extract (must match folder names under comp_root)
products = ["CCI", "NIR", "GRN", "SW1", "NDVI"]

# Which years/windows to extract
years = list(range(2017, 2024))
windows = ["aug"]  # match your date_windows "name"

# Nodata handling
out_nodata = -9999.0
nan_if_nodata = True

# ----------------------------
# Logging
# ----------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s"
)

tile_pat = re.compile(r"X\d{4}_Y\d{4}", re.IGNORECASE)

def guess_tile_column(grid: gpd.GeoDataFrame) -> str:
    """
    Find a column in grid that looks like a tile id (X####_Y####).
    If none found, we will create one from the first match across row values.
    """
    for col in grid.columns:
        if col == "geometry":
            continue
        vals = grid[col].astype(str).head(50).tolist()
        if any(tile_pat.fullmatch(v.strip()) for v in vals):
            return col
    return ""

def ensure_tile_id(grid: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    col = guess_tile_column(grid)
    if col:
        grid = grid.rename(columns={col: "tile_id"})
        grid["tile_id"] = grid["tile_id"].astype(str).str.strip()
        return grid

    # Fall back: try to derive tile_id from any attribute that contains X####_Y####
    def derive(row) -> str | None:
        for c in grid.columns:
            if c == "geometry":
                continue
            s = str(row[c])
            m = tile_pat.search(s)
            if m:
                return m.group(0)
        return None

    grid = grid.copy()
    grid["tile_id"] = grid.apply(derive, axis=1)
    return grid

def sample_raster_at_point(raster_path: Path, x: float, y: float) -> float:
    with rasterio.open(raster_path) as ds:
        val = list(ds.sample([(x, y)]))[0][0]
        if nan_if_nodata and ds.nodata is not None and val == ds.nodata:
            return np.nan
        if nan_if_nodata and val == out_nodata:
            return np.nan
        return float(val)

def build_raster_path(tile_id: str, product: str, year: int, window: str) -> Path | None:
    """
    Finds the expected raster for (tile, product, year, window).
    Uses a glob to tolerate minor filename differences.
    """
    folder = comp_root / product / str(year) / window
    if not folder.exists():
        return None

    # Expected filename pattern begins with tile and contains product + year + window
    candidates = sorted(folder.glob(f"{tile_id}_{product}_{year}_{window}_*_median.tif"))
    if candidates:
        return candidates[0]

    # Fallback if you renamed products (e.g. NDVI folder contains NDVI product)
    candidates = sorted(folder.glob(f"{tile_id}_*_{year}_{window}_*_median.tif"))
    return candidates[0] if candidates else None

def main() -> None:
    # Load data
    logging.info("Reading NFI points")
    nfi = gpd.read_file(nfi_path)

    logging.info("Reading grid tiles")
    grid = gpd.read_file(grid_path)

    # Ensure tile_id exists
    grid = ensure_tile_id(grid)
    if "tile_id" not in grid.columns or grid["tile_id"].isna().all():
        raise ValueError(
            "Could not find or derive a tile id column in grid_ch.gpkg. "
            "Make sure it has an attribute like X0060_Y0063."
        )

    # Reproject points to grid CRS
    if nfi.crs != grid.crs:
        logging.info("Reprojecting NFI to grid CRS")
        nfi = nfi.to_crs(grid.crs)

    # Keep points only
    nfi_pts = nfi[nfi.geometry.type == "Point"].copy()
    if nfi_pts.empty:
        raise ValueError("No point geometries found in NFI layer.")

    # Spatial join: point -> tile polygon
    logging.info("Spatial join points to tiles")
    joined = gpd.sjoin(
        nfi_pts,
        grid[["tile_id", "geometry"]],
        how="left",
        predicate="within",
    )

    # If some points are exactly on boundary, 'within' can miss them. Try 'intersects' for those.
    missing = joined["tile_id"].isna()
    if missing.any():
        logging.info(f"{missing.sum()} points not matched with 'within', retrying with 'intersects'")
        retry = gpd.sjoin(
            joined.loc[missing].drop(columns=["index_right"], errors="ignore"),
            grid[["tile_id", "geometry"]],
            how="left",
            predicate="intersects",
        )
        joined.loc[missing, "tile_id"] = retry["tile_id"].values

    still_missing = joined["tile_id"].isna().sum()
    if still_missing:
        logging.warning(f"{still_missing} points could not be assigned to any tile. They will remain NaN in outputs.")

    # Prepare output rows
    base_cols = [c for c in joined.columns if c not in ["geometry", "index_right"]]
    results = []

    # Cache raster paths so we don’t glob repeatedly
    raster_cache: dict[tuple[str, str, int, str], Path | None] = {}

    logging.info("Sampling rasters by tile")
    for idx, row in joined.iterrows():
        tile_id = row.get("tile_id")
        geom = row.geometry

        out_row = {c: row[c] for c in base_cols}
        if tile_id is None or (isinstance(tile_id, float) and np.isnan(tile_id)):
            # No tile assignment
            for product in products:
                for year in years:
                    for window in windows:
                        out_row[f"{product}_{year}_{window}"] = np.nan
            results.append(out_row)
            continue

        x, y = geom.x, geom.y

        for product in products:
            for year in years:
                for window in windows:
                    col = f"{product}_{year}_{window}"

                    key = (str(tile_id), product, year, window)
                    if key not in raster_cache:
                        raster_cache[key] = build_raster_path(str(tile_id), product, year, window)

                    rp = raster_cache[key]
                    if rp is None or not rp.exists():
                        out_row[col] = np.nan
                        continue

                    try:
                        out_row[col] = sample_raster_at_point(rp, x, y)
                    except Exception as e:
                        logging.warning(f"Sample failed: point={idx} tile={tile_id} raster={rp.name} | {e}")
                        out_row[col] = np.nan

        results.append(out_row)

    df = pd.DataFrame(results)
    df.to_csv(out_csv, index=False)
    logging.info(f"Done. Wrote: {out_csv}")

if __name__ == "__main__":
    main()
