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

# =========================
# Load and reshape
# =========================
df <- read.csv(metric_data)

metric_cols <- grep("^[A-Za-z0-9]+_(Rs|Rc|Rr|Pe)_\\d{4}$", names(df), value = TRUE)
if (length(metric_cols) == 0) stop("No metric columns matched pattern like NDVI_Rs_2018.")

metrics_long <- df %>%
  filter(Species %in% species_order) %>%
  pivot_longer(
    cols = all_of(metric_cols),
    names_to = c("index", "metric", "year"),
    names_pattern = "^(.*)_(Rs|Rc|Rr|Pe)_(\\d{4})$",
    values_to = "value"
  ) %>%
  mutate(
    year = as.integer(year),
    Species = factor(Species, levels = species_order)
  ) %>%
  drop_na(value)

# Auto-detect available values and validate selections
available_indices <- sort(unique(metrics_long$index))
available_metrics <- sort(unique(metrics_long$metric))
available_years   <- sort(unique(metrics_long$year))

if (is.null(indices_to_run)) indices_to_run <- available_indices
if (is.null(metrics_to_run)) metrics_to_run <- available_metrics
if (is.null(years_to_run))   years_to_run   <- available_years

indices_to_run <- intersect(indices_to_run, available_indices)
metrics_to_run <- intersect(metrics_to_run, available_metrics)
years_to_run   <- intersect(years_to_run, available_years)

if (length(indices_to_run) == 0) stop("No matching indices_to_run found in the data.")
if (length(metrics_to_run) == 0) stop("No matching metrics_to_run found in the data.")
if (length(years_to_run) == 0)   stop("No matching years_to_run found in the data.")

metrics_long <- metrics_long %>%
  filter(index %in% indices_to_run,
         metric %in% metrics_to_run,
         year %in% years_to_run)

if (nrow(metrics_long) == 0) stop("No data left after filtering selections.")

# =========================
# Helpers
# =========================
metric_label <- function(metric_code) {
  dplyr::case_when(
    metric_code == "Rs" ~ "Resistance(Rs)",
    metric_code == "Rc" ~ "Recovery(Rc)",
    metric_code == "Rr" ~ "Recovery rate(Rr)",
    metric_code == "Pe" ~ "Resilience(Pe)",
    TRUE ~ metric_code
  )
}

get_letters_one <- function(subdata) {
  if (n_distinct(subdata$Species) <= 1) {
    letters <- setNames("a", as.character(unique(subdata$Species)))
  } else {
    d <- dunn_test(subdata, value ~ Species, p.adjust.method = "BH")
    
    if (nrow(d) == 0) {
      letters <- setNames(rep("a", n_distinct(subdata$Species)), levels(subdata$Species))
    } else {
      species_vec <- levels(subdata$Species)
      pmat <- matrix(1, nrow = length(species_vec), ncol = length(species_vec),
                     dimnames = list(species_vec, species_vec))
      
      for (i in seq_len(nrow(d))) {
        g1 <- d$group1[i]
        g2 <- d$group2[i]
        pmat[g1, g2] <- d$p.adj[i]
        pmat[g2, g1] <- d$p.adj[i]
      }
      letters <- multcompLetters(pmat)$Letters
    }
  }
  
  tibble(
    Species = factor(names(letters), levels = levels(subdata$Species)),
    group = unname(letters)
  )
}

# =========================
# Create metric subfolders up front (Rs, Rc, ...)
# =========================
for (met in metrics_to_run) {
  dir.create(file.path(out_dir, met), recursive = TRUE, showWarnings = FALSE)
}

# =========================
# Loop and save
# All Rs outputs -> out_dir/Rs/
# All Rc outputs -> out_dir/Rc/
# =========================
combos <- metrics_long %>%
  distinct(index, metric, year) %>%
  arrange(metric, year, index)

for (k in seq_len(nrow(combos))) {
  
  idx <- combos$index[k]
  met <- combos$metric[k]
  yr  <- combos$year[k]
  
  sub <- metrics_long %>%
    filter(index == idx, metric == met, year == yr) %>%
    mutate(Species = fct_reorder(Species, value, .fun = mean, .desc = TRUE))
  
  letters <- get_letters_one(sub) %>%
    mutate(ypos = max(sub$value, na.rm = TRUE) * 1.05)
  
  plot_data <- sub %>% left_join(letters, by = "Species")
  
  p <- ggplot(plot_data, aes(x = Species, y = value)) +
    geom_boxplot(fill = "#7E6696", color = "black", linewidth = 0.2, outlier.size = 0.5) +
    geom_text(aes(y = ypos, label = group), size = 3.5, hjust = 0.5) +
    coord_flip() +
    labs(
      title = paste(idx, metric_label(met), yr),
      x = NULL,
      y = metric_label(met)
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      axis.text.x = element_text(size = 10),
      axis.ticks.x = element_line(color = "black"),
      axis.text.y = element_text(face = "italic", size = 10),
      panel.grid = element_blank(),
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.6),
      legend.position = "none"
    )
  
  # Save into subfolder named by metric (Rs, Rc, ...)
  outfile <- file.path(out_dir, met, paste0(idx, "_", met, "_", yr, ".png"))
  
  ggsave(
    filename = outfile,
    plot = p,
    width = plot_width_in, height = plot_height_in,
    dpi = plot_dpi, units = "in",
    bg = "white",
    device = "png"
  )
}

message("Plots written to: ", out_dir)
message("Subfolders created: ", paste(metrics_to_run, collapse = ", "))


