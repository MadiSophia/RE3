# FORM resilience, recovery and resistance pipeline

This repository contains a Python-based workflow to generate mosaiced FORCE time series products for Switzerland (from local FORCE products in form) and compute forest resilience, recovery, and resistance metrics using Swiss NFI data (or any point data locations).

## Requirements
- Anaconda or Miniconda
- Git

Python and all required libraries are installed via the conda environment.

---

## 1) Create the conda environment
From the repository root, create the environment using the provided yml file:

```bash
conda env create -f force_mo_environment.yml

conda activate force_mo_environment

## 2) Mosaicing images
Mosaic local FORCE time series products for selected years, date windows, and variables.

```python
from pathlib import Path

in_root = Path(r"M:\FORCE_Sentinel_2_TSA_2017_2023\level3\tsa\real_values_flagged")
out_root = Path(r"S:\mbrown\Madi_sentinel_2_comp")

years = list(range(2017, 2024))

date_windows = [
    {"name": "aug", "start_mmdd": "08-01", "end_mmdd": "08-31"},
]

output_vars = ["CCI", "NIR", "GRN", "SW1"]

