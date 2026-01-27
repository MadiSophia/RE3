<p align="center">
  <img src="images/RE3.png" alt="Project banner" width="500">
</p>

# RE3: Resistance, Recovery, and Resilience Metric Pipeline 

This repository contains a flexible  Python-based workflow to generate composited  products for Switzerland (from local FORCE Sentinel-2 in  the FORM group at ETHZ) and compute forest resistance, recovery, and resilience metrics using Swiss NFI data (or any point data locations). The original Sentinel-2 data comes from [Koch et al. (2024)](https://www.envidat.ch/#/metadata/sentinel-2-time-series-of-switzerland).

## Requirements
- Anaconda or Miniconda
- Git
- Python and all required libraries are installed via the conda environment.

---

##  1 Create the conda environment
From the repository root, create the environment using the provided yml file:

```bash        
conda env create -f force_mo_environment.yml
conda activate force_mo_environment
```
##  2 Composite images
Go to Script 1, this will alow you to composite desired images for for selected years,  date windows, bands/indices (EVI, NDVI, and NDMI), and tiles once the paths/paramters are set.

```python
from pathlib import Path

in_root = Path(r"M:\FORCE_Sentinel_2_TSA_2017_2023\level3\tsa\real_values_flagged")
out_root = Path(r"S:\mbrown\Madi_sentinel_2_comp")

years = list(range(2017, 2024))

date_windows = [
    {"name": "aug", "start_mmdd": "08-01", "end_mmdd": "08-31"},
]

output_vars = ["CCI", "NIR", "GRN", "SW1"]

# ----------------------------
# Tile selection find gpkg in repository so you can better identify tile locations
# ----------------------------
# Set to None to process all tiles
# Or provide a list like ["X1234_Y5678", "X2345_Y6789"]
selected_tiles: list[str] | None = None

```
## 3 Extract NFI data
Go to Script 2 and download grid .gpkg from this repository  set set desired paths on local machine for NFI data, desired indices to extract, and  were you want csv containing indices to output (if you have already matched your nfi data to gpkg you can comment this part out)
```python
nfi_path = Path(r"C:\Users\mabrown\Desktop\P6_admin\nfi_data\correct_NFI.shp")
grid_path = Path(r"S:\mbrown\FORCE_TSA_processing\grid_ch.gpkg")

# Root folder where your processed composites live
comp_root = Path(r"S:\mbrown\Madi_sentinel_2_comp")

# Output csv
out_csv = comp_root / "nfi_raster_FORCE.csv"

# Which products to extract (must match folder names under comp_root)
products = ["CCI", "NIR", "GRN", "SW1", "NDVI", "EVI"]

# Which years/windows to extract
years = list(range(2017, 2023))
windows = ["aug"]  # match your date_windows "name"
```
##  4 Compute resistance, recovery, and resilience 
Go to script 3 and set desired paths to location of csv from previous step, set disturbances years and calculate metrics of compute resistance, recovery, and resilience. Yay! Now you are ready for further analysis:)
  <img src="images/metrics.png" alt="metric" width="500">
</p>

