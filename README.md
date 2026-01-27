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

## 1) Create the conda environment

