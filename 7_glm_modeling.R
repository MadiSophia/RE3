library(dplyr)
library(stringr)
library(broom)
library(ggplot2)

rm(list = ls())

# =========================================================
# Run GLMs for all metric tables (Rs, Rc, Rr, Pe)
# and loop through all spectral indices automatically.
# Outputs:
# - coefficients table
# - fit table
# - observed vs predicted metrics table
# - variable importance table (delta %RMSE)
# - observed vs predicted plots
# - variable importance plots (shared y scale)
# - summary table of all spectral indices with R2, p value, and %RMSE
# =========================================================

# -----------------------------
# Working directory and inputs
# -----------------------------
setwd("S:/mbrown/Madi_sentinel_2_comp/glm_ready/")

files <- c(
  Rs = "glm_ready_Rs_2018.csv",
  Rc = "glm_ready_Rc_2018.csv",
  Rr = "glm_ready_Rr_2018.csv",
  Pe = "glm_ready_Pe_2018.csv"
)

# -----------------------------
# Settings
# -----------------------------
species_col <- "Species"
min_n <- 25

base_predictors <- c("soil_index", "slope_deg", "folded_aspect", "forest_edge", "ForestCovS")

# Output files
out_coef <- "glm_models_all_indices_coefficients.csv"
out_fit  <- "glm_models_all_indices_fit.csv"
out_obs_pred_metrics <- "glm_models_all_indices_obs_pred_metrics.csv"
out_varimp <- "glm_models_all_indices_variable_importance_percent_rmse.csv"

# Requested summary output: all spectral indices with R2, %RMSE, p value
out_spectral_perf <- "glm_spectral_indices_performance_summary.csv"

# Plot folders
obs_pred_dir <- "glm_obs_pred_plots_all_indices"
varimp_dir <- "glm_variable_importance_plots_percent_rmse_all_indices"
dir.create(obs_pred_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(varimp_dir, recursive = TRUE, showWarnings = FALSE)

# Global y-axis max for var-importance plots (consistent scale)
varimp_y_max <- NA_real_

# -----------------------------
# Helpers
# -----------------------------
safe_name <- function(x) str_replace_all(x, "[^A-Za-z0-9]+", "_")

species_expr <- function(sp) {
  parts <- unlist(str_split(trimws(sp), "\\s+"))
  if (length(parts) >= 2) {
    bquote(italic(.(parts[1])~.(parts[2])))
  } else {
    bquote(italic(.(sp)))
  }
}

# -----------------------------
# %RMSE helper
# %RMSE = 100 * RMSE / mean(observed)
# -----------------------------
percent_rmse <- function(model, data_used, response) {
  obs <- data_used[[response]]
  pred <- predict(model, type = "response")
  ok <- is.finite(obs) & is.finite(pred)
  if (sum(ok) < 5) return(NA_real_)
  denom <- mean(obs[ok])
  if (!is.finite(denom) || denom == 0) return(NA_real_)
  rmse <- sqrt(mean((obs[ok] - pred[ok])^2))
  100 * rmse / denom
}

# -----------------------------
# Observed vs predicted metrics and plot
# -----------------------------
obs_pred_summary_and_plot <- function(model, data_used, response, metric_tag, species, index_name, plot_path) {
  
  pred <- predict(model, type = "response")
  obs  <- data_used[[response]]
  
  ok <- is.finite(obs) & is.finite(pred)
  obs <- obs[ok]
  pred <- pred[ok]
  
  if (length(obs) < 5) return(list(metrics = tibble()))
  
  r <- suppressWarnings(cor(obs, pred))
  r2 <- r^2
  pval <- suppressWarnings(cor.test(obs, pred)$p.value)
  prmse <- percent_rmse(model, data_used, response)
  
  metrics <- tibble(
    metric_type = metric_tag,
    index = index_name,
    species = species,
    response = response,
    n = length(obs),
    r = r,
    r2 = r2,
    p_value = pval,
    percent_rmse = prmse
  )
  
  df_plot <- tibble(observed = obs, predicted = pred)
  ttl <- bquote(.(index_name)~.(metric_tag)~.(response)~"-"~.(species_expr(species)))
  
  p <- ggplot(df_plot, aes(x = predicted, y = observed)) +
    geom_point(alpha = 0.6) +
    geom_smooth(method = "lm", se = FALSE) +
    labs(
      title = ttl,
      x = "Predicted",
      y = "Observed"
    ) +
    annotate(
      "text",
      x = Inf, y = -Inf,
      hjust = 1.05, vjust = -0.5,
      label = paste0(
        "R2 = ", round(r2, 3), "\n",
        "p = ", signif(pval, 3), "\n",
        "%RMSE = ", round(prmse, 1)
      )
    ) +
    theme_classic(base_size = 12) +
    theme(
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8),
      axis.line = element_line(color = "black"),
      plot.title = element_text(hjust = 0.5, size = 12)
    )
  
  ggsave(plot_path, p, width = 5, height = 5, dpi = 300, bg = "white")
  
  list(metrics = metrics)
}

