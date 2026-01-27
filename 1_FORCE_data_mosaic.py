from __future__ import annotations

from pathlib import Path
import re
import logging
from datetime import datetime, date
import time
import numpy as np
import rasterio
from rasterio.errors import RasterioIOError

# ----------------------------
# User config
# ----------------------------
in_root = Path(r"M:\FORCE_Sentinel_2_TSA_2017_2023\level3\tsa\real_values_flagged")
out_root = Path(r"S:\mbrown\Madi_sentinel_2_comp")

years = list(range(2017, 2023))

date_windows = [
    {"name": "aug", "start_mmdd": "08-01", "end_mmdd": "08-31"},
]

output_vars = ["CCI", "NIR", "GRN", "SW1"]
prefer_force_ndvi = True

out_nodata = -9999.0
write_tmp_suffix = ".tmp"
target_block = 256

open_retries = 3
retry_sleep_seconds = 2.0

# ----------------------------
# Tile selection find gpkg in repository so you can better identify tile locations
# ----------------------------
# Set to None to process all tiles
# Or provide a list like ["X1234_Y5678", "X2345_Y6789"]
selected_tiles: list[str] | None = None

# ----------------------------
# Logging
# ----------------------------
out_root.mkdir(parents=True, exist_ok=True)

bad_inputs_fp = out_root / "bad_inputs.txt"
bad_inputs_fp.write_text("", encoding="utf-8")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(out_root / "composite_log.txt", encoding="utf-8"),
    ],
)

def log_bad_input(fp: Path, reason: str) -> None:
    with bad_inputs_fp.open("a", encoding="utf-8") as f:
        f.write(f"{fp}\t{reason}\n")

# ----------------------------
# Patterns
# ----------------------------
tile_pat = re.compile(r"^X\d{4}_Y\d{4}$", re.IGNORECASE)

tif_pat = re.compile(
    r"^(?P<y0>\d{4})-(?P<y1>\d{4})_\d{3}-\d{3}_HL_TSA_SEN2L_(?P<var>[A-Z0-9]{3})_TSS\.tif$",
    re.IGNORECASE,
)

band_desc_pat = re.compile(r"^(?P<ymd>\d{8})_(?P<sensor>SEN2A|SEN2B)$", re.IGNORECASE)

# ----------------------------
# Helpers
# ----------------------------
def output_is_valid(fp: Path) -> bool:
    if not fp.exists():
        return False
    try:
        with rasterio.open(fp) as ds:
            _ = ds.read(1, window=((0, 1), (0, 1)))
        return True
    except Exception:
        return False

def iter_tile_dirs(root: Path) -> list[Path]:
    tiles = [p for p in root.iterdir() if p.is_dir() and tile_pat.match(p.name)]
    if selected_tiles is not None:
        sel = {t.upper() for t in selected_tiles}
        tiles = [p for p in tiles if p.name.upper() in sel]
    tiles.sort(key=lambda p: p.name)
    return tiles

def find_var_file(tile_dir: Path, year: int, var: str) -> Path | None:
    var = var.upper()
    exact, ranged = [], []

    for p in tile_dir.iterdir():
        if not p.is_file() or p.suffix.lower() != ".tif":
            continue
        m = tif_pat.match(p.name)
        if not m:
            continue
        y0, y1 = int(m.group("y0")), int(m.group("y1"))
        if m.group("var").upper() != var:
            continue
        if y0 == year and y1 == year:
            exact.append(p)
        elif y0 <= year <= y1:
            ranged.append(p)

    return sorted(exact or ranged)[0] if (exact or ranged) else None

def try_open_validate(fp: Path) -> rasterio.DatasetReader | None:
    last_err = None
    for i in range(open_retries):
        try:
            src = rasterio.open(fp)
            _ = src.read(1, window=((0, 1), (0, 1)))
            return src
        except Exception as e:
            last_err = e
            time.sleep(retry_sleep_seconds)
    log_bad_input(fp, str(last_err))
    return None

def band_date_map(src):
    out = {}
    for i, d in enumerate(src.descriptions, start=1):
        if not d:
            continue
        m = band_desc_pat.match(d.strip())
        if m:
            out[datetime.strptime(m.group("ymd"), "%Y%m%d").date()] = i
    return out

def parse_mmdd(mmdd):
    m, d = mmdd.split("-")
    return int(m), int(d)

