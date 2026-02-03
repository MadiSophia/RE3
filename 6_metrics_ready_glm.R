# =================================================
# Prep data for GLMs:
# - join env + metrics
# - keep only environmental predictors needed for each metric type (Rs, Rc, Rr, Pe)
# - build climate indices for each metric type using only (pre, event, rec) years
# - combine elevation into the climate indices (no separate elevation predictor)
# - build one soil index block
# - output one ready-to-model table per metric type
# =================================================

library(dplyr)
library(stringr)

rm(list = ls())

# -----------------------------
# Inputs
# -----------------------------
env_path <- "S:/mbrown/Madi_sentinel_2_comp/clim_site_var.csv"
res_path <- "S:/mbrown/Madi_sentinel_2_comp/nfi_indices_metrics_clean.csv"

out_dir <- "S:/mbrown/Madi_sentinel_2_comp/glm_ready"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# -----------------------------
# Event definition (match your python code)
# -----------------------------
events <- tibble(
  pre   = 2017,
  event = 2018,
  rec   = 2021
)

# -----------------------------
# Read data
# -----------------------------
env <- read.csv(env_path)
res <- read.csv(res_path)

# -----------------------------
# Join by shared columns
# -----------------------------
shared_cols <- intersect(names(res), names(env))
data <- res %>%
  inner_join(env, by = shared_cols)

# -----------------------------
# Drop PDIR immediately
# -----------------------------
data <- data %>% select(-any_of("PDIR"))

# -----------------------------
# Fix typo in climate column name if present
# -----------------------------
if ("pcrp_2019" %in% names(data) && !"prcp_2019" %in% names(data)) {
  data <- data %>% rename(prcp_2019 = pcrp_2019)
}
if ("pcrp_2019" %in% names(data) && "prcp_2019" %in% names(data)) {
  data <- data %>% select(-pcrp_2019)
}

# -----------------------------
# Helper: safely compute rowMeans when some cols may be missing
# -----------------------------
safe_rowmean <- function(df, cols) {
  cols <- cols[cols %in% names(df)]
  if (length(cols) == 0) return(rep(NA_real_, nrow(df)))
  rowMeans(df[, cols, drop = FALSE], na.rm = TRUE)
}

# -----------------------------
# Soil index block
# Higher = more water available (less drought vulnerable)
# -----------------------------
soil_vars <- c("awc_1_25m", "soc_0_200", "gravel_0_200", "density_0_200")

soil_mat <- data %>%
  select(any_of(soil_vars)) %>%
  mutate(across(everything(), as.numeric))

if (ncol(soil_mat) > 0) {
  soil_z <- as.data.frame(scale(soil_mat))
  comb_terms <- list(
    awc  = if ("awc_1_25m" %in% names(soil_z)) soil_z$awc_1_25m else NULL,
    soc  = if ("soc_0_200" %in% names(soil_z)) soil_z$soc_0_200 else NULL,
    grav = if ("gravel_0_200" %in% names(soil_z)) -soil_z$gravel_0_200 else NULL,
    dens = if ("density_0_200" %in% names(soil_z)) -soil_z$density_0_200 else NULL
  )
  comb_mat <- do.call(cbind, comb_terms[!vapply(comb_terms, is.null, logical(1))])
  data$soil_index <- if (!is.null(comb_mat) && ncol(comb_mat) > 0) rowMeans(comb_mat, na.rm = TRUE) else NA_real_
} else {
  data$soil_index <- NA_real_
}

# -----------------------------
# Climate block per metric type (tmean + vpd) using only event years
# Elevation is combined into each climate index (no separate elevation predictor)
# -----------------------------
pre <- events$pre[1]
ev  <- events$event[1]
rec <- events$rec[1]

tpre <- paste0("tmean_", pre)
tev  <- paste0("tmean_", ev)
trec <- paste0("tmean_", rec)

vpre <- paste0("vpd_", pre)
vev  <- paste0("vpd_", ev)
vrec <- paste0("vpd_", rec)

# Window means (used for Pe)
data <- data %>%
  mutate(
    tmean_mean_window = safe_rowmean(., c(tpre, tev, trec)),
    vpd_mean_window   = safe_rowmean(., c(vpre, vev, vrec))
  )