# -----------------------------
# Variable importance (delta %RMSE)
# -----------------------------
variable_importance <- function(full_model, data_used, response, predictors,
                                metric_tag, species, index_name, clim_col) {
  
  full_prmse <- percent_rmse(full_model, data_used, response)
  full_aic <- AIC(full_model)
  
  out <- list()
  
  for (v in predictors) {
    
    reduced_preds <- setdiff(predictors, v)
    if (length(reduced_preds) == 0) next
    
    fml_red <- as.formula(paste(response, "~", paste(reduced_preds, collapse = " + ")))
    m_red <- glm(fml_red, data = data_used, family = gaussian())
    
    red_prmse <- percent_rmse(m_red, data_used, response)
    red_aic <- AIC(m_red)
    
    out[[length(out) + 1]] <- tibble(
      metric_type = metric_tag,
      index = index_name,
      species = species,
      response = response,
      n = nrow(data_used),
      climate_index = clim_col,
      removed_term = v,
      percent_rmse_full = full_prmse,
      percent_rmse_reduced = red_prmse,
      delta_percent_rmse = red_prmse - full_prmse,
      aic_full = full_aic,
      aic_reduced = red_aic,
      delta_aic = red_aic - full_aic
    )
  }
  
  bind_rows(out)
}

# -----------------------------
# Variable importance plot (fixed scale, italic species)
# -----------------------------
plot_varimp_group <- function(varimp_group, metric_tag, response, species, index_name, out_path, y_max = NULL) {
  
  g2 <- varimp_group %>%
    filter(is.finite(delta_percent_rmse)) %>%
    arrange(desc(delta_percent_rmse)) %>%
    mutate(
      removed_term_lab = str_replace(removed_term, "^clim_index_.*", "Climate index"),
      removed_term_lab = str_replace_all(removed_term_lab, "_", " ")
    )
  
  if (nrow(g2) == 0) return(invisible(NULL))
  
  ttl <- bquote(.(index_name)~.(metric_tag)~.(response)~"-"~.(species_expr(species)))
  
  p <- ggplot(g2, aes(x = reorder(removed_term_lab, delta_percent_rmse), y = delta_percent_rmse)) +
    geom_col() +
    coord_flip() +
    labs(
      title = ttl,
      subtitle = "Importance = increase in %RMSE when predictor is removed",
      x = NULL,
      y = "Delta %RMSE"
    ) +
    theme_classic(base_size = 12) +
    theme(
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8),
      axis.line = element_line(color = "black"),
      plot.title = element_text(hjust = 0.5, size = 12),
      plot.subtitle = element_text(hjust = 0.5, size = 10)
    )
  
  if (!is.null(y_max) && is.finite(y_max)) {
    p <- p + scale_y_continuous(limits = c(0, y_max), expand = expansion(mult = c(0, 0.05)))
  }
  
  ggsave(out_path, p, width = 6, height = 4, dpi = 300, bg = "white")
}

# -----------------------------
# Run models across all indices in each dataset
# -----------------------------
all_coef <- list()
all_fit <- list()
all_obs_pred <- list()
all_varimp <- list()

