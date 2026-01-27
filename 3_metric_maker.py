import re
import numpy as np
import pandas as pd

# ------------------------------------------------------------
# compute resistance,resilience, and recovery metrics
# Output keeps only selected metadata + tile_id + new calculated columns
# ------------------------------------------------------------

# 1) Input and output
in_csv = r"S:\mbrown\Madi_sentinel_2_comp\nfi_raster_FORCE.csv"
out_csv = r"S:\mbrown\Madi_sentinel_2_comp\nfi_indices_metrics_clean.csv"

# 2) Replace nodata with NaN
nodata_values = [-9999, -9999.0]

# 3) Disturbance setup: (pre_year, event_year, recovery_year) 
#My drought was in 2018 for this example 
# If a needed year column does not exist, the metric becomes NaN
events = [
    (2017, 2018, 2021),
]

# I am calculate new during this script but you can comment them out
# 4) NDWI definition:
# "mcf" = (Green - NIR) / (Green + NIR)  (McFeeters NDWI)
# "gao" = (NIR - SW1)  / (NIR + SW1)     (often called NDMI)
ndwi_mode = "mcf"


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
def find_year_cols(df, prefix):
    """
    Match columns like:
      PREFIX_YYYY
      PREFIX_YYYY_aug
    Return dict: {year:int -> colname:str}
    """
    patt = re.compile(rf"^{re.escape(prefix)}_(\d{{4}})(?:_aug)?$")
    out = {}
    for c in df.columns:
        m = patt.match(c)
        if m:
            out[int(m.group(1))] = c
    return out


def safe_normdiff(a, b):
    # (a - b) / (a + b)
    a = a.astype(float)
    b = b.astype(float)
    den = a + b
    num = a - b
    return np.where((den == 0) | np.isnan(den) | np.isnan(num), np.nan, num / den)


def add_gndvi(df, nir_map, grn_map):
    """
    GNDVI = (NIR - Green) / (NIR + Green)
    Creates: GNDVI_YYYY_aug
    """
    years = set(nir_map.keys()).intersection(grn_map.keys())
    for y in sorted(years):
        df[f"GNDVI_{y}_aug"] = safe_normdiff(df[nir_map[y]], df[grn_map[y]])
    return df


def add_ndwi(df, nir_map, grn_map, sw1_map, mode="mcf"):
    """
    NDWI definitions:
      mode="mcf": (Green - NIR) / (Green + NIR)  (McFeeters NDWI)
      mode="gao": (NIR - SW1)  / (NIR + SW1)     (often NDMI)
    Creates: NDWI_YYYY_aug
    """
    if mode == "mcf":
        years = set(nir_map.keys()).intersection(grn_map.keys())
        for y in sorted(years):
            df[f"NDWI_{y}_aug"] = safe_normdiff(df[grn_map[y]], df[nir_map[y]])
    elif mode == "gao":
        years = set(nir_map.keys()).intersection(sw1_map.keys())
        for y in sorted(years):
            df[f"NDWI_{y}_aug"] = safe_normdiff(df[nir_map[y]], df[sw1_map[y]])
    else:
        raise ValueError("ndwi_mode must be 'mcf' or 'gao'")
    return df