def window_dates(date_map, year, s_mmdd, e_mmdd):
    sm, sd = parse_mmdd(s_mmdd)
    em, ed = parse_mmdd(e_mmdd)
    start, end = date(year, sm, sd), date(year, em, ed)
    return sorted(
        d for d in date_map
        if (d >= start and d <= end) or (end < start and (d >= start or d <= end))
    )

def read_band(src, idx):
    arr = src.read(idx).astype("float32", copy=False)
    if src.nodata is not None:
        arr[arr == src.nodata] = np.nan
    return arr

def median(stack):
    return np.nanmedian(np.stack(stack), axis=0).astype("float32")

def safe_index(a, b):
    with np.errstate(divide="ignore", invalid="ignore"):
        r = a / b
    r[~np.isfinite(r)] = np.nan
    return r.astype("float32")

def out_name(tile, prod, year, win, s, e):
    return f"{tile}_{prod}_{year}_{win}_{s.replace('-','')}_{e.replace('-','')}_median.tif"

def safe_unlink(fp):
    try:
        if fp.exists():
            fp.unlink()
    except Exception:
        pass

def _blk(v):
    return max(16, (min(target_block, v) // 16) * 16)

def write_atomic(fp, src, arr):
    fp.parent.mkdir(parents=True, exist_ok=True)
    tmp = fp.with_suffix(fp.suffix + write_tmp_suffix)
    safe_unlink(tmp)

    profile = src.profile.copy()
    profile.update(
        driver="GTiff",
        count=1,
        dtype="float32",
        nodata=out_nodata,
        compress="deflate",
        zlevel=6,
        BIGTIFF="IF_SAFER",
        tiled=True,
        blockxsize=_blk(src.width),
        blockysize=_blk(src.height),
    )

    out = arr.copy()
    out[np.isnan(out)] = out_nodata

    with rasterio.open(tmp, "w", **profile) as dst:
        dst.write(out, 1)

    safe_unlink(fp)
    tmp.replace(fp)

# ----------------------------
# Main
# ----------------------------
def main():
    for tile_dir in iter_tile_dirs(in_root):
        tile = tile_dir.name
        logging.info(f"Tile {tile}")

        for y in years:
            for win in date_windows:
                s, e, wname = win["start_mmdd"], win["end_mmdd"], win["name"]

                for var in output_vars:
                    out_fp = out_root / var / str(y) / wname / out_name(tile, var, y, wname, s, e)
                    if output_is_valid(out_fp):
                        logging.info(f"Skip existing {out_fp.name}")
                        continue

                    src = try_open_validate(find_var_file(tile_dir, y, var))
                    if src is None:
                        continue

                    dates = window_dates(band_date_map(src), y, s, e)
                    if not dates:
                        src.close()
                        continue

                    arr = median([read_band(src, band_date_map(src)[d]) for d in dates])
                    write_atomic(out_fp, src, arr)
                    src.close()

                # NDVI
                out_fp = out_root / "NDVI" / str(y) / wname / out_name(tile, "NDVI", y, wname, s, e)
                if output_is_valid(out_fp):
                    logging.info(f"Skip existing {out_fp.name}")
                    continue

                ndv = find_var_file(tile_dir, y, "NDV")
                if ndv:
                    src = try_open_validate(ndv)
                    if src:
                        dates = window_dates(band_date_map(src), y, s, e)
                        if dates:
                            arr = median([read_band(src, band_date_map(src)[d]) for d in dates])
                            write_atomic(out_fp, src, arr)
                        src.close()
                        continue

                nir = find_var_file(tile_dir, y, "NIR")
                red = find_var_file(tile_dir, y, "RED")
                if not nir or not red:
                    continue

                sn, sr = try_open_validate(nir), try_open_validate(red)
                if not sn or not sr:
                    continue

                common = set(window_dates(band_date_map(sn), y, s, e)) & set(
                    window_dates(band_date_map(sr), y, s, e)
                )
                if common:
                    arr = median([
                        safe_index(
                            read_band(sn, band_date_map(sn)[d]) - read_band(sr, band_date_map(sr)[d]),
                            read_band(sn, band_date_map(sn)[d]) + read_band(sr, band_date_map(sr)[d]),
                        )
                        for d in sorted(common)
                    ])
                    write_atomic(out_fp, sn, arr)

                sn.close()
                sr.close()

    logging.info("Processing complete")

if __name__ == "__main__":
    main()