# Rs: event minus pre
data$tmean_Rs_2018 <- if (tpre %in% names(data) && tev %in% names(data)) data[[tev]] - data[[tpre]] else NA_real_
data$vpd_Rs_2018   <- if (vpre %in% names(data) && vev %in% names(data)) data[[vev]] - data[[vpre]] else NA_real_

# Rc: recovery climate (absolute)
data$tmean_Rc_2018 <- if (trec %in% names(data)) as.numeric(data[[trec]]) else NA_real_
data$vpd_Rc_2018   <- if (vrec %in% names(data)) as.numeric(data[[vrec]]) else NA_real_

# Rr: recovery minus event
data$tmean_Rr_2018 <- if (trec %in% names(data) && tev %in% names(data)) data[[trec]] - data[[tev]] else NA_real_
data$vpd_Rr_2018   <- if (vrec %in% names(data) && vev %in% names(data)) data[[vrec]] - data[[vev]] else NA_real_

# Pe: integrated window means
data$tmean_Pe_2018 <- data$tmean_mean_window
data$vpd_Pe_2018   <- data$vpd_mean_window

# Helper: climate + elevation index
make_clim_elev_index <- function(df, cols, elev_col = "elevation") {
  use_cols <- cols[cols %in% names(df)]
  if (elev_col %in% names(df)) {
    use_cols <- c(use_cols, elev_col)
  }
  if (length(use_cols) == 0) {
    return(rep(NA_real_, nrow(df)))
  }
  z <- as.data.frame(scale(df[, use_cols, drop = FALSE]))
  rowMeans(z, na.rm = TRUE)
}

# Combined climate + elevation indices
data$clim_index_Rs_2018 <- make_clim_elev_index(data, c("tmean_Rs_2018", "vpd_Rs_2018"))
data$clim_index_Rc_2018 <- make_clim_elev_index(data, c("tmean_Rc_2018", "vpd_Rc_2018"))
data$clim_index_Rr_2018 <- make_clim_elev_index(data, c("tmean_Rr_2018", "vpd_Rr_2018"))
data$clim_index_Pe_2018 <- make_clim_elev_index(data, c("tmean_Pe_2018", "vpd_Pe_2018"))

# -----------------------------
# Build one dataset per metric type
# Response metrics: any PREFIX_(Rs|Rc|Rr|Pe)_2018
# -----------------------------
id_cols <- c("ID", "SiteID", "TreeID", "Year", "BART", "BARTgroup",
             "Species", "Species1", "SpeciesGro", "tile_id")
id_cols <- id_cols[id_cols %in% names(data)]

# Predictors to keep (elevation excluded because it's in clim_index)
base_predictors <- c(
  "soil_index",
  "slope_deg",  "folded_aspect",
  "forest_edge", "ForestCovS"
)
base_predictors <- base_predictors[base_predictors %in% names(data)]

prep_metric_df <- function(df, metric_type) {
  clim_col <- paste0("clim_index_", metric_type, "_2018")
  resp_cols <- names(df)[str_detect(names(df), paste0("^[A-Za-z0-9]+_", metric_type, "_2018$"))]
  
  keep <- c(id_cols, resp_cols, base_predictors, clim_col)
  
  df_out <- df %>%
    select(any_of(keep)) %>%
    filter(if_any(all_of(resp_cols), ~ !is.na(.x)))
  
  df_out
}

df_Rs <- prep_metric_df(data, "Rs")
df_Rc <- prep_metric_df(data, "Rc")
df_Rr <- prep_metric_df(data, "Rr")
df_Pe <- prep_metric_df(data, "Pe")

# -----------------------------
# Save ready-to-model tables
# -----------------------------
write.csv(df_Rs, file.path(out_dir, "glm_ready_Rs_2018.csv"), row.names = FALSE)
write.csv(df_Rc, file.path(out_dir, "glm_ready_Rc_2018.csv"), row.names = FALSE)
write.csv(df_Rr, file.path(out_dir, "glm_ready_Rr_2018.csv"), row.names = FALSE)
write.csv(df_Pe, file.path(out_dir, "glm_ready_Pe_2018.csv"), row.names = FALSE)