def compute_metrics_for_index(df, index_prefix, events):
    """
    Explicit metric naming like your example:
      {index}_Rs_{event}
      {index}_Rc_{event}
      {index}_Rr_{event}
      {index}_Pe_{event}

    Definitions:
      Rs = Index_event / Index_pre
      Rc = Index_rec / Index_pre
      Rr = (Index_rec - Index_event) / (Index_pre * (rec - event))
      Pe = ((1 - Rs)^2) / (2 * Rr)
    """
    cols = find_year_cols(df, index_prefix)

    for pre, event, rec in events:
        pre_col = cols.get(pre)
        event_col = cols.get(event)
        rec_col = cols.get(rec)
        dt = rec - event

        rs_col = f"{index_prefix}_Rs_{event}"
        rc_col = f"{index_prefix}_Rc_{event}"
        rr_col = f"{index_prefix}_Rr_{event}"
        pe_col = f"{index_prefix}_Pe_{event}"

        # 4) Resistance (Rs)
        if pre_col and event_col:
            df[rs_col] = df[event_col] / df[pre_col]
        else:
            df[rs_col] = np.nan

        # 5) Recovery (Rc)
        if pre_col and rec_col:
            df[rc_col] = df[rec_col] / df[pre_col]
        else:
            df[rc_col] = np.nan

        # 6) Recovery rate (Rr)
        if pre_col and event_col and rec_col and dt != 0:
            df[rr_col] = (df[rec_col] - df[event_col]) / (df[pre_col] * dt)
        else:
            df[rr_col] = np.nan

        # 7) Persistence (Pe)
        df[pe_col] = ((1 - df[rs_col]) ** 2) / (2 * df[rr_col])
        df.loc[(df[rr_col] == 0) | np.isnan(df[rr_col]), pe_col] = np.nan

    return df


def discover_index_prefixes(df, exclude_prefixes=None):
    """
    Find prefixes that have at least 2 year columns like PREFIX_2017 or PREFIX_2017_aug.
    """
    if exclude_prefixes is None:
        exclude_prefixes = set()

    prefix_to_years = {}
    patt = re.compile(r"^([A-Za-z0-9]+)_(\d{4})(?:_aug)?$")

    for c in df.columns:
        m = patt.match(c)
        if not m:
            continue
        prefix = m.group(1)
        year = int(m.group(2))
        prefix_to_years.setdefault(prefix, set()).add(year)

    prefixes = [
        p for p, years in prefix_to_years.items()
        if len(years) >= 2 and p not in exclude_prefixes
    ]
    return sorted(prefixes)


# ------------------------------------------------------------
# Load
# ------------------------------------------------------------
df = pd.read_csv(in_csv)
for v in nodata_values:
    df = df.replace(v, np.nan)

# ------------------------------------------------------------
# New indices calculating and indice calculation section
# ------------------------------------------------------------
nir_map = find_year_cols(df, "NIR")
grn_map = find_year_cols(df, "GRN")
sw1_map = find_year_cols(df, "SW1")

df = add_gndvi(df, nir_map=nir_map, grn_map=grn_map)
df = add_ndwi(df, nir_map=nir_map, grn_map=grn_map, sw1_map=sw1_map, mode=ndwi_mode)

# ------------------------------------------------------------
# Compute metrics for all indices (exclude bands)
# ------------------------------------------------------------
band_prefixes = {"NIR", "GRN", "SW1"}
index_prefixes = discover_index_prefixes(df, exclude_prefixes=band_prefixes)

# Ensure the new indices are included even if only 1 year exists
for p in ["GNDVI", "NDWI"]:
    if p not in index_prefixes:
        index_prefixes.append(p)

for p in sorted(set(index_prefixes)):
    df = compute_metrics_for_index(df, p, events)

# ------------------------------------------------------------
# Keep only selected metadata + tile_id + new calculated columns (you can change if you want to keep more or less)
# ------------------------------------------------------------
base_cols = [
    "ID",
    "Year",
    "SiteID",
    "TreeID",
    "BART",
    "BARTgroup",
    "Species",
    "Species1",
    "SpeciesGro",
    "ForestCovS",
    "Yweg",
    "Xwgs",
    "X03.",
    "Y03.",
    "TreeNo",
    "SpeciesNo",
    "Shannon_In",
    "tile_id",
]

metric_patterns = ("_Rs_", "_Rc_", "_Rr_", "_Pe_")

# keep ONLY explicitly defined resilience metrics 
calculated_cols = [
    c for c in df.columns
    if any(p in c for p in metric_patterns)
]

final_cols = [c for c in base_cols if c in df.columns] + calculated_cols
df_final = df.loc[:, final_cols].copy()
# ------------------------------------------------------------
# Save
# ------------------------------------------------------------
df_final.to_csv(out_csv, index=False)

print("Saved:", out_csv)
print("Indices processed:", ", ".join(sorted(set(index_prefixes))))
print("Rows:", len(df_final), "Columns:", len(df_final.columns))