```python
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
```
## Step 5 Tree species metrics comparisons (optional)
You now have an analysis ready csv containing the desired metrics and are now ready for analysis. In script 4, we will switch it up and compare the varying tree species metrics using R ggplot2 and conduct a [Kruskal-Wallis](http://dx.doi.org/10.1080/01621459.1952.10483441) test (95 % CI) to see if there are statistically significant different between 11 dominant species in Switzerland . Change input and output file paths to your own, then set parameters for metrics, indices, and years you want to visualize. You end up with a series of plots for each metric (see below). 
<p align="center">
  <img src="images/plot.png" alt="plot" width="400">
</p>

```R
# Uncomment only if you need to install packages
# install.packages(c("dplyr","tidyr","ggplot2","forcats","rstatix","multcompView"))

library(dplyr)
library(tidyr)
library(ggplot2)
library(forcats)
library(rstatix)
library(multcompView)

rm(list = ls())

# =========================
# User settings
# =========================
metric_data <- "S:/mbrown/Madi_sentinel_2_comp/nfi_indices_metrics_clean.csv"

# Base output folder (all subfolders will be created inside this)
out_dir <- "S:/mbrown/Madi_sentinel_2_comp/metric_plots"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


#11 most dominant species 
species_order <- c(
  "Abies alba","Larix decidua", "Picea abies", "Pinus cembra",
  "Pinus sylvestris","Acer pseudoplatanus", "Betula pendula",
  "Castanea sativa","Fagus sylvatica", "Fraxinus excelsior", "Quercus petraea"
)

# Set any of these to NULL to run everything available
indices_to_run <- c(NULL)  # or NULL
metrics_to_run <- c(NULL)             # Rs Rc Rr Pe, or NULL
years_to_run   <- c(2018)                   # or NULL

plot_width_in  <- 10
plot_height_in <- 6.5
plot_dpi       <- 300
```
## References

Bloom, C. K., Koch, T. L., Meusburger, K., Zweifel, R., Walthert, L., Etzold, S., Scherrer, D., Wilhelm, M., Kahmen, A., & Baltensweiler, A. (2025). Towards near real-time drought stress assessment in Europe’s temperate forests – comparing remote sensing time series with continuous in-situ tree-level measurements. *Ecological Indicators*, 177, 113757. https://doi.org/10.1016/j.ecolind.2025.113757

Claverie, M., Ju, J., Masek, J. G., Dungan, J. L., Vermote, E. F., Roger, J.-C., Skakun, S. V., & Justice, C. (2018). The harmonized Landsat and Sentinel-2 surface reflectance data set. *Remote Sensing of Environment*, 219, 145–161. https://doi.org/10.1016/j.rse.2018.09.002

Frantz, D., Schug, F., Okujeni, A., Navacchi, C., Wagner, W., van der Linden, S., & Hostert, P. (2021). National-scale mapping of building height using Sentinel-1 and Sentinel-2 time series. *Remote Sensing of Environment*, 252, 112128. https://doi.org/10.1016/j.rse.2020.112128

Gamon, J. A., Huemmrich, K. F., Wong, C. Y. S., et al. (2016). A remotely sensed pigment index reveals photosynthetic phenology in evergreen conifers. *Proceedings of the National Academy of Sciences*, 113(46), 13087–13092. https://doi.org/10.1073/pnas.1606162113

Gaudel, A., Languille, F., Delvit, J. M., Michel, J., Cournet, M., Poulain, V., & Youssefi, D. (2017). Sentinel-2 global reference image validation and application to multitemporal performances and high latitude digital surface model. *The International Archives of the Photogrammetry, Remote Sensing and Spatial Information Sciences*, XLII-1/W1, 447–454. https://doi.org/10.5194/isprs-archives-xlii-1-w1-447-2017

Holling, C. S., & Meffe, G. K. (1996). Command and control and the pathology of natural resource management. *Conservation Biology*, 10(2), 328–337. https://www.jstor.org/stable/2386849

Ingrisch, J., & Bahn, M. (2018). Towards a comparable quantification of resilience. *Trends in Ecology & Evolution*, 33(4), 251–259. https://doi.org/10.1016/j.tree.2018.01.013

Koch, T. L., Hobi, M. L., Morsdorf, F., Damm, A., Weber, D., Rüetschi, M., Wegner, J. D., & Waser, L. T. (2025). Assessing intraspecific variation of tree species based on Sentinel-2 vegetation indices across space and time. *Remote Sensing*, 17(12), 2094. https://doi.org/10.3390/rs17122094

Lloret, F., Keeling, E. G., & Sala, A. (2011). Components of tree resilience: effects of successive low-growth episodes in old ponderosa pine forests. *Oikos*, 120(12), 1909–1920. https://doi.org/10.1111/j.1600-0706.2011.19372.x

Main-Knorn, M., Pflug, B., Louis, J., Debaecker, V., Müller-Wilm, U., & Gascon, F. (2017). Sen2Cor for Sentinel-2. In L. Bruzzone, F. Bovolo, & J. A. Benediktsson (Eds.), *Proceedings of SPIE* (Vol. 10427, 1042704). https://doi.org/10.1117/12.2278218

Pasquarella, V. J., Brown, C. F., Czerwinski, W., & Rucklidge, W. J. (2023). Comprehensive quality assessment of optical satellite imagery using weakly supervised video learning. https://doi.org/10.1109/cvprw59228.2023.00206

Poussin, C., Timoner, P., Peduzzi, P., & Giuliani, G. (2025). Past and future trends in Swiss snow cover: multi-decades analysis using the snow observation from space algorithm. *Frontiers in Remote Sensing*, 6. https://doi.org/10.3389/frsen.2025.1542181

Senf, C., Seidl, R., & Poulter, B. (2021). Post-disturbance canopy recovery and the resilience of Europe’s forests. *Global Ecology and Biogeography*, 31(1), 25–36. https://doi.org/10.1111/geb.13406

Skakun, S., Wevers, J., Brockmann, C., Doxani, G., Aleksandrov, M., Batič, M., Frantz, D., Gascon, F., Gómez-Chova, L., Hagolle, O., López-Puigdollers, D., Louis, J., Lubej, M., Mateo-García, G., Osman, J., Peressutti, D., Pflug, B., Puc, J., Richter, R., & Roger, J.-C. (2022). Cloud mask intercomparison exercise (CMIX): an evaluation of cloud masking algorithms for Landsat 8 and Sentinel-2. *Remote Sensing of Environment*, 274, 112990. https://doi.org/10.1016/j.rse.2022.112990

Sturm, J., Santos, M. J., Schmid, B., & Damm, A. (2022). Satellite data reveal differential responses of Swiss forests to unprecedented 2018 drought. *Global Change Biology*, 28(9), 2956–2978. https://doi.org/10.1111/gcb.16136

Trotto, T., Coops, N. C., Achim, A., & Gergel, S. E. (2025). Spectral remote sensing reveals forest structural characteristics resilient to spruce budworm infestations. *Ecological Indicators*, 181, 114382. https://doi.org/10.1016/j.ecolind.2025.114382