for (metric_tag in names(files)) {
  
  message("Processing file: ", metric_tag, " (", files[[metric_tag]], ")")
  df <- read.csv(files[[metric_tag]])
  
  if (!species_col %in% names(df)) stop("Species column not found: ", species_col)
  
  # Find climate index column
  clim_col <- names(df)[str_detect(names(df), "^clim_index_")]
  if (length(clim_col) == 0) stop("No climate index column found in: ", files[[metric_tag]])
  clim_col <- clim_col[1]
  
  # Drop intermediate climate columns if present
  df <- df %>% select(-matches("^tmean_"), -matches("^vpd_"))
  
  # Responses: INDEX_metric_YYYY
  resp_cols <- names(df)[str_detect(names(df), paste0("^[A-Za-z0-9]+_", metric_tag, "_\\d{4}$"))]
  if (length(resp_cols) == 0) {
    message("No response columns found for ", metric_tag, " - skipping.")
    next
  }
  
  # Map response -> index
  idx_names <- str_match(resp_cols, "^([A-Za-z0-9]+)_")[, 2]
  names(idx_names) <- resp_cols
  
  predictors <- c(clim_col, base_predictors)
  predictors <- predictors[predictors %in% names(df)]
  
  for (sp in sort(unique(df[[species_col]]))) {
    
    d_sp <- df %>% filter(.data[[species_col]] == sp)
    
    for (y in resp_cols) {
      
      index_name <- idx_names[[y]]
      
      needed <- c(y, predictors)
      
      d_mod <- d_sp %>%
        select(all_of(needed)) %>%
        filter(!is.na(.data[[y]])) %>%
        filter(if_all(all_of(predictors), ~ is.finite(.x)))
      
      if (nrow(d_mod) < min_n) next
      
      fml <- as.formula(paste(y, "~", paste(predictors, collapse = " + ")))
      m <- glm(fml, data = d_mod, family = gaussian())
      
      all_coef[[length(all_coef) + 1]] <- broom::tidy(m) %>%
        mutate(
          metric_type = metric_tag,
          index = index_name,
          species = sp,
          response = y,
          n = nrow(d_mod),
          climate_index = clim_col
        )
      
      all_fit[[length(all_fit) + 1]] <- broom::glance(m) %>%
        mutate(
          metric_type = metric_tag,
          index = index_name,
          species = sp,
          response = y,
          n = nrow(d_mod),
          climate_index = clim_col
        )
      
      obs_plot_path <- file.path(
        obs_pred_dir,
        paste0(index_name, "__", metric_tag, "__", safe_name(y), "__", safe_name(sp), ".png")
      )
      op <- obs_pred_summary_and_plot(m, d_mod, y, metric_tag, sp, index_name, obs_plot_path)
      if (nrow(op$metrics) > 0) all_obs_pred[[length(all_obs_pred) + 1]] <- op$metrics
      
      vi <- variable_importance(m, d_mod, y, predictors, metric_tag, sp, index_name, clim_col)
      if (nrow(vi) > 0) all_varimp[[length(all_varimp) + 1]] <- vi
      
      # Update global y max for consistent scaling (99th percentile)
      if (nrow(vi) > 0) {
        vals <- vi$delta_percent_rmse
        vals <- vals[is.finite(vals)]
        if (length(vals) > 0) {
          new_max <- as.numeric(quantile(vals, 0.99, na.rm = TRUE))
          if (!is.finite(varimp_y_max)) varimp_y_max <<- new_max
          varimp_y_max <<- max(varimp_y_max, new_max, na.rm = TRUE)
        }
      }
      
      if (nrow(vi) > 0 && is.finite(varimp_y_max)) {
        vi_plot_path <- file.path(
          varimp_dir,
          paste0(index_name, "__", metric_tag, "__", safe_name(y), "__", safe_name(sp), "__varimp_percent_rmse.png")
        )
        plot_varimp_group(vi, metric_tag, y, sp, index_name, vi_plot_path, y_max = varimp_y_max)
      }
    }
  }
}

coef_df <- bind_rows(all_coef)
fit_df  <- bind_rows(all_fit)
obs_df  <- bind_rows(all_obs_pred)
varimp_df <- bind_rows(all_varimp)

write.csv(coef_df, out_coef, row.names = FALSE)
write.csv(fit_df,  out_fit,  row.names = FALSE)
write.csv(obs_df,  out_obs_pred_metrics, row.names = FALSE)
write.csv(varimp_df, out_varimp, row.names = FALSE)

# -----------------------------
# Requested output: one table of all spectral indices with R2, %RMSE, p value
# Each row = one fitted model (index × metric type × species)
# -----------------------------
spectral_perf <- obs_df %>%
  mutate(
    index = if_else(is.na(index) | index == "", str_extract(response, "^[A-Za-z0-9]+"), index),
    metric_type = metric_type
  ) %>%
  select(
    index,
    metric_type,
    species,
    response,
    n,
    r2,
    p_value,
    percent_rmse
  ) %>%
  arrange(index, metric_type, species)

write.csv(spectral_perf, out_spectral_perf, row.names = FALSE)

message("Saved: ", out_coef)
message("Saved: ", out_fit)
message("Saved: ", out_obs_pred_metrics)
message("Saved: ", out_varimp)
message("Saved: ", out_spectral_perf)
message("Saved observed vs predicted plots to: ", file.path(getwd(), obs_pred_dir))
message("Saved variable importance plots to: ", file.path(getwd(), varimp_dir))
message("Total models fit: ", nrow(fit_df))
message("Variable importance y-axis max used: ", varimp_y_max)
