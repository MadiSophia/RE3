# =================================================
# Correlation matrix: climate + topo/forest/soil variables
# Excludes spectral and resilience metrics, ids, and coordinates
# Fixes typo: pcrp_2019 -> prcp_2019
# Climate ordered by variable then year
# Clean ggplot2 heatmap (square, no title, no tile labels)
# =================================================

library(dplyr)
library(stringr)
library(ggplot2)

rm(list = ls())

# -----------------------------
# Inputs
# -----------------------------
env_path <- "S:/mbrown/Madi_sentinel_2_comp/clim_site_var.csv"
res_path <- "S:/mbrown/Madi_sentinel_2_comp/nfi_indices_metrics_clean.csv"

out_png <- "S:/mbrown/Madi_sentinel_2_comp/corr_env_only_no_spectral.png"

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
# Use only numeric columns
# -----------------------------
corr_data <- data %>%
  select(where(is.numeric)) %>%
  select(where(~ sum(is.finite(.x)) >= 2))

all_vars <- names(corr_data)

# -----------------------------
# Exclude ids and coordinates seen in your data
# -----------------------------
drop_exact <- c(
  "ID", "Year", "SiteID", "TreeID",
  "TreeNo", "SpeciesNo",
  "Xwgs", "Yweg", "X03.", "Y03.",
  "X", "BART", "BARTgroup"
)



# -----------------------------
# Exclude spectral/resilience metric columns
# Examples: CCI_Rs_2018, NDVI_Pe_2018, NDWI_Rr_2018, etc.
# -----------------------------
metric_pat <- "_(Rs|Rc|Rr|Pe)_\\d{4}$"

# Also drop raw index/band time series if they exist (e.g., NDVI_2018 or NIR_2019_aug)
spectral_year_pat <- "^[A-Z0-9]+_(19|20)\\d{2}(_aug)?$"

exclude_vars <- all_vars[
  all_vars %in% drop_exact |
    str_detect(all_vars, metric_pat) |
    str_detect(all_vars, spectral_year_pat)
]

keep_vars <- setdiff(all_vars, exclude_vars)
corr_data <- corr_data[, keep_vars, drop = FALSE]

# -----------------------------
# Climate vars
# -----------------------------
clim_vars <- keep_vars[
  str_detect(keep_vars, "^(prcp|tmean|vpd)_(19|20)\\d{2}$")
]

other_vars <- setdiff(keep_vars, clim_vars)

# Order climate vars: variable name then year
clim_ordered <- tibble(var = clim_vars) %>%
  mutate(
    base = str_match(var, "^([a-zA-Z]+)_")[, 2],
    year = as.integer(str_match(var, "_(\\d{4})$")[, 2])
  ) %>%
  arrange(base, year) %>%
  pull(var)

# Order other vars alphabetically
ordered_vars <- c(clim_ordered, sort(other_vars))
corr_data <- corr_data[, ordered_vars, drop = FALSE]

# -----------------------------
# Correlation matrix
# -----------------------------
corr_matrix <- cor(corr_data, use = "pairwise.complete.obs", method = "pearson")

# -----------------------------
# Long format for ggplot2
# -----------------------------
corr_long <- as.data.frame(as.table(corr_matrix)) %>%
  rename(var_x = Var1, var_y = Var2, r = Freq) %>%
  mutate(
    var_x = factor(var_x, levels = ordered_vars),
    var_y = factor(var_y, levels = rev(ordered_vars))
  )

pretty_names <- function(x) {
  x %>%
    str_replace_all("_", " ") %>%
    str_replace_all("\\s+", " ") %>%
    str_trim()
}

corr_long <- corr_long %>%
  mutate(
    var_x_lab = factor(pretty_names(as.character(var_x)),
                       levels = pretty_names(ordered_vars)),
    var_y_lab = factor(pretty_names(as.character(var_y)),
                       levels = pretty_names(rev(ordered_vars)))
  )

# -----------------------------
# Plot heatmap (square, no title, no tile labels)
# -----------------------------
p <- ggplot(corr_long, aes(x = var_x_lab, y = var_y_lab, fill = r)) +
  geom_tile(color = "white", linewidth = 0.15) +
  coord_fixed() +
  scale_fill_gradient2(
    low = "blue",
    mid = "white",
    high = "red",
    limits = c(-1, 1),
    name = "Correlation"
  ) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid = element_blank(),
    axis.title = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1, size = 12),
    axis.text.y = element_text(size = 12),
    legend.title = element_text(size = 12),
    legend.text = element_text(size = 10),
    plot.margin = margin(4, 4, 4, 4)
  )

print(p)

# -----------------------------
# Save plot
# -----------------------------
ggsave(out_png, p, width = 12, height = 12, dpi = 600, bg = "white")

message("Saved plot: ", out_png)
