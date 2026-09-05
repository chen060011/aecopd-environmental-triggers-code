suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
  library(dlnm)
  library(splines)
  library(sandwich)
})

CONTROL_STRATEGY <- Sys.getenv("AECOPD_CONTROL_STRATEGY", "monthly_weekday")

DATA_DIR <- Sys.getenv("AECOPD_DATA_DIR", ".")
data_path <- Sys.getenv("AECOPD_ANALYSIS_INPUT", file.path(DATA_DIR, "analysis_input.csv"))

CENTRE_VAR <- Sys.getenv("AECOPD_CENTRE_VAR", "hospital_code")
EXCLUDE_CENTRE <- Sys.getenv("AECOPD_EXCLUDE_CENTRE", "")
output_tag <- if (nzchar(EXCLUDE_CENTRE)) paste0(CONTROL_STRATEGY, "_exclude_", gsub("[^A-Za-z0-9_-]", "_", EXCLUDE_CENTRE)) else CONTROL_STRATEGY
output_dir <- file.path(Sys.getenv("AECOPD_OUTPUT_DIR", "results"), output_tag)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

STRATA_VAR  <- "match_id"
OUTCOME_VAR <- "is_case"
CLUSTER_CANDIDATES <- c("cluster_id", "origin_id", "patient_id")

EVENT_DATE_VAR <- "date"
RUN_HEATING_STRATIFIED <- TRUE

HEATING_START_MONTH <- 10
HEATING_START_DAY   <- 20
HEATING_END_MONTH   <- 4
HEATING_END_DAY     <- 6

RUN_COVID_WAVE_ADJUST <- TRUE
COVID_WAVE_VAR <- "covid_major_wave"

COVID_MAJOR_WAVE_WINDOWS <- list(
  c("2020-01-01", "2020-05-31"),
  c("2022-03-01", "2023-01-31")
)

EXT_TEMP_COUNT_MAIN_VARS <- c("EHT_count_lag0_2", "ELT_count_lag0_2")

CLOGIT_LAGS <- 0:7
MAX_LAG    <- 21
FOCUS_LAGS <- 0:7
FOCUS_WIN  <- c(0, 7)
RUN_FLU_DLNM <- FALSE

DF_VAR_TARGET <- 3
DF_LAG        <- 4
MAX_MISS_LAG0 <- 0.30

AGG_PATTERNS <- c("_avg_lag0_2$", "_avg_lag0_7$", "_max_lag0_2$")

ENV_SINGLE_LAGS <- 0:7
ENV_MULTI_LAGS  <- paste0("avg_lag0_", 1:7)

FLU_ADJ_FOR_ENV <- c("阳性率")
FLU_ADJ_SUFFIX <- "_avg_lag0_2"

RUN_TEMP_NL_DLNM <- TRUE
TEMP_NL_DLNM_VARS <- c("Tavg", "Tmin", "Tmax")
TEMP_NL_DLNM_MAX_LAG <- 21
TEMP_NL_DLNM_DF_VAR <- 4
TEMP_NL_DLNM_DF_LAG <- 3
TEMP_NL_DLNM_PRED_Q <- c(0.01, 0.99)
TEMP_NL_DLNM_PRED_N <- 80

RUN_POLLUTANT_LIN_DLNM <- FALSE
POLLUTANT_LIN_DLNM_VARS <- c("PM25", "PM10", "NO2", "SO2", "CO", "O3")
POLLUTANT_LIN_DLNM_MAX_LAG <- 21
POLLUTANT_LIN_DLNM_DF_LAG <- 4
POLLUTANT_LIN_DLNM_LAGS_TO_REPORT <- c(0, 1, 3, 5, 7, 14, 21)

RUN_GROUP_STRATIFIED <- TRUE

MIN_CASES_PER_GROUP_LEVEL <- 30
MIN_ROWS_PER_GROUP_LEVEL  <- 100
KEEP_REFERENCE_LEVELS <- TRUE

ANALYSIS_GROUP_VARS <- c(

  "grp_age_3cat",
  "grp_sex",
  "grp_cv_comorb",
  "grp_multimorbidity",

  "grp_metabolic_comorb",

  "grp_smoking_3cat",
  "grp_smoking_ever_never",
  "grp_pack_years_4cat",

  "grp_symptom_dominant_4cat",
  "grp_airway",
  "grp_airway_strict",
  "grp_never_smoker_airway",
  "grp_bx_grp",
  "grp_asthma_grp",
  "grp_emphysema_grp"
)

GROUP_VAR_LABEL_MAP <- c(
  "grp_age_3cat" = "Age group",
  "grp_sex" = "Sex",
  "grp_cv_comorb" = "Cardiovascular comorbidity",
  "grp_multimorbidity" = "Multimorbidity",
  "grp_metabolic_comorb" = "Metabolic comorbidity",
  "grp_smoking_3cat" = "Smoking (3-category)",
  "grp_smoking_ever_never" = "Smoking (ever/never)",
  "grp_pack_years_4cat" = "Pack-years (4-category)",
  "grp_symptom_dominant_4cat" = "Symptom-dominant group (4-category)",
  "grp_airway" = "Airway-related symptom phenotype",
  "grp_airway_strict" = "Strict airway-related symptom phenotype",
  "grp_never_smoker_airway" = "Smoking-airway composite group",
  "grp_bx_grp" = "Background bronchiectasis",
  "grp_asthma_grp" = "Background asthma",
  "grp_emphysema_grp" = "Background emphysema"
)

VAR_LABEL_MAP <- c(
  "PM25" = "PM2.5 (µg/m³)",
  "PM10" = "PM10 (µg/m³)",
  "NO2"  = "NO₂ (µg/m³)",
  "SO2"  = "SO₂ (µg/m³)",
  "CO"   = "CO (mg/m³)",
  "O3"   = "O₃ (µg/m³)",

  "Tavg" = "Mean temperature (°C)",
  "Tmax" = "Maximum temperature (°C)",
  "Tmin" = "Minimum temperature (°C)",
  "EHT"  = "Extreme high temperature day",
  "ELT"  = "Extreme low temperature day",
  "EHT_count_lag0_2" = "Extreme high temperature days (lag 0-2 count)",
  "ELT_count_lag0_2" = "Extreme low temperature days (lag 0-2 count)",
  "EHT_count_lag0_7" = "Extreme high temperature days (lag 0-7 count)",
  "ELT_count_lag0_7" = "Extreme low temperature days (lag 0-7 count)",

  "RHUM" = "Relative humidity (%)",
  "SHUM" = "Specific humidity (kg/kg)",
  "PRES" = "Atmospheric pressure (hPa)",

  "检测数" = "Influenza tests",
  "阳性数" = "Positive tests",
  "阳性率" = "Positivity rate",

  "A型占比" = "Influenza A (%)",
  "B型占比" = "Influenza B (%)",
  "A_H3N2占比" = "A(H3N2) (%)",
  "A_H1N1占比" = "A(H1N1)pdm09 (%)",
  "A_unsubtyped占比" = "A unsubtyped (%)",
  "B_未分系占比" = "B lineage unclassified (%)",
  "B_Victoria占比" = "B/Victoria (%)",
  "B_Yamagata占比" = "B/Yamagata (%)",

  "A型数量" = "Influenza A detections",
  "B型数量" = "Influenza B detections",
  "A_H3N2数量" = "A(H3N2) detections",
  "A_H1N1数量" = "A(H1N1)pdm09 detections",
  "A_unsubtyped数量" = "A unsubtyped detections",
  "B_未分系数量" = "B lineage unclassified detections",
  "B_Victoria数量" = "B/Victoria detections",
  "B_Yamagata数量" = "B/Yamagata detections",

  "covid_major_wave" = "COVID major-wave period",
  "holiday" = "Public holiday"
)

add_var_label <- function(v) {
  out <- unname(VAR_LABEL_MAP[v])
  ifelse(is.na(out), v, out)
}

add_group <- function(v) {
  case_when(
    v %in% c("Tavg", "Tmax", "Tmin", "EHT", "ELT",
             "EHT_count_lag0_2", "ELT_count_lag0_2",
             "EHT_count_lag0_7", "ELT_count_lag0_7",
             "RHUM", "SHUM", "PRES") ~ "Meteorological factors",
    v %in% c("PM25", "PM10", "SO2", "NO2", "CO", "O3") ~ "Air pollutants",
    TRUE ~ "Influenza indicators"
  )
}

add_group_var_label <- function(v) {
  out <- unname(GROUP_VAR_LABEL_MAP[v])
  ifelse(is.na(out), v, out)
}

POLLUTANT_VARS <- c("PM25", "PM10", "SO2", "NO2", "CO", "O3")
METEO_VARS     <- c("Tavg", "Tmax", "Tmin", "EHT", "ELT",
                    "EHT_count_lag0_2", "ELT_count_lag0_2",
                    "EHT_count_lag0_7", "ELT_count_lag0_7",
                    "RHUM", "SHUM", "PRES")
FLU_VARS       <- c(
  "检测数", "阳性数", "阳性率",
  "A型占比", "B型占比",
  "A_H3N2占比", "A_H1N1占比", "A_unsubtyped占比",
  "B_未分系占比", "B_Victoria占比", "B_Yamagata占比",
  "A型数量", "B型数量",
  "A_H3N2数量", "A_H1N1数量", "A_unsubtyped数量",
  "B_未分系数量", "B_Victoria数量", "B_Yamagata数量"
)

FLU_MAIN_VARS <- FLU_VARS
ENV_MAIN_VARS <- c(POLLUTANT_VARS, METEO_VARS)

FLU_TEMP_AVG_COL <- "Tavg_avg_lag0_2"
FLU_RHUM_AVG_COL <- "RHUM_avg_lag0_2"
FLU_TEMP_DF <- 6
FLU_RHUM_DF <- 3

TEMP_GROUP  <- c("Tavg", "Tmax", "Tmin", "EHT", "ELT")
HUMID_GROUP <- c("RHUM", "SHUM")

BINARY_VARS <- c("EHT", "ELT")

MANUAL_SCALE_MAP <- c(
  "阳性率" = 10,
  "A型占比" = 10,
  "B型占比" = 10,
  "A_H3N2占比" = 10,
  "A_H1N1占比" = 10,
  "A_unsubtyped占比" = 1,
  "B_未分系占比" = 10,
  "B_Victoria占比" = 10,
  "B_Yamagata占比" = 10,

  "检测数" = 100,
  "阳性数" = 100,
  "A型数量" = 100,
  "B型数量" = 100,
  "A_H3N2数量" = 100,
  "A_H1N1数量" = 100,
  "A_unsubtyped数量" = 10,
  "B_未分系数量" = 100,
  "B_Victoria数量" = 100,
  "B_Yamagata数量" = 1,
  "EHT" = 1,
  "ELT" = 1,
  "EHT_count_lag0_2" = 1,
  "ELT_count_lag0_2" = 1,
  "EHT_count_lag0_7" = 1,
  "ELT_count_lag0_7" = 1,
  "covid_major_wave" = 1,
  "holiday" = 1
)


safe_is_finite <- function(x) is.finite(x) & !is.na(x)

calc_iqr <- function(x, var_name = NULL) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[safe_is_finite(x)]
  if (length(x) < 10) return(NA_real_)
  i <- IQR(x, na.rm = TRUE)
  if (!is.finite(i) || i <= 0) return(NA_real_)
  i
}

GLOBAL_IQR_MAP <- c()
CURRENT_IQR_MAP <- c()

build_global_iqr_map <- function(df, base_vars, max_lag = 21) {
  out <- setNames(rep(NA_real_, length(base_vars)), base_vars)

  for (v in base_vars) {
    x <- NULL

    lag0_name <- paste0(v, "_lag0")
    if (lag0_name %in% names(df)) {
      x <- suppressWarnings(as.numeric(df[[lag0_name]]))
    } else if (v %in% names(df)) {
      x <- suppressWarnings(as.numeric(df[[v]]))
    }

    iqr_v <- calc_iqr(x, var_name = v)
    if (is.finite(iqr_v) && iqr_v > 0) {
      out[[v]] <- iqr_v
    } else {
      out[[v]] <- NA_real_
    }
  }

  out
}

get_registered_global_iqr <- function(base_var) {
  if (!exists("GLOBAL_IQR_MAP", inherits = TRUE)) return(NA_real_)
  if (!(base_var %in% names(GLOBAL_IQR_MAP))) return(NA_real_)

  val <- suppressWarnings(as.numeric(GLOBAL_IQR_MAP[[base_var]]))
  if (!is.finite(val) || val <= 0) return(NA_real_)
  val
}

get_analysis_iqr <- function(base_var) {
  if (base_var %in% names(CURRENT_IQR_MAP)) {
    val <- suppressWarnings(as.numeric(CURRENT_IQR_MAP[[base_var]]))
    if (is.finite(val) && val > 0) return(val)
  }
  get_registered_global_iqr(base_var)
}

get_cluster_var <- function(df, candidates = CLUSTER_CANDIDATES) {
  hit <- candidates[candidates %in% names(df)]
  if (length(hit) == 0) return(NULL)
  hit[1]
}

`%||%` <- function(x, y) {
  if (!is.null(x)) x else y
}

get_scale_value <- function(data, base_var) {
  if (base_var %in% names(MANUAL_SCALE_MAP)) {
    return(as.numeric(MANUAL_SCALE_MAP[[base_var]]))
  }

  if (base_var %in% names(CURRENT_IQR_MAP)) {
    current_iqr <- suppressWarnings(as.numeric(CURRENT_IQR_MAP[[base_var]]))
    if (is.finite(current_iqr) && current_iqr > 0) return(current_iqr)
  }

  iqr_v <- get_analysis_iqr(base_var)
  if (is.finite(iqr_v) && iqr_v > 0) return(iqr_v)

  1
}

get_scale_label <- function(data, base_var) {
  if (base_var %in% names(MANUAL_SCALE_MAP)) {
    return(paste0("per ", MANUAL_SCALE_MAP[[base_var]], "-unit"))
  }

  if (base_var %in% names(CURRENT_IQR_MAP)) {
    current_iqr <- suppressWarnings(as.numeric(CURRENT_IQR_MAP[[base_var]]))
    if (is.finite(current_iqr) && current_iqr > 0) return("per IQR (current analysis subset)")
  }

  iqr_v <- get_analysis_iqr(base_var)

  if (is.finite(iqr_v) && iqr_v > 0) {
    return("per IQR (global)")
  }

  "per 1-unit"
}

safe_coef_se <- function(fit, coef_name, cluster_vec = NULL) {
  beta <- tryCatch(as.numeric(coef(fit)[[coef_name]]), error = function(e) NA_real_)
  if (!is.finite(beta)) return(list(ok = FALSE, beta = NA_real_, se = NA_real_))

  vv <- NULL

  if (!is.null(cluster_vec) && requireNamespace("sandwich", quietly = TRUE)) {
    vv <- tryCatch({
      sandwich::vcovCL(fit, cluster = cluster_vec)
    }, error = function(e) NULL)
  }

  if (is.null(vv)) {
    vv <- tryCatch(vcov(fit), error = function(e) NULL)
  }

  if (is.null(vv) || !(coef_name %in% rownames(vv))) {
    return(list(ok = FALSE, beta = beta, se = NA_real_))
  }

  se <- sqrt(as.numeric(vv[coef_name, coef_name]))
  if (!is.finite(se) || se <= 0) {
    return(list(ok = FALSE, beta = beta, se = se))
  }

  list(ok = TRUE, beta = beta, se = se)
}

get_model_vcov <- function(fit, cluster_vec = NULL) {
  vv <- NULL
  if (!is.null(cluster_vec) && requireNamespace("sandwich", quietly = TRUE)) {
    vv <- tryCatch(sandwich::vcovCL(fit, cluster = cluster_vec), error = function(e) NULL)
  }
  if (is.null(vv)) vv <- tryCatch(vcov(fit), error = function(e) NULL)
  vv
}

calc_p_from_logrr_se <- function(logrr, se) {
  ifelse(
    is.finite(logrr) & is.finite(se) & se > 0,
    2 * (1 - pnorm(abs(logrr / se))),
    NA_real_
  )
}

is_valid_base_var <- function(df, v, max_lag = 35, max_miss_lag0 = 0.80) {
  lag_cols <- paste0(v, "_lag", 0:max_lag)
  if (!all(lag_cols %in% names(df))) return(FALSE)

  x0 <- suppressWarnings(as.numeric(df[[paste0(v, "_lag0")]]))
  miss0 <- mean(is.na(x0))
  if (!is.finite(miss0) || miss0 > max_miss_lag0) return(FALSE)

  x0 <- x0[safe_is_finite(x0)]
  if (length(x0) < 50) return(FALSE)

  if (v %in% BINARY_VARS) {
    if (length(unique(x0)) < 2) return(FALSE)
    return(TRUE)
  }

  if (length(unique(x0)) < 5) return(FALSE)
  TRUE
}

normalize_calendar_covariates <- function(df) {
  if ("public_holiday" %in% names(df) && !("holiday" %in% names(df))) {
    df <- df %>% mutate(holiday = as.numeric(public_holiday))
  }
  if ("holiday" %in% names(df)) {
    df <- df %>% mutate(holiday = as.numeric(holiday))
  }
  if ("is_workday" %in% names(df)) {
    df <- df %>% mutate(is_workday = as.numeric(is_workday))
  }
  if ("is_weekend" %in% names(df)) {
    df <- df %>% mutate(is_weekend = as.numeric(is_weekend))
  }
  if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(df)) {
    df[[COVID_WAVE_VAR]] <- as.numeric(df[[COVID_WAVE_VAR]])
  }
  df
}

make_flu_adjust_colnames <- function(base_vars, suffix = "_avg_lag0_2") {
  paste0(base_vars, suffix)
}

get_env_adjust_strategy <- function(base_var) {
  if (base_var %in% POLLUTANT_VARS) {
    return(list(use_temp = TRUE, use_rhum = TRUE, strategy = "pollutant"))
  }
  if (base_var %in% TEMP_GROUP) {
    return(list(use_temp = FALSE, use_rhum = TRUE, strategy = "temperature-group"))
  }
  if (base_var %in% HUMID_GROUP) {
    return(list(use_temp = TRUE, use_rhum = FALSE, strategy = "humidity-group"))
  }
  if (base_var == "PRES") {
    return(list(use_temp = TRUE, use_rhum = TRUE, strategy = "pressure"))
  }
  list(use_temp = TRUE, use_rhum = TRUE, strategy = "default")
}

build_env_adjust_label <- function(base_var, include_flu = TRUE, include_covid = TRUE) {
  st <- get_env_adjust_strategy(base_var)
  lbl <- c(
    if (st$use_temp) "ns(Tavg_avg_lag0_2,6)" else NULL,
    if (st$use_rhum) "ns(RHUM_avg_lag0_2,3)" else NULL,
    "public_holiday",
    if (include_covid && RUN_COVID_WAVE_ADJUST) "covid_major_wave" else NULL
  )
  if (include_flu) {
    lbl <- c(lbl, "阳性率_avg_lag0_2")
  }
  paste(lbl, collapse = " + ")
}

build_flu_adjust_label <- function(include_covid = TRUE, include_holiday = TRUE) {
  paste(
    c(
      paste0("ns(", FLU_TEMP_AVG_COL, ",", FLU_TEMP_DF, ")"),
      paste0("ns(", FLU_RHUM_AVG_COL, ",", FLU_RHUM_DF, ")"),
      if (include_holiday) "public_holiday" else NULL,
      if (include_covid && RUN_COVID_WAVE_ADJUST) "covid_major_wave" else NULL
    ),
    collapse = " + "
  )
}

parse_event_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  x <- as.character(x)
  x <- trimws(x)
  x <- gsub("\\.", "-", x)
  x <- gsub("/", "-", x)
  as.Date(x)
}

is_heating_date <- function(d,
                            start_month = HEATING_START_MONTH,
                            start_day = HEATING_START_DAY,
                            end_month = HEATING_END_MONTH,
                            end_day = HEATING_END_DAY) {
  if (is.na(d)) return(NA)

  mmdd <- format(d, "%m-%d")
  start_mmdd <- sprintf("%02d-%02d", start_month, start_day)
  end_mmdd   <- sprintf("%02d-%02d", end_month, end_day)

  (mmdd >= start_mmdd) | (mmdd <= end_mmdd)
}

add_heating_flag <- function(df, event_date_var = EVENT_DATE_VAR) {
  if (!event_date_var %in% names(df)) {
    stop(paste0("缺少事件日列: ", event_date_var))
  }

  df %>%
    mutate(
      event_date = parse_event_date(.data[[event_date_var]]),
      event_month = as.integer(format(event_date, "%m")),
      heating_season = case_when(
        is.na(event_date) ~ NA_character_,
        vapply(event_date, is_heating_date, logical(1)) ~ "heating",
        TRUE ~ "non_heating"
      )
    )
}

add_covid_major_wave_flag <- function(df, date_var = EVENT_DATE_VAR, out_var = COVID_WAVE_VAR) {
  if (!date_var %in% names(df)) {
    stop(paste0("缺少日期列: ", date_var))
  }

  d <- parse_event_date(df[[date_var]])
  flag <- rep(0, length(d))
  flag[is.na(d)] <- NA_real_

  for (win in COVID_MAJOR_WAVE_WINDOWS) {
    start_d <- as.Date(win[1])
    end_d   <- as.Date(win[2])
    flag[!is.na(d) & d >= start_d & d <= end_d] <- 1
  }

  df[[out_var]] <- as.numeric(flag)
  df
}

clean_group_value_for_path <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x <- gsub("[/\\\\]+", "-", x)
  x <- gsub("[:*?\"<>|]+", "_", x)
  x <- gsub("\\s+", "_", x)
  x <- gsub("[^[:alnum:]_\\-\\+\\.]+", "_", x)
  x
}

should_keep_group_level <- function(group_var, level_value, keep_reference = TRUE) {
  lv <- as.character(level_value)
  if (keep_reference) return(TRUE)
  bad_levels <- c("No", "Other", "Neither", "Non-infective", "Non-airway-reactive", "0")
  !(lv %in% bad_levels)
}

get_valid_group_levels <- function(df,
                                   group_var,
                                   outcome_var = OUTCOME_VAR,
                                   min_cases = MIN_CASES_PER_GROUP_LEVEL,
                                   min_rows = MIN_ROWS_PER_GROUP_LEVEL,
                                   keep_reference = KEEP_REFERENCE_LEVELS) {
  if (!(group_var %in% names(df))) return(tibble())

  tmp <- df %>%
    filter(!is.na(.data[[group_var]])) %>%
    mutate(group_level = as.character(.data[[group_var]])) %>%
    group_by(group_level) %>%
    summarise(
      n_rows = n(),
      n_cases = sum(.data[[outcome_var]] == 1, na.rm = TRUE),
      n_controls = sum(.data[[outcome_var]] == 0, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_rows >= min_rows, n_cases >= min_cases, n_controls > 0) %>%
    filter(vapply(group_level, function(z) should_keep_group_level(group_var, z, keep_reference), logical(1)))

  tmp
}

make_group_subset_tag <- function(group_var, group_level, prefix = "group") {
  gv <- clean_group_value_for_path(group_var)
  gl <- clean_group_value_for_path(group_level)
  paste0(prefix, "__", gv, "__", gl)
}

make_required_multi_day_lags <- function(df, vars, max_lag = 7) {
  for (v in vars) {
    lag_cols <- paste0(v, "_lag", 0:max_lag)
    if (!all(lag_cols %in% names(df))) next

    for (k in 1:max_lag) {
      new_name <- paste0(v, "_avg_lag0_", k)

      if (!new_name %in% names(df)) {
        use_cols <- paste0(v, "_lag", 0:k)
        tmp <- rowMeans(df[, use_cols], na.rm = TRUE)
        n_ok <- rowSums(!is.na(df[, use_cols]))

        min_required <- ifelse(k <= 2, 2, k)
        tmp[n_ok < min_required] <- NA_real_

        df[[new_name]] <- tmp
      }
    }
  }
  df
}

safe_df_for_ns <- function(x, target_df = 3, min_unique = 5) {
  x <- x[safe_is_finite(x)]
  ux <- length(unique(x))
  if (ux < 2) return(NA_integer_)
  if (ux < min_unique) return(max(1L, min(target_df, ux - 1L)))
  target_df
}

make_crossbasis_safe <- function(xmat, max_lag = 35, df_var_target = 3, df_lag = 4) {
  x_all <- as.numeric(xmat)
  x_all <- x_all[safe_is_finite(x_all)]

  if (length(x_all) < 10 || length(unique(x_all)) < 2) {
    return(list(cb = NULL, argvar_used = "skip_constant", df_var_used = NA_integer_, msg = "exposure constant/too few"))
  }

  df_use <- safe_df_for_ns(x_all, target_df = df_var_target, min_unique = df_var_target + 2)

  try_ns <- function(d) {
    crossbasis(
      x = xmat,
      lag = max_lag,
      argvar = list(fun = "ns", df = d),
      arglag = list(fun = "ns", df = df_lag)
    )
  }

  if (!is.na(df_use) && df_use >= 2) {
    cb1 <- tryCatch(try_ns(df_use), error = function(e) NULL)
    if (!is.null(cb1)) return(list(cb = cb1, argvar_used = "ns", df_var_used = df_use, msg = "ok"))

    cb2 <- tryCatch(try_ns(max(1, df_use - 1)), error = function(e) NULL)
    if (!is.null(cb2)) return(list(cb = cb2, argvar_used = "ns", df_var_used = max(1, df_use - 1), msg = "ns downgraded"))
  }

  cb3 <- tryCatch(
    crossbasis(
      x = xmat,
      lag = max_lag,
      argvar = list(fun = "lin"),
      arglag = list(fun = "ns", df = df_lag)
    ),
    error = function(e) NULL
  )
  if (!is.null(cb3)) return(list(cb = cb3, argvar_used = "lin", df_var_used = 1L, msg = "fallback lin"))

  list(cb = NULL, argvar_used = "skip_failed", df_var_used = NA_integer_, msg = "crossbasis failed")
}

run_clogit_lags_0_7 <- function(df, base_var, lags = 0:7,
                                strata_var = STRATA_VAR, cluster_var = NULL) {
  out_list <- list()
  fail_list <- list()

  scale_value <- NA_real_
  scale_label <- NA_character_


  need_base <- c(
    OUTCOME_VAR, strata_var,
    FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday",
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL
  )
  if (!is.null(cluster_var)) need_base <- unique(c(need_base, cluster_var))

  for (k in lags) {
    xk_name <- paste0(base_var, "_lag", k)
    if (!xk_name %in% names(df)) {
      fail_list[[as.character(k)]] <- tibble(variable = base_var, lag = k, reason = "missing lag column")
      next
    }

    need <- unique(c(need_base, xk_name))
    need <- unique(need[need %in% names(df)])

    if (!all(c(OUTCOME_VAR, strata_var, xk_name, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday") %in% names(df))) {
      fail_list[[as.character(k)]] <- tibble(variable = base_var, lag = k, reason = "missing exposure or covariates")
      next
    }

    d <- df %>%
      select(all_of(need)) %>%
      transmute(
        outcome = as.numeric(.data[[OUTCOME_VAR]]),
        strata  = as.character(.data[[strata_var]]),
        xk      = suppressWarnings(as.numeric(.data[[xk_name]])),
        temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
        rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
        holiday2 = as.numeric(.data[["holiday"]]),
        cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_,
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
          suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
        } else NA_real_
      ) %>%
      filter(
        !is.na(outcome), !is.na(strata),
        safe_is_finite(xk),
        safe_is_finite(temp_02),
        safe_is_finite(rhum_02),
        !is.na(holiday2)
      )

    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    valid_strata <- d %>%
      group_by(strata) %>%
      summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
      filter(has_case & has_ctrl) %>%
      pull(strata)

    if (length(valid_strata) < 3) {
      fail_list[[as.character(k)]] <- tibble(variable = base_var, lag = k, reason = "too few valid strata")
      next
    }

    d <- d %>% filter(strata %in% valid_strata)

    scale_value <- get_scale_value(d, base_var)
    scale_label <- get_scale_label(d, base_var)

    rhs_terms <- c(
      "xk",
      paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
      paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
      "holiday2"
    )

    if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")

    fml <- as.formula(
      paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
    )

    fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
    if (is.null(fit)) {
      fail_list[[as.character(k)]] <- tibble(variable = base_var, lag = k, reason = "clogit failed")
      next
    }

    coef_info <- safe_coef_se(fit, "xk", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
    if (!isTRUE(coef_info$ok)) {
      fail_list[[as.character(k)]] <- tibble(variable = base_var, lag = k, reason = "coef/se invalid")
      next
    }

    beta <- coef_info$beta
    se   <- coef_info$se
    iqr_k <- get_analysis_iqr(base_var)

    adjust_label <- build_flu_adjust_label(include_covid = TRUE, include_holiday = TRUE)

    r_scaled <- tibble(
      variable = base_var,
      var_label = add_var_label(base_var),
      group = add_group(base_var),
      lag = k,
      effect_type = "per_scaled_unit",
      scale_value = scale_value,
      scale_label = scale_label,
      iqr_value = NA_real_,
      adjust_vars = adjust_label,
      or = exp(beta * scale_value),
      ci_low = exp((beta - 1.96 * se) * scale_value),
      ci_high = exp((beta + 1.96 * se) * scale_value),
      p_value = 2 * (1 - pnorm(abs(beta / se))),
      n_cases = sum(d$outcome == 1),
      n_controls = sum(d$outcome == 0),
      n_strata = length(valid_strata)
    )

    r_iqr <- tibble(
      variable = base_var,
      var_label = add_var_label(base_var),
      group = add_group(base_var),
      lag = k,
      effect_type = "per_iqr",
      scale_value = NA_real_,
      scale_label = "per IQR (global)",
      iqr_value = iqr_k,
      adjust_vars = adjust_label,
      or = ifelse(is.finite(iqr_k) & iqr_k > 0, exp(beta * iqr_k), NA_real_),
      ci_low = ifelse(is.finite(iqr_k) & iqr_k > 0, exp((beta - 1.96 * se) * iqr_k), NA_real_),
      ci_high = ifelse(is.finite(iqr_k) & iqr_k > 0, exp((beta + 1.96 * se) * iqr_k), NA_real_),
      p_value = 2 * (1 - pnorm(abs(beta / se))),
      n_cases = sum(d$outcome == 1),
      n_controls = sum(d$outcome == 0),
      n_strata = length(valid_strata)
    )

    out_list[[paste0("lag", k)]] <- bind_rows(r_scaled, r_iqr)
  }

  list(
    ok = length(out_list) > 0,
    res = if (length(out_list) > 0) bind_rows(out_list) else tibble(),
    fail = if (length(fail_list) > 0) bind_rows(fail_list) else tibble()
  )
}

run_clogit_agg_exposures <- function(df, col_name,
                                     strata_var = STRATA_VAR, cluster_var = NULL) {
  base_var <- col_name
  agg_type <- "agg"
  m <- stringr::str_match(col_name, "^(.+?)_(avg_lag0_2|avg_lag0_7|max_lag0_2)$")
  if (!is.na(m[1, 1])) {
    base_var <- m[1, 2]
    agg_type <- m[1, 3]
  }

  need <- c(
    OUTCOME_VAR, strata_var, col_name,
    FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday",
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL
  )
  if (!is.null(cluster_var)) need <- unique(c(need, cluster_var))
  need <- unique(need[need %in% names(df)])

  if (!all(c(OUTCOME_VAR, strata_var, col_name, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday") %in% names(df))) {
    return(list(ok = FALSE, res = tibble(), fail = tibble(variable = col_name, reason = "missing column or covariates")))
  }

  d <- df %>%
    select(all_of(need)) %>%
    transmute(
      outcome = as.numeric(.data[[OUTCOME_VAR]]),
      strata  = as.character(.data[[strata_var]]),
      x       = suppressWarnings(as.numeric(.data[[col_name]])),
      temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
      rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
      holiday2 = as.numeric(.data[["holiday"]]),
      cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_,
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_
    ) %>%
    filter(
      !is.na(outcome), !is.na(strata),
      safe_is_finite(x),
      safe_is_finite(temp_02),
      safe_is_finite(rhum_02),
      !is.na(holiday2)
    )

  if (RUN_COVID_WAVE_ADJUST) {
    d <- d %>% filter(!is.na(covid_wave2))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(list(ok = FALSE, res = tibble(), fail = tibble(variable = col_name, reason = "too few valid strata")))
  }

  d <- d %>% filter(strata %in% valid_strata)

  scale_value <- get_scale_value(d, base_var)
  scale_label <- get_scale_label(d, base_var)

  rhs_terms <- c(
    "x",
    paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
    paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
    "holiday2"
  )

  if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")


  fml <- as.formula(
    paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(ok = FALSE, res = tibble(), fail = tibble(variable = col_name, reason = "clogit failed")))
  }

  coef_info <- safe_coef_se(fit, "x", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
  if (!isTRUE(coef_info$ok)) {
    return(list(ok = FALSE, res = tibble(), fail = tibble(variable = col_name, reason = "coef/se invalid")))
  }

  beta <- coef_info$beta
  se   <- coef_info$se
  iqr_x <- get_analysis_iqr(base_var)



  adjust_label <- build_flu_adjust_label(include_covid = TRUE, include_holiday = TRUE)

  r_scaled <- tibble(
    variable = base_var,
    var_label = add_var_label(base_var),
    group = add_group(base_var),
    agg_type = agg_type,
    effect_type = "per_scaled_unit",
    scale_value = scale_value,
    scale_label = scale_label,
    iqr_value = NA_real_,
    adjust_vars = adjust_label,
    or = exp(beta * scale_value),
    ci_low = exp((beta - 1.96 * se) * scale_value),
    ci_high = exp((beta + 1.96 * se) * scale_value),
    p_value = 2 * (1 - pnorm(abs(beta / se))),
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata)
  )

  r_iqr <- tibble(
    variable = base_var,
    var_label = add_var_label(base_var),
    group = add_group(base_var),
    agg_type = agg_type,
    effect_type = "per_iqr",
    scale_value = NA_real_,
    scale_label = "per IQR (global)",
    iqr_value = iqr_x,
    adjust_vars = adjust_label,
    or = ifelse(is.finite(iqr_x) & iqr_x > 0, exp(beta * iqr_x), NA_real_),
    ci_low = ifelse(is.finite(iqr_x) & iqr_x > 0, exp((beta - 1.96 * se) * iqr_x), NA_real_),
    ci_high = ifelse(is.finite(iqr_x) & iqr_x > 0, exp((beta + 1.96 * se) * iqr_x), NA_real_),
    p_value = 2 * (1 - pnorm(abs(beta / se))),
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata)
  )

  list(ok = TRUE, res = bind_rows(r_scaled, r_iqr), fail = tibble())
}

run_one_dlnm <- function(df, base_var,
                         max_lag = 35, focus_lags = 0:7, focus_win = c(0, 7),
                         strata_var = STRATA_VAR,
                         cluster_var = NULL,
                         df_var_target = 3, df_lag = 4,
                         effect_type = c("per_scaled_unit", "per_iqr"),
                         max_miss_lag0 = 0.8) {

  effect_type <- match.arg(effect_type)

  lag_cols <- paste0(base_var, "_lag", 0:max_lag)
  if (!all(lag_cols %in% names(df))) return(list(ok = FALSE, error = "missing lag columns"))

  need <- c(
    OUTCOME_VAR, strata_var, lag_cols,
    FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday",
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL
  )
  if (!is.null(cluster_var)) need <- unique(c(need, cluster_var))
  need <- unique(need[need %in% names(df)])

  if (!all(c(OUTCOME_VAR, strata_var, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday") %in% names(df))) {
    return(list(ok = FALSE, error = "missing covariates"))
  }

  d <- df %>%
    select(all_of(need)) %>%
    mutate(
      outcome_num = as.numeric(.data[[OUTCOME_VAR]]),
      strata_id   = as.character(.data[[strata_var]]),
      cluster_id2 = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_,
      temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
      rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
      holiday2 = as.numeric(.data[["holiday"]]),
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_
    ) %>%
    filter(
      !is.na(outcome_num),
      !is.na(strata_id),
      safe_is_finite(temp_02),
      safe_is_finite(rhum_02),
      !is.na(holiday2)
    )

  if (RUN_COVID_WAVE_ADJUST) {
    d <- d %>% filter(!is.na(covid_wave2))
  }

  valid_strata <- d %>%
    group_by(strata_id) %>%
    summarise(has_case = any(outcome_num == 1), has_ctrl = any(outcome_num == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(strata_id)

  if (length(valid_strata) < 3) return(list(ok = FALSE, error = "too few valid strata"))
  d <- d %>% filter(strata_id %in% valid_strata)

  xmat <- as.matrix(d[, lag_cols])
  storage.mode(xmat) <- "numeric"

  miss0 <- mean(is.na(xmat[, 1]))
  if (!is.finite(miss0) || miss0 > max_miss_lag0) {
    return(list(ok = FALSE, error = sprintf("lag0 missing too high (%.1f%%)", 100 * miss0)))
  }

  ref <- median(xmat[, 1], na.rm = TRUE)
  if (!is.finite(ref)) return(list(ok = FALSE, error = "ref not finite"))

  if (effect_type == "per_scaled_unit") {
    scale_value <- get_scale_value(d, base_var)
    scale_label <- get_scale_label(d, base_var)
    delta <- scale_value
    iqr_val <- NA_real_
  } else {
    scale_value <- NA_real_
    scale_label <- "per IQR (global)"
    iqr_val <- get_analysis_iqr(base_var)
    if (!is.finite(iqr_val) || iqr_val <= 0) return(list(ok = FALSE, error = "invalid global IQR"))
    delta <- iqr_val
  }


  at_val <- ref + delta

  cb_info <- make_crossbasis_safe(xmat, max_lag = max_lag, df_var_target = df_var_target, df_lag = df_lag)
  cb <- cb_info$cb
  if (is.null(cb)) {
    return(list(ok = FALSE, error = paste0("crossbasis failed: ", cb_info$argvar_used, " | ", cb_info$msg),
                argvar_used = cb_info$argvar_used, df_var_used = cb_info$df_var_used))
  }

  rhs_terms <- c(
    "cb",
    paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
    paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
    "holiday2"
  )
  if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")

  fml <- as.formula(
    paste0("outcome_num ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata_id)")
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) return(list(ok = FALSE, error = "clogit failed"))

  pred <- tryCatch(
    crosspred(cb, fit, at = at_val, cen = ref, bylag = 1, cumul = TRUE),
    error = function(e) NULL
  )
  if (is.null(pred)) return(list(ok = FALSE, error = "crosspred failed"))

  fit_lag <- as.numeric(pred$matfit[1, focus_lags + 1])
  se_lag  <- as.numeric(pred$matse[1,  focus_lags + 1])

  adjust_label <- build_flu_adjust_label(include_covid = TRUE, include_holiday = TRUE)

  lag_df <- tibble(
    variable = base_var,
    var_label = add_var_label(base_var),
    group = add_group(base_var),
    effect_type = effect_type,
    scale_value = scale_value,
    scale_label = scale_label,
    iqr_value = iqr_val,
    adjust_vars = adjust_label,
    ref_value = ref,
    delta = delta,
    at_value = at_val,
    argvar_used = cb_info$argvar_used,
    df_var_used = cb_info$df_var_used,
    lag = focus_lags,
    or = exp(fit_lag),
    ci_low = exp(fit_lag - 1.96 * se_lag),
    ci_high = exp(fit_lag + 1.96 * se_lag),
    p_value = 2 * (1 - pnorm(abs(fit_lag / se_lag))),
    n_cases = sum(d$outcome_num == 1),
    n_controls = sum(d$outcome_num == 0),
    n_strata = length(valid_strata)
  )

  end_lag <- focus_win[2]
  cum_fit_07 <- as.numeric(pred$cumfit[1, end_lag + 1])
  cum_se_07  <- as.numeric(pred$cumse[1, end_lag + 1])

  cum_df <- tibble(
    variable = base_var,
    var_label = add_var_label(base_var),
    group = add_group(base_var),
    effect_type = effect_type,
    scale_value = scale_value,
    scale_label = scale_label,
    iqr_value = iqr_val,
    adjust_vars = adjust_label,
    ref_value = ref,
    delta = delta,
    at_value = at_val,
    argvar_used = cb_info$argvar_used,
    df_var_used = cb_info$df_var_used,
    window = paste0(focus_win[1], "-", focus_win[2]),
    cum_or = exp(cum_fit_07),
    cum_ci_low = exp(cum_fit_07 - 1.96 * cum_se_07),
    cum_ci_high = exp(cum_fit_07 + 1.96 * cum_se_07),
    cum_p_value = 2 * (1 - pnorm(abs(cum_fit_07 / cum_se_07))),
    n_cases = sum(d$outcome_num == 1),
    n_controls = sum(d$outcome_num == 0),
    n_strata = length(valid_strata)
  )

  cum_fit_all <- as.numeric(pred$cumfit[1, max_lag + 1])
  cum_se_all  <- as.numeric(pred$cumse[1, max_lag + 1])

  cum_df <- cum_df %>%
    mutate(
      cum_or_0_35 = exp(cum_fit_all),
      cum_ci_low_0_35 = exp(cum_fit_all - 1.96 * cum_se_all),
      cum_ci_high_0_35 = exp(cum_fit_all + 1.96 * cum_se_all),
      cum_p_value_0_35 = 2 * (1 - pnorm(abs(cum_fit_all / cum_se_all)))
    )

  meta <- tibble(
    variable = base_var,
    var_label = add_var_label(base_var),
    group = add_group(base_var),
    effect_type = effect_type,
    scale_value = scale_value,
    scale_label = scale_label,
    adjust_vars = adjust_label,
    argvar_used = cb_info$argvar_used,
    df_var_used = cb_info$df_var_used,
    miss_lag0 = miss0
  )

  list(ok = TRUE, lag_effects = lag_df, cum_effects = cum_df, meta = meta)
}

run_env_main_lag_models <- function(df, base_var,
                                    strata_var = STRATA_VAR,
                                    cluster_var = NULL,
                                    outcome_var = OUTCOME_VAR) {

  exposure_candidates <- c(
    paste0(base_var, "_lag", ENV_SINGLE_LAGS),
    paste0(base_var, "_", ENV_MULTI_LAGS)
  )
  exposure_candidates <- exposure_candidates[exposure_candidates %in% names(df)]

  if (length(exposure_candidates) == 0) {
    return(list(ok = FALSE, res = tibble(), fail = tibble(variable = base_var, reason = "no candidate exposure columns")))
  }

  flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
  flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

  adj_strategy <- get_env_adjust_strategy(base_var)
  use_temp_spline <- adj_strategy$use_temp
  use_rhum_spline <- adj_strategy$use_rhum

  env_covars_needed <- c("holiday")
  if (use_temp_spline) env_covars_needed <- c(env_covars_needed, "Tavg_avg_lag0_2")
  if (use_rhum_spline) env_covars_needed <- c(env_covars_needed, "RHUM_avg_lag0_2")
  if (RUN_COVID_WAVE_ADJUST) env_covars_needed <- c(env_covars_needed, COVID_WAVE_VAR)

  missing_covars <- setdiff(env_covars_needed, names(df))
  if (length(missing_covars) > 0) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = base_var, reason = paste("missing covariates:", paste(missing_covars, collapse = ", ")))
    ))
  }

  out_list <- list()
  fail_list <- list()



  for (xname in exposure_candidates) {
    need <- c(
      outcome_var, strata_var, xname, "holiday",
      if (use_temp_spline) "Tavg_avg_lag0_2" else NULL,
      if (use_rhum_spline) "RHUM_avg_lag0_2" else NULL,
      flu_adjust_cols,
      if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL
    )
    if (!is.null(cluster_var)) need <- unique(c(need, cluster_var))

    d <- df %>%
      select(all_of(intersect(need, names(df)))) %>%
      transmute(
        outcome = as.numeric(.data[[outcome_var]]),
        strata  = as.character(.data[[strata_var]]),
        exposure = suppressWarnings(as.numeric(.data[[xname]])),
        temp_02 = if (use_temp_spline) suppressWarnings(as.numeric(.data[["Tavg_avg_lag0_2"]])) else NA_real_,
        rhum_02 = if (use_rhum_spline) suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])) else NA_real_,
        holiday2 = as.numeric(.data[["holiday"]]),
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
          suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
        } else NA_real_,
        flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_,
        cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_
      ) %>%
      filter(
        !is.na(outcome), !is.na(strata),
        safe_is_finite(exposure),
        !is.na(holiday2)
      )

    if (use_temp_spline) {
      d <- d %>% filter(safe_is_finite(temp_02))
    }
    if (use_rhum_spline) {
      d <- d %>% filter(safe_is_finite(rhum_02))
    }
    if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
      d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
    }
    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    valid_strata <- d %>%
      group_by(strata) %>%
      summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
      filter(has_case & has_ctrl) %>%
      pull(strata)

    if (length(valid_strata) < 3) {
      fail_list[[xname]] <- tibble(variable = base_var, exposure_term = xname, reason = "too few valid strata")
      next
    }

    d <- d %>% filter(strata %in% valid_strata)

    scale_value <- get_scale_value(d, base_var)
    scale_label <- get_scale_label(d, base_var)

    rhs_terms <- c("exposure")
    if (use_temp_spline) rhs_terms <- c(rhs_terms, "ns(temp_02, df = 6)")
    if (use_rhum_spline) rhs_terms <- c(rhs_terms, "ns(rhum_02, df = 3)")
    rhs_terms <- c(rhs_terms, "holiday2")
    if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")
    if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) rhs_terms <- c(rhs_terms, "flu_posrate_02")

    fml <- as.formula(
      paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
    )

    fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
    if (is.null(fit)) {
      fail_list[[xname]] <- tibble(variable = base_var, exposure_term = xname, reason = "clogit failed")
      next
    }

    coef_info <- safe_coef_se(fit, "exposure", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
    if (!isTRUE(coef_info$ok)) {
      fail_list[[xname]] <- tibble(variable = base_var, exposure_term = xname, reason = "coef/se invalid")
      next
    }

    beta <- coef_info$beta
    se   <- coef_info$se
    iqr_x <- get_analysis_iqr(base_var)

    aic_val <- tryCatch(AIC(fit), error = function(e) NA_real_)

    adjust_label <- c(
      if (use_temp_spline) "ns(Tavg_avg_lag0_2,6)" else NULL,
      if (use_rhum_spline) "ns(RHUM_avg_lag0_2,3)" else NULL,
      "public_holiday",
      if (RUN_COVID_WAVE_ADJUST) "covid_major_wave" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "阳性率_avg_lag0_2" else NULL
    )
    adjust_label <- paste(adjust_label, collapse = " + ")

    out_list[[xname]] <- bind_rows(
      tibble(
        variable = base_var,
        var_label = add_var_label(base_var),
        group = add_group(base_var),
        exposure_term = xname,
        effect_type = "per_scaled_unit",
        scale_value = scale_value,
        scale_label = scale_label,
        iqr_value = NA_real_,
        adjust_vars = adjust_label,
        beta = beta,
        se = se,
        or = exp(beta * scale_value),
        ci_low = exp((beta - 1.96 * se) * scale_value),
        ci_high = exp((beta + 1.96 * se) * scale_value),
        p_value = 2 * (1 - pnorm(abs(beta / se))),
        aic = aic_val,
        n_cases = sum(d$outcome == 1),
        n_controls = sum(d$outcome == 0),
        n_strata = length(valid_strata),
        env_adjust_strategy = adj_strategy$strategy
      ),
      tibble(
        variable = base_var,
        var_label = add_var_label(base_var),
        group = add_group(base_var),
        exposure_term = xname,
        effect_type = "per_iqr",
        scale_value = NA_real_,
        scale_label = "per IQR (global)",
        iqr_value = iqr_x,
        adjust_vars = adjust_label,
        beta = beta,
        se = se,
        or = ifelse(is.finite(iqr_x) & iqr_x > 0, exp(beta * iqr_x), NA_real_),
        ci_low = ifelse(is.finite(iqr_x) & iqr_x > 0, exp((beta - 1.96 * se) * iqr_x), NA_real_),
        ci_high = ifelse(is.finite(iqr_x) & iqr_x > 0, exp((beta + 1.96 * se) * iqr_x), NA_real_),
        p_value = 2 * (1 - pnorm(abs(beta / se))),
        aic = aic_val,
        n_cases = sum(d$outcome == 1),
        n_controls = sum(d$outcome == 0),
        n_strata = length(valid_strata),
        env_adjust_strategy = adj_strategy$strategy
      )
    )
  }

  list(
    ok = length(out_list) > 0,
    res = if (length(out_list) > 0) bind_rows(out_list) else tibble(),
    fail = if (length(fail_list) > 0) bind_rows(fail_list) else tibble()
  )
}

run_env_count_main_model <- function(df, exposure_col,
                                     display_var = exposure_col,
                                     strata_var = STRATA_VAR,
                                     cluster_var = NULL,
                                     outcome_var = OUTCOME_VAR) {

  if (!exposure_col %in% names(df)) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = display_var, exposure_term = exposure_col, reason = "missing exposure column")
    ))
  }

  flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
  flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

  env_covars_needed <- c("holiday", "RHUM_avg_lag0_2")
  if (RUN_COVID_WAVE_ADJUST) env_covars_needed <- c(env_covars_needed, COVID_WAVE_VAR)

  missing_covars <- setdiff(env_covars_needed, names(df))
  if (length(missing_covars) > 0) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = display_var, exposure_term = exposure_col,
                    reason = paste("missing covariates:", paste(missing_covars, collapse = ", ")))
    ))
  }

  need <- c(
    outcome_var, strata_var, exposure_col, "holiday", "RHUM_avg_lag0_2",
    flu_adjust_cols,
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL
  )
  if (!is.null(cluster_var)) need <- unique(c(need, cluster_var))

  d <- df %>%
    select(all_of(intersect(need, names(df)))) %>%
    transmute(
      outcome = as.numeric(.data[[outcome_var]]),
      strata  = as.character(.data[[strata_var]]),
      exposure = suppressWarnings(as.numeric(.data[[exposure_col]])),
      rhum_02 = suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])),
      holiday2 = as.numeric(.data[["holiday"]]),
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_,
      flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_,
      cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_
    ) %>%
    filter(
      !is.na(outcome), !is.na(strata),
      safe_is_finite(exposure),
      safe_is_finite(rhum_02),
      !is.na(holiday2)
    )

  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
    d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
  }
  if (RUN_COVID_WAVE_ADJUST) {
    d <- d %>% filter(!is.na(covid_wave2))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = display_var, exposure_term = exposure_col, reason = "too few valid strata")
    ))
  }

  d <- d %>% filter(strata %in% valid_strata)

  rhs_terms <- c("exposure", "ns(rhum_02, df = 3)", "holiday2")
  if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")
  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) rhs_terms <- c(rhs_terms, "flu_posrate_02")

  fml <- as.formula(
    paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = display_var, exposure_term = exposure_col, reason = "clogit failed")
    ))
  }

  coef_info <- safe_coef_se(fit, "exposure", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
  if (!isTRUE(coef_info$ok)) {
    return(list(
      ok = FALSE,
      res = tibble(),
      fail = tibble(variable = display_var, exposure_term = exposure_col, reason = "coef/se invalid")
    ))
  }

  beta <- coef_info$beta
  se   <- coef_info$se
  aic_val <- tryCatch(AIC(fit), error = function(e) NA_real_)

  scale_value <- get_scale_value(d, display_var)
  scale_label <- get_scale_label(d, display_var)


  adjust_label <- c(
    "ns(RHUM_avg_lag0_2,3)",
    "public_holiday",
    if (RUN_COVID_WAVE_ADJUST) "covid_major_wave" else NULL,
    if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "阳性率_avg_lag0_2" else NULL
  )
  adjust_label <- paste(adjust_label, collapse = " + ")

  res <- tibble(
    variable = display_var,
    var_label = add_var_label(display_var),
    group = add_group(display_var),
    exposure_term = exposure_col,
    effect_type = "per_scaled_unit",
    scale_value = scale_value,
    scale_label = scale_label,
    iqr_value = NA_real_,
    adjust_vars = adjust_label,
    beta = beta,
    se = se,
    or = exp(beta * scale_value),
    ci_low = exp((beta - 1.96 * se) * scale_value),
    ci_high = exp((beta + 1.96 * se) * scale_value),
    p_value = 2 * (1 - pnorm(abs(beta / se))),
    aic = aic_val,
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata),
    env_adjust_strategy = "extreme-temp-count"
  )

  list(ok = TRUE, res = res, fail = tibble())
}

run_temp_nl_dlnm_analysis <- function(df,
                                      temp_var,
                                      strata_var = STRATA_VAR,
                                      cluster_var = NULL,
                                      outcome_var = OUTCOME_VAR,
                                      max_lag = TEMP_NL_DLNM_MAX_LAG,
                                      df_var = TEMP_NL_DLNM_DF_VAR,
                                      df_lag = TEMP_NL_DLNM_DF_LAG,
                                      pred_q = TEMP_NL_DLNM_PRED_Q,
                                      pred_n = TEMP_NL_DLNM_PRED_N) {

  lag_cols <- paste0(temp_var, "_lag", 0:max_lag)
  if (!all(lag_cols %in% names(df))) {
    return(list(ok = FALSE, error = paste("missing lag columns for", temp_var)))
  }

  flu_adjust_cols <- make_flu_adjust_colnames(c("阳性率"), FLU_ADJ_SUFFIX)
  flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

  need_cols <- c(
    strata_var, outcome_var, lag_cols, "holiday", "RHUM_avg_lag0_2", flu_adjust_cols,
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL,
    if (!is.null(cluster_var)) cluster_var else NULL
  )
  need_cols <- unique(intersect(need_cols, names(df)))

  d <- df %>%
    select(all_of(need_cols)) %>%
    mutate(
      outcome = as.numeric(.data[[outcome_var]]),
      strata  = as.character(.data[[strata_var]]),
      cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_,
      holiday2 = as.numeric(.data[["holiday"]]),
      rhum_02  = suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])),
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_,
      flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_
    ) %>%
    mutate(across(all_of(lag_cols), ~ suppressWarnings(as.numeric(.x)))) %>%
    filter(
      !is.na(outcome),
      !is.na(strata),
      !is.na(holiday2),
      safe_is_finite(rhum_02)
    )

  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
    d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
  }
  if (RUN_COVID_WAVE_ADJUST) {
    d <- d %>% filter(!is.na(covid_wave2))
  }

  xmat <- as.matrix(d[, lag_cols, drop = FALSE])
  storage.mode(xmat) <- "numeric"

  keep <- apply(xmat, 1, function(z) any(is.finite(z)))
  d <- d[keep, , drop = FALSE]
  xmat <- xmat[keep, , drop = FALSE]

  if (nrow(d) < 50) {
    return(list(ok = FALSE, error = paste("too few rows for", temp_var)))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(list(ok = FALSE, error = paste("too few valid strata for", temp_var)))
  }

  idx <- d$strata %in% valid_strata
  d <- d[idx, , drop = FALSE]
  xmat <- xmat[idx, , drop = FALSE]

  x0 <- xmat[, 1]
  x0_fin <- x0[safe_is_finite(x0)]
  if (length(x0_fin) < 30) {
    return(list(ok = FALSE, error = paste("too few finite lag0 values for", temp_var)))
  }

  ref_temp <- median(x0_fin, na.rm = TRUE)
  pred_min <- as.numeric(quantile(x0_fin, pred_q[1], na.rm = TRUE))
  pred_max <- as.numeric(quantile(x0_fin, pred_q[2], na.rm = TRUE))

  if (!is.finite(ref_temp) || !is.finite(pred_min) || !is.finite(pred_max) || pred_min >= pred_max) {
    return(list(ok = FALSE, error = paste("invalid prediction range for", temp_var)))
  }

  cb <- tryCatch(
    crossbasis(
      x = xmat,
      lag = max_lag,
      argvar = list(fun = "ns", df = df_var),
      arglag = list(fun = "ns", df = df_lag)
    ),
    error = function(e) NULL
  )

  if (is.null(cb)) {
    return(list(ok = FALSE, error = paste("crossbasis failed for", temp_var)))
  }

  rhs_terms <- c("cb", "ns(rhum_02, df = 3)", "holiday2")
  if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")
  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) rhs_terms <- c(rhs_terms, "flu_posrate_02")

  fml <- as.formula(
    paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(ok = FALSE, error = paste("clogit failed for", temp_var)))
  }
  model_vcov <- get_model_vcov(
    fit,
    if (!is.null(cluster_var)) d$cluster else NULL
  )
  if (is.null(model_vcov)) {
    return(list(ok = FALSE, error = paste("variance estimation failed for", temp_var)))
  }

  pred_grid <- seq(pred_min, pred_max, length.out = pred_n)

  pred <- tryCatch(
    crosspred(
      basis = cb,
      model = fit,
      vcov = model_vcov,
      at = pred_grid,
      cen = ref_temp,
      bylag = 1,
      cumul = TRUE
    ),
    error = function(e) NULL
  )

  if (is.null(pred)) {
    return(list(ok = FALSE, error = paste("crosspred failed for", temp_var)))
  }

  overall_df <- tibble(
    variable = temp_var,
    var_label = add_var_label(temp_var),
    ref_value = ref_temp,
    exposure = as.numeric(pred$predvar),
    cumul_rr = as.numeric(pred$allRRfit),
    cumul_low = as.numeric(pred$allRRlow),
    cumul_high = as.numeric(pred$allRRhigh),
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata),
    aic = tryCatch(AIC(fit), error = function(e) NA_real_),
    adjust_vars = paste(c(
      "ns(RHUM_avg_lag0_2,3)",
      "public_holiday",
      if (RUN_COVID_WAVE_ADJUST) "covid_major_wave" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "阳性率_avg_lag0_2" else NULL
    ), collapse = " + ")
  )

  lag_specific_days <- c(0, 1, 3, 5, 7, 14, 21)
  lag_specific_days <- lag_specific_days[lag_specific_days <= max_lag]

  global_iqr_temp <- get_analysis_iqr(temp_var)
  ref_plus_iqr <- if (is.finite(global_iqr_temp) && global_iqr_temp > 0) {
    ref_temp + global_iqr_temp
  } else {
    ref_temp + 5
  }


  lag_spec_list <- list()
  for (lg in lag_specific_days) {
    p_lag <- tryCatch(
      crosspred(
        basis = cb,
        model = fit,
        vcov = model_vcov,
        at = ref_plus_iqr,
        cen = ref_temp,
        lag = lg
      ),
      error = function(e) NULL
    )

    if (!is.null(p_lag)) {
      lag_spec_list[[as.character(lg)]] <- tibble(
        variable = temp_var,
        var_label = add_var_label(temp_var),
        lag = lg,
        ref_value = ref_temp,
        contrast_value = ref_plus_iqr,
        rr = as.numeric(p_lag$matRRfit[1, 1]),
        rr_low = as.numeric(p_lag$matRRlow[1, 1]),
        rr_high = as.numeric(p_lag$matRRhigh[1, 1])
      )
    }
  }

  lag_specific_df <- if (length(lag_spec_list) > 0) bind_rows(lag_spec_list) else tibble()

  rr_mat <- pred$matRRfit
  exp_vals <- as.numeric(pred$predvar)
  lag_vals <- 0:max_lag

  if (nrow(rr_mat) != length(exp_vals)) {
    return(list(ok = FALSE, error = paste("row mismatch in matRRfit for", temp_var)))
  }
  if (ncol(rr_mat) != length(lag_vals)) {
    return(list(ok = FALSE, error = paste("column mismatch in matRRfit for", temp_var)))
  }

  contour_df <- expand.grid(
    exp_id = seq_along(exp_vals),
    lag_id = seq_along(lag_vals)
  ) %>%
    mutate(
      exposure = exp_vals[exp_id],
      lag = lag_vals[lag_id],
      rr = rr_mat[cbind(exp_id, lag_id)],
      variable = temp_var,
      var_label = add_var_label(temp_var),
      ref_value = ref_temp
    ) %>%
    select(variable, var_label, exposure, lag, rr, ref_value) %>%
    filter(is.finite(exposure), is.finite(lag), is.finite(rr))

  meta_df <- tibble(
    variable = temp_var,
    var_label = add_var_label(temp_var),
    ref_value = ref_temp,
    pred_min = pred_min,
    pred_max = pred_max,
    df_var = df_var,
    df_lag = df_lag,
    max_lag = max_lag,
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata),
    aic = tryCatch(AIC(fit), error = function(e) NA_real_)
  )

  list(
    ok = TRUE,
    overall = overall_df,
    lag_specific = lag_specific_df,
    contour = contour_df,
    meta = meta_df,
    model = fit
  )
}

run_pollutant_linear_dlnm_analysis <- function(df,
                                               pollutant_var,
                                               strata_var = STRATA_VAR,
                                               cluster_var = NULL,
                                               outcome_var = OUTCOME_VAR,
                                               max_lag = POLLUTANT_LIN_DLNM_MAX_LAG,
                                               df_lag = POLLUTANT_LIN_DLNM_DF_LAG,
                                               report_lags = POLLUTANT_LIN_DLNM_LAGS_TO_REPORT) {

  lag_cols <- paste0(pollutant_var, "_lag", 0:max_lag)
  if (!all(lag_cols %in% names(df))) {
    return(list(ok = FALSE, error = paste("missing lag columns for", pollutant_var)))
  }

  flu_adjust_cols <- make_flu_adjust_colnames(c("阳性率"), FLU_ADJ_SUFFIX)
  flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

  need_cols <- c(
    strata_var, outcome_var, lag_cols, "holiday", "Tavg_avg_lag0_2", "RHUM_avg_lag0_2",
    flu_adjust_cols,
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL,
    if (!is.null(cluster_var)) cluster_var else NULL
  )
  need_cols <- unique(intersect(need_cols, names(df)))

  d <- df %>%
    select(all_of(need_cols)) %>%
    mutate(
      outcome = as.numeric(.data[[outcome_var]]),
      strata  = as.character(.data[[strata_var]]),
      cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_,
      holiday2 = as.numeric(.data[["holiday"]]),
      temp_02  = suppressWarnings(as.numeric(.data[["Tavg_avg_lag0_2"]])),
      rhum_02  = suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])),
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_,
      flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_
    ) %>%
    mutate(across(all_of(lag_cols), ~ suppressWarnings(as.numeric(.x)))) %>%
    filter(
      !is.na(outcome),
      !is.na(strata),
      !is.na(holiday2),
      safe_is_finite(temp_02),
      safe_is_finite(rhum_02)
    )

  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
    d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
  }
  if (RUN_COVID_WAVE_ADJUST) {
    d <- d %>% filter(!is.na(covid_wave2))
  }

  xmat <- as.matrix(d[, lag_cols, drop = FALSE])
  storage.mode(xmat) <- "numeric"

  keep <- apply(xmat, 1, function(z) any(is.finite(z)))
  d <- d[keep, , drop = FALSE]
  xmat <- xmat[keep, , drop = FALSE]

  if (nrow(d) < 50) {
    return(list(ok = FALSE, error = paste("too few rows for", pollutant_var)))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(has_case = any(outcome == 1), has_ctrl = any(outcome == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(list(ok = FALSE, error = paste("too few valid strata for", pollutant_var)))
  }

  idx <- d$strata %in% valid_strata
  d <- d[idx, , drop = FALSE]
  xmat <- xmat[idx, , drop = FALSE]

  x0 <- xmat[, 1]
  x0_fin <- x0[safe_is_finite(x0)]
  if (length(x0_fin) < 30) {
    return(list(ok = FALSE, error = paste("too few finite lag0 values for", pollutant_var)))
  }

  ref_val <- median(x0_fin, na.rm = TRUE)
  iqr_val <- get_analysis_iqr(pollutant_var)

  scale_val <- get_scale_value(d, pollutant_var)
  scale_lab <- get_scale_label(d, pollutant_var)


  cb <- tryCatch(
    crossbasis(
      x = xmat,
      lag = max_lag,
      argvar = list(fun = "lin"),
      arglag = list(fun = "ns", df = df_lag)
    ),
    error = function(e) NULL
  )

  if (is.null(cb)) {
    return(list(ok = FALSE, error = paste("crossbasis failed for", pollutant_var)))
  }

  rhs_terms <- c(
    "cb",
    "ns(temp_02, df = 6)",
    "ns(rhum_02, df = 3)",
    "holiday2"
  )
  if (RUN_COVID_WAVE_ADJUST) rhs_terms <- c(rhs_terms, "covid_wave2")
  if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) rhs_terms <- c(rhs_terms, "flu_posrate_02")

  fml <- as.formula(
    paste0("outcome ~ ", paste(rhs_terms, collapse = " + "), " + strata(strata)")
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(ok = FALSE, error = paste("clogit failed for", pollutant_var)))
  }

  pred_scaled <- tryCatch(
    crosspred(
      basis = cb,
      model = fit,
      at = scale_val,
      cen = 0,
      bylag = 1,
      cumul = TRUE
    ),
    error = function(e) NULL
  )
  if (is.null(pred_scaled)) {
    return(list(ok = FALSE, error = paste("crosspred failed (scaled) for", pollutant_var)))
  }

  pred_iqr <- NULL
  if (is.finite(iqr_val) && iqr_val > 0) {
    pred_iqr <- tryCatch(
      crosspred(
        basis = cb,
        model = fit,
        at = iqr_val,
        cen = 0,
        bylag = 1,
        cumul = TRUE
      ),
      error = function(e) NULL
    )
  }

  report_lags <- report_lags[report_lags <= max_lag]
  adjust_label_use <- build_env_adjust_label(pollutant_var, include_flu = TRUE, include_covid = TRUE)

  lag_scaled_logrr <- as.numeric(pred_scaled$matfit[1, ])
  lag_scaled_se    <- as.numeric(pred_scaled$matse[1, ])

  lag_scaled_df <- tibble(
    variable = pollutant_var,
    var_label = add_var_label(pollutant_var),
    group = add_group(pollutant_var),
    effect_type = "per_scaled_unit",
    scale_value = scale_val,
    scale_label = scale_lab,
    iqr_value = NA_real_,
    adjust_vars = adjust_label_use,
    lag = 0:max_lag,
    logrr = lag_scaled_logrr,
    se = lag_scaled_se,
    or = as.numeric(pred_scaled$matRRfit[1, ]),
    ci_low = as.numeric(pred_scaled$matRRlow[1, ]),
    ci_high = as.numeric(pred_scaled$matRRhigh[1, ]),
    p_value = calc_p_from_logrr_se(lag_scaled_logrr, lag_scaled_se),
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata)
  )

  lag_iqr_df <- tibble()
  if (!is.null(pred_iqr)) {
    lag_iqr_logrr <- as.numeric(pred_iqr$matfit[1, ])
    lag_iqr_se    <- as.numeric(pred_iqr$matse[1, ])

    lag_iqr_df <- tibble(
      variable = pollutant_var,
      var_label = add_var_label(pollutant_var),
      group = add_group(pollutant_var),
      effect_type = "per_iqr",
      scale_value = NA_real_,
      scale_label = "per IQR (global)",
      iqr_value = iqr_val,
      adjust_vars = adjust_label_use,
      lag = 0:max_lag,
      logrr = lag_iqr_logrr,
      se = lag_iqr_se,
      or = as.numeric(pred_iqr$matRRfit[1, ]),
      ci_low = as.numeric(pred_iqr$matRRlow[1, ]),
      ci_high = as.numeric(pred_iqr$matRRhigh[1, ]),
      p_value = calc_p_from_logrr_se(lag_iqr_logrr, lag_iqr_se),
      n_cases = sum(d$outcome == 1),
      n_controls = sum(d$outcome == 0),
      n_strata = length(valid_strata)
    )
  }

  cum_scaled_logrr <- as.numeric(pred_scaled$allfit)
  cum_scaled_se    <- as.numeric(pred_scaled$allse)

  cum_scaled_df <- tibble(
    variable = pollutant_var,
    var_label = add_var_label(pollutant_var),
    group = add_group(pollutant_var),
    effect_type = "per_scaled_unit",
    scale_value = scale_val,
    scale_label = scale_lab,
    iqr_value = NA_real_,
    adjust_vars = adjust_label_use,
    window = paste0("0-", max_lag),
    logrr = cum_scaled_logrr,
    se = cum_scaled_se,
    cum_or = as.numeric(pred_scaled$allRRfit),
    cum_ci_low = as.numeric(pred_scaled$allRRlow),
    cum_ci_high = as.numeric(pred_scaled$allRRhigh),
    p_value = calc_p_from_logrr_se(cum_scaled_logrr, cum_scaled_se),
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata)
  )

  cum_iqr_df <- tibble()
  if (!is.null(pred_iqr)) {
    cum_iqr_logrr <- as.numeric(pred_iqr$allfit)
    cum_iqr_se    <- as.numeric(pred_iqr$allse)

    cum_iqr_df <- tibble(
      variable = pollutant_var,
      var_label = add_var_label(pollutant_var),
      group = add_group(pollutant_var),
      effect_type = "per_iqr",
      scale_value = NA_real_,
      scale_label = "per IQR (global)",
      iqr_value = iqr_val,
      adjust_vars = adjust_label_use,
      window = paste0("0-", max_lag),
      logrr = cum_iqr_logrr,
      se = cum_iqr_se,
      cum_or = as.numeric(pred_iqr$allRRfit),
      cum_ci_low = as.numeric(pred_iqr$allRRlow),
      cum_ci_high = as.numeric(pred_iqr$allRRhigh),
      p_value = calc_p_from_logrr_se(cum_iqr_logrr, cum_iqr_se),
      n_cases = sum(d$outcome == 1),
      n_controls = sum(d$outcome == 0),
      n_strata = length(valid_strata)
    )
  }

  report_scaled_df <- lag_scaled_df %>%
    filter(lag %in% report_lags)

  report_iqr_df <- tibble()
  if (nrow(lag_iqr_df) > 0) {
    report_iqr_df <- lag_iqr_df %>%
      filter(lag %in% report_lags)
  }

  meta_df <- tibble(
    variable = pollutant_var,
    var_label = add_var_label(pollutant_var),
    ref_value = ref_val,
    scale_value = scale_val,
    scale_label = scale_lab,
    iqr_value = iqr_val,
    df_lag = df_lag,
    max_lag = max_lag,
    argvar_used = "lin",
    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata),
    aic = tryCatch(AIC(fit), error = function(e) NA_real_),
    adjust_vars = adjust_label_use
  )

  list(
    ok = TRUE,
    lag_all = bind_rows(lag_scaled_df, lag_iqr_df),
    lag_report = bind_rows(report_scaled_df, report_iqr_df),
    cumulative = bind_rows(cum_scaled_df, cum_iqr_df),
    meta = meta_df,
    pred_scaled = pred_scaled,
    pred_iqr = pred_iqr,
    model = fit
  )
}

env_color_map <- c(
  "Mean temperature (°C)" = "#5F4596",
  "Minimum temperature (°C)" = "#0066CC",
  "Maximum temperature (°C)" = "#CC66B3",
  "PM2.5 (µg/m³)" = "#2C7FB8",
  "PM10 (µg/m³)" = "#41B6C4",
  "NO₂ (µg/m³)" = "#1D91C0",
  "SO₂ (µg/m³)" = "#225EA8",
  "CO (mg/m³)" = "#253494",
  "O₃ (µg/m³)" = "#7FCDBB"
)







safe_lrt_p <- function(fit_main, fit_int) {
  aa <- tryCatch(
    anova(fit_main, fit_int, test = "LRT"),
    error = function(e) e
  )

  if (inherits(aa, "error") || is.null(aa)) {
    return(list(
      p_value = NA_real_,
      ok = FALSE,
      reason = paste0("anova failed: ", if (inherits(aa, "error")) aa$message else "NULL result")
    ))
  }

  aa_df <- tryCatch(as.data.frame(aa), error = function(e) NULL)
  if (is.null(aa_df) || nrow(aa_df) < 2) {
    return(list(
      p_value = NA_real_,
      ok = FALSE,
      reason = "anova table invalid or <2 rows"
    ))
  }

  cn <- colnames(aa_df)

  candidate_cols <- c(
    "P(>|Chi|)", "Pr(>|Chi|)", "Pr(>Chi)", "P(>Chi)",
    "P(>|Chisq|)", "Pr(>|Chisq|)", "Pr(>Chisq)", "P(>Chisq)"
  )
  hit <- intersect(candidate_cols, cn)

  if (length(hit) == 0) {
    hit <- grep("(^P|^Pr|Chi|Chisq)", cn, value = TRUE)
  }

  if (length(hit) == 0) {
    return(list(
      p_value = NA_real_,
      ok = FALSE,
      reason = paste0("no p-value column found; columns=", paste(cn, collapse = ", "))
    ))
  }

  pv <- suppressWarnings(as.numeric(aa_df[2, hit[1]]))
  if (!is.finite(pv)) {
    return(list(
      p_value = NA_real_,
      ok = FALSE,
      reason = paste0("p-value not finite from column ", hit[1])
    ))
  }

  list(
    p_value = pv,
    ok = TRUE,
    reason = "ok"
  )
}

scalar1 <- function(x, default = NA) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(default)
  x[[1]]
}

run_lag2_group_interaction_test <- function(df,
                                            base_var,
                                            group_var,
                                            model_family = "flu_primary",
                                            strata_var = STRATA_VAR,
                                            cluster_var = NULL,
                                            outcome_var = OUTCOME_VAR) {

  df <- normalize_calendar_covariates(df)

  fail_out <- function(reason_text,
                       n_levels = NA_integer_,
                       n_cases = NA_integer_,
                       n_controls = NA_integer_,
                       n_strata = NA_integer_,
                       adjust_vars = NA_character_) {
    list(
      ok = FALSE,
      res = tibble(
        variable = as.character(scalar1(base_var, NA_character_)),
        var_label = as.character(scalar1(add_var_label(base_var), NA_character_)),
        group = as.character(scalar1(add_group(base_var), NA_character_)),
        group_var = as.character(scalar1(group_var, NA_character_)),
        group_var_label = as.character(scalar1(add_group_var_label(group_var), NA_character_)),
        model_family = as.character(scalar1(model_family, NA_character_)),
        lag = 2,
        p_interaction = NA_real_,
        n_levels = as.integer(n_levels),
        n_cases = as.integer(n_cases),
        n_controls = as.integer(n_controls),
        n_strata = as.integer(n_strata),
        adjust_vars = as.character(adjust_vars),
        reason = as.character(reason_text)
      )
    )
  }

  if (is.null(model_family) || length(model_family) == 0 || all(is.na(model_family))) {
    return(fail_out("model_family is NULL or length 0"))
  }

  model_family <- as.character(model_family)[1]

  if (!(model_family %in% c("flu_primary", "env_primary"))) {
    return(fail_out(paste0("invalid model_family: ", model_family)))
  }

  xname <- paste0(base_var, "_lag2")

  if (!xname %in% names(df)) {
    return(fail_out("missing lag2 exposure column"))
  }

  if (!group_var %in% names(df)) {
    return(fail_out("missing group variable"))
  }

  tmp_group <- df[[group_var]]
  if (all(is.na(tmp_group))) {
    return(fail_out("group variable all missing"))
  }

  fit_main <- NULL
  fit_int  <- NULL
  d <- NULL
  adjust_label_use <- NA_character_

  if (identical(model_family, "flu_primary")) {

    must_have <- c(outcome_var, strata_var, xname, group_var, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday")
    if (RUN_COVID_WAVE_ADJUST) must_have <- c(must_have, COVID_WAVE_VAR)

    missing_need <- setdiff(unique(must_have), names(df))
    if (length(missing_need) > 0) {
      return(fail_out(
        paste0("missing required columns: ", paste(missing_need, collapse = ", "))
      ))
    }

    need <- unique(must_have)

    d <- df %>%
      select(all_of(need)) %>%
      transmute(
        outcome = as.numeric(.data[[outcome_var]]),
        strata  = as.character(.data[[strata_var]]),
        exposure = suppressWarnings(as.numeric(.data[[xname]])),
        group_level = as.character(.data[[group_var]]),
        temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
        rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
        holiday2 = as.numeric(.data[["holiday"]]),
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST) suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]])) else NA_real_
      ) %>%
      filter(
        !is.na(outcome),
        !is.na(strata),
        !is.na(group_level),
        safe_is_finite(exposure),
        safe_is_finite(temp_02),
        safe_is_finite(rhum_02),
        !is.na(holiday2)
      )

    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    adjust_label_use <- build_flu_adjust_label(include_covid = TRUE, include_holiday = TRUE)
  }

  if (identical(model_family, "env_primary")) {

    flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
    flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

    adj_strategy <- get_env_adjust_strategy(base_var)
    use_temp_spline <- adj_strategy$use_temp
    use_rhum_spline <- adj_strategy$use_rhum

    must_have <- c(outcome_var, strata_var, xname, group_var, "holiday")
    if (use_temp_spline) must_have <- c(must_have, "Tavg_avg_lag0_2")
    if (use_rhum_spline) must_have <- c(must_have, "RHUM_avg_lag0_2")
    if (RUN_COVID_WAVE_ADJUST) must_have <- c(must_have, COVID_WAVE_VAR)

    missing_need <- setdiff(unique(must_have), names(df))
    if (length(missing_need) > 0) {
      return(fail_out(
        paste0("missing required columns: ", paste(missing_need, collapse = ", "))
      ))
    }

    need <- unique(c(must_have, flu_adjust_cols))

    d <- df %>%
      select(all_of(need)) %>%
      transmute(
        outcome = as.numeric(.data[[outcome_var]]),
        strata  = as.character(.data[[strata_var]]),
        exposure = suppressWarnings(as.numeric(.data[[xname]])),
        group_level = as.character(.data[[group_var]]),
        temp_02 = if (use_temp_spline) suppressWarnings(as.numeric(.data[["Tavg_avg_lag0_2"]])) else NA_real_,
        rhum_02 = if (use_rhum_spline) suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])) else NA_real_,
        holiday2 = as.numeric(.data[["holiday"]]),
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST) suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]])) else NA_real_,
        flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_
      ) %>%
      filter(
        !is.na(outcome),
        !is.na(strata),
        !is.na(group_level),
        safe_is_finite(exposure),
        !is.na(holiday2)
      )

    if (use_temp_spline) d <- d %>% filter(safe_is_finite(temp_02))
    if (use_rhum_spline) d <- d %>% filter(safe_is_finite(rhum_02))
    if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
      d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
    }
    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    adjust_label_use <- build_env_adjust_label(base_var, include_flu = TRUE, include_covid = TRUE)
  }

  if (is.null(d) || nrow(d) == 0) {
    return(fail_out("no rows after filtering", adjust_vars = adjust_label_use))
  }

  d <- d %>%
    mutate(
      group_level = trimws(group_level),
      group_level = na_if(group_level, ""),
      group_level = factor(group_level)
    ) %>%
    filter(!is.na(group_level))

  if (nrow(d) == 0) {
    return(fail_out("no rows after group cleaning", adjust_vars = adjust_label_use))
  }

  if (nlevels(d$group_level) < 2) {
    return(fail_out(
      "group variable has <2 levels after filtering",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(
      has_case = any(outcome == 1),
      has_ctrl = any(outcome == 0),
      .groups = "drop"
    ) %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(fail_out(
      "too few valid strata",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = length(valid_strata),
      adjust_vars = adjust_label_use
    ))
  }

  d <- d %>% filter(strata %in% valid_strata)

  level_tab <- d %>%
    group_by(group_level) %>%
    summarise(
      n_cases = sum(outcome == 1, na.rm = TRUE),
      n_controls = sum(outcome == 0, na.rm = TRUE),
      .groups = "drop"
    )

  bad_levels <- level_tab %>%
    filter(n_cases == 0 | n_controls == 0) %>%
    pull(group_level) %>%
    as.character()

  if (length(bad_levels) > 0) {
    d <- d %>% filter(!(as.character(group_level) %in% bad_levels))
    d$group_level <- droplevels(d$group_level)
  }

  if (nlevels(d$group_level) < 2) {
    return(fail_out(
      paste0(
        "group variable has <2 analysable levels after removing empty-case/control levels: ",
        paste(bad_levels, collapse = ", ")
      ),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  if (identical(model_family, "flu_primary")) {
    rhs_main <- c(
      "exposure",
      "group_level",
      paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
      paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
      "holiday2"
    )
    if (RUN_COVID_WAVE_ADJUST) rhs_main <- c(rhs_main, "covid_wave2")

    rhs_int <- c(
      "exposure * group_level",
      paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
      paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
      "holiday2"
    )
    if (RUN_COVID_WAVE_ADJUST) rhs_int <- c(rhs_int, "covid_wave2")
  }

  if (identical(model_family, "env_primary")) {
    flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
    flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

    adj_strategy <- get_env_adjust_strategy(base_var)
    use_temp_spline <- adj_strategy$use_temp
    use_rhum_spline <- adj_strategy$use_rhum

    rhs_main <- c(
      "exposure",
      "group_level",
      if (use_temp_spline) "ns(temp_02, df = 6)" else NULL,
      if (use_rhum_spline) "ns(rhum_02, df = 3)" else NULL,
      "holiday2",
      if (RUN_COVID_WAVE_ADJUST) "covid_wave2" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "flu_posrate_02" else NULL
    )

    rhs_int <- c(
      "exposure * group_level",
      if (use_temp_spline) "ns(temp_02, df = 6)" else NULL,
      if (use_rhum_spline) "ns(rhum_02, df = 3)" else NULL,
      "holiday2",
      if (RUN_COVID_WAVE_ADJUST) "covid_wave2" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "flu_posrate_02" else NULL
    )
  }

  fml_main <- as.formula(
    paste0("outcome ~ ", paste(rhs_main, collapse = " + "), " + strata(strata)")
  )
  fml_int <- as.formula(
    paste0("outcome ~ ", paste(rhs_int, collapse = " + "), " + strata(strata)")
  )

  fit_main <- tryCatch(
    clogit(fml_main, data = d),
    error = function(e) e
  )
  if (inherits(fit_main, "error") || is.null(fit_main)) {
    return(fail_out(
      paste0("main model fitting failed: ", if (inherits(fit_main, "error")) fit_main$message else "NULL"),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  fit_int <- tryCatch(
    clogit(fml_int, data = d),
    error = function(e) e
  )
  if (inherits(fit_int, "error") || is.null(fit_int)) {
    return(fail_out(
      paste0("interaction model fitting failed: ", if (inherits(fit_int, "error")) fit_int$message else "NULL"),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  lrt_res <- safe_lrt_p(fit_main, fit_int)

  if (!isTRUE(lrt_res$ok)) {
    return(fail_out(
      paste0("LRT extraction failed: ", lrt_res$reason),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  out <- tibble(
    variable = as.character(scalar1(base_var, NA_character_)),
    var_label = as.character(scalar1(add_var_label(base_var), NA_character_)),
    group = as.character(scalar1(add_group(base_var), NA_character_)),
    group_var = as.character(scalar1(group_var, NA_character_)),
    group_var_label = as.character(scalar1(add_group_var_label(group_var), NA_character_)),
    model_family = as.character(scalar1(model_family, NA_character_)),
    lag = 2,
    p_interaction = as.numeric(scalar1(lrt_res$p_value, NA_real_)),
    n_levels = as.integer(scalar1(nlevels(d$group_level), NA_integer_)),
    n_cases = as.integer(scalar1(sum(d$outcome == 1, na.rm = TRUE), NA_integer_)),
    n_controls = as.integer(scalar1(sum(d$outcome == 0, na.rm = TRUE), NA_integer_)),
    n_strata = as.integer(scalar1(dplyr::n_distinct(d$strata), NA_integer_)),
    adjust_vars = as.character(scalar1(adjust_label_use, NA_character_))
  )

  list(ok = TRUE, res = out)
}

run_lag2_group_interaction_or_detail <- function(df,
                                                 base_var,
                                                 group_var,
                                                 model_family = "flu_primary",
                                                 strata_var = STRATA_VAR,
                                                 cluster_var = NULL,
                                                 outcome_var = OUTCOME_VAR) {

  df <- normalize_calendar_covariates(df)

  fail_out <- function(reason_text,
                       n_levels = NA_integer_,
                       n_cases = NA_integer_,
                       n_controls = NA_integer_,
                       n_strata = NA_integer_,
                       adjust_vars = NA_character_,
                       p_interaction = NA_real_) {
    list(
      ok = FALSE,
      detail = tibble(
        variable = as.character(base_var),
        var_label = as.character(add_var_label(base_var)),
        group = as.character(add_group(base_var)),
        group_var = as.character(group_var),
        group_var_label = as.character(add_group_var_label(group_var)),
        model_family = as.character(model_family),
        lag = 2,
        group_level = NA_character_,
        reference_level = NA_character_,
        beta = NA_real_,
        se = NA_real_,
        or = NA_real_,
        ci_low = NA_real_,
        ci_high = NA_real_,
        p_value = NA_real_,
        p_interaction = as.numeric(p_interaction),
        n_levels = as.integer(n_levels),
        n_cases = as.integer(n_cases),
        n_controls = as.integer(n_controls),
        n_strata = as.integer(n_strata),
        adjust_vars = as.character(adjust_vars),
        reason = as.character(reason_text)
      )
    )
  }

  if (!(model_family %in% c("flu_primary", "env_primary"))) {
    return(fail_out(paste0("invalid model_family: ", model_family)))
  }

  xname <- paste0(base_var, "_lag2")
  if (!xname %in% names(df)) {
    return(fail_out("missing lag2 exposure column"))
  }
  if (!group_var %in% names(df)) {
    return(fail_out("missing group variable"))
  }
  if (all(is.na(df[[group_var]]))) {
    return(fail_out("group variable all missing"))
  }

  d <- NULL
  adjust_label_use <- NA_character_

  if (identical(model_family, "flu_primary")) {
    must_have <- c(outcome_var, strata_var, xname, group_var, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday")
    if (RUN_COVID_WAVE_ADJUST) must_have <- c(must_have, COVID_WAVE_VAR)

    missing_need <- setdiff(unique(must_have), names(df))
    if (length(missing_need) > 0) {
      return(fail_out(
        paste0("missing required columns: ", paste(missing_need, collapse = ", "))
      ))
    }

    d <- df %>%
      select(all_of(unique(must_have))) %>%
      transmute(
        outcome = as.numeric(.data[[outcome_var]]),
        strata  = as.character(.data[[strata_var]]),
        exposure = suppressWarnings(as.numeric(.data[[xname]])),
        group_level = as.character(.data[[group_var]]),
        temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
        rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
        holiday2 = as.numeric(.data[["holiday"]]),
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST) suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]])) else NA_real_
      ) %>%
      filter(
        !is.na(outcome),
        !is.na(strata),
        !is.na(group_level),
        safe_is_finite(exposure),
        safe_is_finite(temp_02),
        safe_is_finite(rhum_02),
        !is.na(holiday2)
      )

    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    adjust_label_use <- build_flu_adjust_label(include_covid = TRUE, include_holiday = TRUE)
  }

  if (identical(model_family, "env_primary")) {
    flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
    flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

    adj_strategy <- get_env_adjust_strategy(base_var)
    use_temp_spline <- adj_strategy$use_temp
    use_rhum_spline <- adj_strategy$use_rhum

    must_have <- c(outcome_var, strata_var, xname, group_var, "holiday")
    if (use_temp_spline) must_have <- c(must_have, "Tavg_avg_lag0_2")
    if (use_rhum_spline) must_have <- c(must_have, "RHUM_avg_lag0_2")
    if (RUN_COVID_WAVE_ADJUST) must_have <- c(must_have, COVID_WAVE_VAR)

    missing_need <- setdiff(unique(must_have), names(df))
    if (length(missing_need) > 0) {
      return(fail_out(
        paste0("missing required columns: ", paste(missing_need, collapse = ", "))
      ))
    }

    need <- unique(c(must_have, flu_adjust_cols))

    d <- df %>%
      select(all_of(need)) %>%
      transmute(
        outcome = as.numeric(.data[[outcome_var]]),
        strata  = as.character(.data[[strata_var]]),
        exposure = suppressWarnings(as.numeric(.data[[xname]])),
        group_level = as.character(.data[[group_var]]),
        temp_02 = if (use_temp_spline) suppressWarnings(as.numeric(.data[["Tavg_avg_lag0_2"]])) else NA_real_,
        rhum_02 = if (use_rhum_spline) suppressWarnings(as.numeric(.data[["RHUM_avg_lag0_2"]])) else NA_real_,
        holiday2 = as.numeric(.data[["holiday"]]),
        covid_wave2 = if (RUN_COVID_WAVE_ADJUST) suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]])) else NA_real_,
        flu_posrate_02 = if ("阳性率_avg_lag0_2" %in% names(.)) suppressWarnings(as.numeric(.data[["阳性率_avg_lag0_2"]])) else NA_real_
      ) %>%
      filter(
        !is.na(outcome),
        !is.na(strata),
        !is.na(group_level),
        safe_is_finite(exposure),
        !is.na(holiday2)
      )

    if (use_temp_spline) d <- d %>% filter(safe_is_finite(temp_02))
    if (use_rhum_spline) d <- d %>% filter(safe_is_finite(rhum_02))
    if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) {
      d <- d %>% filter(!is.na(flu_posrate_02), safe_is_finite(flu_posrate_02))
    }
    if (RUN_COVID_WAVE_ADJUST) {
      d <- d %>% filter(!is.na(covid_wave2))
    }

    adjust_label_use <- build_env_adjust_label(base_var, include_flu = TRUE, include_covid = TRUE)
  }

  if (is.null(d) || nrow(d) == 0) {
    return(fail_out("no rows after filtering", adjust_vars = adjust_label_use))
  }

  d <- d %>%
    mutate(
      group_level = trimws(group_level),
      group_level = na_if(group_level, ""),
      group_level = factor(group_level)
    ) %>%
    filter(!is.na(group_level))

  if (nrow(d) == 0) {
    return(fail_out("no rows after group cleaning", adjust_vars = adjust_label_use))
  }

  if (nlevels(d$group_level) < 2) {
    return(fail_out(
      "group variable has <2 levels after filtering",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  valid_strata <- d %>%
    group_by(strata) %>%
    summarise(
      has_case = any(outcome == 1),
      has_ctrl = any(outcome == 0),
      .groups = "drop"
    ) %>%
    filter(has_case & has_ctrl) %>%
    pull(strata)

  if (length(valid_strata) < 3) {
    return(fail_out(
      "too few valid strata",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = length(valid_strata),
      adjust_vars = adjust_label_use
    ))
  }

  d <- d %>% filter(strata %in% valid_strata)

  level_tab <- d %>%
    group_by(group_level) %>%
    summarise(
      n_cases = sum(outcome == 1, na.rm = TRUE),
      n_controls = sum(outcome == 0, na.rm = TRUE),
      .groups = "drop"
    )

  bad_levels <- level_tab %>%
    filter(n_cases == 0 | n_controls == 0) %>%
    pull(group_level) %>%
    as.character()

  if (length(bad_levels) > 0) {
    d <- d %>% filter(!(as.character(group_level) %in% bad_levels))
    d$group_level <- droplevels(d$group_level)
  }

  if (nlevels(d$group_level) < 2) {
    return(fail_out(
      paste0(
        "group variable has <2 analysable levels after removing empty-case/control levels: ",
        paste(bad_levels, collapse = ", ")
      ),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  reference_level <- levels(d$group_level)[1]

  if (identical(model_family, "flu_primary")) {
    rhs_main <- c(
      "exposure",
      "group_level",
      paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
      paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
      "holiday2"
    )
    if (RUN_COVID_WAVE_ADJUST) rhs_main <- c(rhs_main, "covid_wave2")

    rhs_int <- c(
      "exposure * group_level",
      paste0("ns(temp_02, df = ", FLU_TEMP_DF, ")"),
      paste0("ns(rhum_02, df = ", FLU_RHUM_DF, ")"),
      "holiday2"
    )
    if (RUN_COVID_WAVE_ADJUST) rhs_int <- c(rhs_int, "covid_wave2")
  }

  if (identical(model_family, "env_primary")) {
    flu_adjust_cols <- make_flu_adjust_colnames(FLU_ADJ_FOR_ENV, FLU_ADJ_SUFFIX)
    flu_adjust_cols <- flu_adjust_cols[flu_adjust_cols %in% names(df)]

    adj_strategy <- get_env_adjust_strategy(base_var)
    use_temp_spline <- adj_strategy$use_temp
    use_rhum_spline <- adj_strategy$use_rhum

    rhs_main <- c(
      "exposure",
      "group_level",
      if (use_temp_spline) "ns(temp_02, df = 6)" else NULL,
      if (use_rhum_spline) "ns(rhum_02, df = 3)" else NULL,
      "holiday2",
      if (RUN_COVID_WAVE_ADJUST) "covid_wave2" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "flu_posrate_02" else NULL
    )

    rhs_int <- c(
      "exposure * group_level",
      if (use_temp_spline) "ns(temp_02, df = 6)" else NULL,
      if (use_rhum_spline) "ns(rhum_02, df = 3)" else NULL,
      "holiday2",
      if (RUN_COVID_WAVE_ADJUST) "covid_wave2" else NULL,
      if ("阳性率_avg_lag0_2" %in% flu_adjust_cols) "flu_posrate_02" else NULL
    )
  }

  fml_main <- as.formula(
    paste0("outcome ~ ", paste(rhs_main, collapse = " + "), " + strata(strata)")
  )
  fml_int <- as.formula(
    paste0("outcome ~ ", paste(rhs_int, collapse = " + "), " + strata(strata)")
  )

  fit_main <- tryCatch(clogit(fml_main, data = d), error = function(e) e)
  if (inherits(fit_main, "error") || is.null(fit_main)) {
    return(fail_out(
      paste0("main model fitting failed: ", if (inherits(fit_main, "error")) fit_main$message else "NULL"),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  fit_int <- tryCatch(clogit(fml_int, data = d), error = function(e) e)
  if (inherits(fit_int, "error") || is.null(fit_int)) {
    return(fail_out(
      paste0("interaction model fitting failed: ", if (inherits(fit_int, "error")) fit_int$message else "NULL"),
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use
    ))
  }

  lrt_res <- safe_lrt_p(fit_main, fit_int)
  p_int <- if (isTRUE(lrt_res$ok)) lrt_res$p_value else NA_real_

  beta_hat <- tryCatch(coef(fit_int), error = function(e) NULL)
  if (is.null(beta_hat)) {
    return(fail_out(
      "cannot extract coefficients from interaction model",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use,
      p_interaction = p_int
    ))
  }

  vv <- tryCatch(vcov(fit_int), error = function(e) NULL)
  if (is.null(vv)) {
    return(fail_out(
      "cannot extract vcov from interaction model",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use,
      p_interaction = p_int
    ))
  }

  coef_names <- names(beta_hat)
  exp_main_name <- "exposure"

  if (!(exp_main_name %in% coef_names)) {
    return(fail_out(
      "exposure coefficient not found in interaction model",
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use,
      p_interaction = p_int
    ))
  }

  levs <- levels(d$group_level)

  detail_list <- lapply(levs, function(gl) {
    if (identical(gl, reference_level)) {
      beta_use <- as.numeric(beta_hat[exp_main_name])
      var_use  <- as.numeric(vv[exp_main_name, exp_main_name])
    } else {

      cand1 <- paste0("exposure:group_level", gl)
      cand2 <- paste0("group_level", gl, ":exposure")
      int_name <- c(cand1, cand2)[c(cand1, cand2) %in% coef_names][1]

      if (is.na(int_name) || length(int_name) == 0) {
        return(tibble(
          variable = base_var,
          var_label = add_var_label(base_var),
          group = add_group(base_var),
          group_var = group_var,
          group_var_label = add_group_var_label(group_var),
          model_family = model_family,
          lag = 2,
          group_level = as.character(gl),
          reference_level = as.character(reference_level),
          beta = NA_real_,
          se = NA_real_,
          or = NA_real_,
          ci_low = NA_real_,
          ci_high = NA_real_,
          p_value = NA_real_,
          p_interaction = p_int,
          n_levels = nlevels(d$group_level),
          n_cases = sum(d$outcome == 1, na.rm = TRUE),
          n_controls = sum(d$outcome == 0, na.rm = TRUE),
          n_strata = dplyr::n_distinct(d$strata),
          adjust_vars = adjust_label_use,
          reason = "interaction coefficient not found for this level"
        ))
      }

      beta_use <- as.numeric(beta_hat[exp_main_name] + beta_hat[int_name])
      var_use  <- as.numeric(
        vv[exp_main_name, exp_main_name] +
          vv[int_name, int_name] +
          2 * vv[exp_main_name, int_name]
      )
    }

    se_use <- ifelse(is.finite(var_use) && var_use >= 0, sqrt(var_use), NA_real_)
    p_use <- ifelse(is.finite(beta_use) && is.finite(se_use) && se_use > 0,
                    2 * (1 - pnorm(abs(beta_use / se_use))),
                    NA_real_)

    tibble(
      variable = base_var,
      var_label = add_var_label(base_var),
      group = add_group(base_var),
      group_var = group_var,
      group_var_label = add_group_var_label(group_var),
      model_family = model_family,
      lag = 2,
      group_level = as.character(gl),
      reference_level = as.character(reference_level),
      beta = beta_use,
      se = se_use,
      or = ifelse(is.finite(beta_use), exp(beta_use), NA_real_),
      ci_low = ifelse(is.finite(beta_use) && is.finite(se_use), exp(beta_use - 1.96 * se_use), NA_real_),
      ci_high = ifelse(is.finite(beta_use) && is.finite(se_use), exp(beta_use + 1.96 * se_use), NA_real_),
      p_value = p_use,
      p_interaction = p_int,
      n_levels = nlevels(d$group_level),
      n_cases = sum(d$outcome == 1, na.rm = TRUE),
      n_controls = sum(d$outcome == 0, na.rm = TRUE),
      n_strata = dplyr::n_distinct(d$strata),
      adjust_vars = adjust_label_use,
      reason = NA_character_
    )
  })

  detail_df <- bind_rows(detail_list)

  list(ok = TRUE, detail = detail_df)
}

run_dual_strategy_analysis <- function(df_sub, subset_tag,
                                       output_dir_base = output_dir) {
  cat("\n=============================\n")
  cat("开始分析子集: ", subset_tag, "\n")
  cat("=============================\n")

  current_iqr_before <- CURRENT_IQR_MAP
  CURRENT_IQR_MAP <<- c()
  if (subset_tag %in% c("heating", "non_heating")) {
    lag0_subset <- names(df_sub)[grepl("_lag0$", names(df_sub))]
    base_subset <- unique(gsub("_lag0$", "", lag0_subset))
    CURRENT_IQR_MAP <<- build_global_iqr_map(df_sub, base_subset, max_lag = MAX_LAG)
  }
  on.exit(CURRENT_IQR_MAP <<- current_iqr_before, add = TRUE)

  sub_output_dir <- file.path(output_dir_base, subset_tag)
  dir.create(sub_output_dir, showWarnings = FALSE, recursive = TRUE)

  df_sub <- normalize_calendar_covariates(df_sub)
  cluster_var <- get_cluster_var(df_sub, CLUSTER_CANDIDATES)

  if ("control_date_source" %in% names(df_sub)) {
    cat("control_date_source 分布:\n")
    print(table(df_sub$control_date_source, useNA = "ifany"))
  }

  if ("holiday" %in% names(df_sub)) {
    cat("holiday 分布:\n")
    print(table(df_sub$holiday, useNA = "ifany"))
  }

  if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(df_sub)) {
    cat("covid_major_wave 分布:\n")
    print(table(df_sub[[COVID_WAVE_VAR]], useNA = "ifany"))
  }

  df_sub <- df_sub %>%
    mutate(
      is_case = as.numeric(.data[[OUTCOME_VAR]]),
      match_id = as.character(.data[[STRATA_VAR]])
    ) %>%
    filter(!is.na(match_id), !is.na(is_case))

  strata_ok <- df_sub %>%
    group_by(match_id) %>%
    summarise(has_case = any(is_case == 1), has_ctrl = any(is_case == 0), .groups = "drop") %>%
    filter(has_case & has_ctrl) %>%
    pull(match_id)

  df_sub <- df_sub %>% filter(match_id %in% strata_ok)

  cat("有效match_id数: ", n_distinct(df_sub$match_id), "\n")
  cat("病例数: ", sum(df_sub$is_case == 1, na.rm = TRUE), " | 对照数: ", sum(df_sub$is_case == 0, na.rm = TRUE), "\n")
  cat("用于稳健SE的cluster变量: ", ifelse(is.null(cluster_var), "NULL", cluster_var), "\n")

  if (n_distinct(df_sub$match_id) < 10) {
    cat("有效配对过少，跳过子集: ", subset_tag, "\n")
    return(NULL)
  }

  lag0_cols <- names(df_sub)[grepl("_lag0$", names(df_sub))]
  base_vars_detected <- unique(gsub("_lag0$", "", lag0_cols))

  candidate_vars <- base_vars_detected[
    sapply(base_vars_detected, function(v) is_valid_base_var(df_sub, v, max_lag = MAX_LAG, max_miss_lag0 = MAX_MISS_LAG0))
  ]

  flu_exposure_vars <- intersect(FLU_MAIN_VARS, candidate_vars)
  env_exposure_vars <- intersect(ENV_MAIN_VARS, candidate_vars)
  temp_nl_dlnm_vars <- intersect(TEMP_NL_DLNM_VARS, candidate_vars)
  pollutant_lin_dlnm_vars <- intersect(POLLUTANT_LIN_DLNM_VARS, candidate_vars)

  cat("流感主暴露变量: ", paste(flu_exposure_vars, collapse = ", "), "\n")
  cat("环境主暴露变量（0-7天候选）: ", paste(env_exposure_vars, collapse = ", "), "\n")
  cat("温度非线性DLNM变量: ", paste(temp_nl_dlnm_vars, collapse = ", "), "\n")
  cat("污染物线性distributed-lag变量: ", paste(pollutant_lin_dlnm_vars, collapse = ", "), "\n")

  agg_cols_all <- names(df_sub)[Reduce(`|`, lapply(AGG_PATTERNS, function(p) grepl(p, names(df_sub))))]
  agg_cols_all <- agg_cols_all[!is.na(agg_cols_all)]
  if (length(agg_cols_all) > 0 && length(flu_exposure_vars) > 0) {
    agg_cols_flu <- agg_cols_all[
      vapply(
        agg_cols_all,
        function(x) any(startsWith(x, paste0(flu_exposure_vars, "_"))),
        logical(1)
      )
    ]
  } else {
    agg_cols_flu <- character()
  }

  df_sub <- make_required_multi_day_lags(
    df_sub,
    vars = unique(c(env_exposure_vars, "Tavg", "RHUM", "阳性率")),
    max_lag = 7
  )

  cat("\n2A) 流感主暴露模型...\n")

  flu_clogit_ok <- list()
  flu_clogit_fail <- list()
  flu_agg_ok <- list()
  flu_agg_fail <- list()
  flu_dlnm_lag <- list()
  flu_dlnm_cum <- list()
  flu_dlnm_meta <- list()
  flu_dlnm_fail <- list()

  for (i in seq_along(flu_exposure_vars)) {
    v <- flu_exposure_vars[i]
    cat(sprintf("  [流感 %d/%d] %s\n", i, length(flu_exposure_vars), v))

    rr1 <- run_clogit_lags_0_7(df_sub, v, lags = CLOGIT_LAGS, strata_var = STRATA_VAR, cluster_var = cluster_var)
    if (isTRUE(rr1$ok) && nrow(rr1$res) > 0) flu_clogit_ok[[v]] <- rr1$res
    if (nrow(rr1$fail) > 0) flu_clogit_fail[[v]] <- rr1$fail

    if (isTRUE(RUN_FLU_DLNM)) {
    rr2 <- run_one_dlnm(
      df_sub, v,
      max_lag = MAX_LAG, focus_lags = FOCUS_LAGS, focus_win = FOCUS_WIN,
      strata_var = STRATA_VAR, cluster_var = cluster_var,
      df_var_target = DF_VAR_TARGET, df_lag = DF_LAG,
      effect_type = "per_scaled_unit", max_miss_lag0 = MAX_MISS_LAG0
    )
    if (isTRUE(rr2$ok)) {
      flu_dlnm_lag[[paste0(v, "_scaled")]] <- rr2$lag_effects
      flu_dlnm_cum[[paste0(v, "_scaled")]] <- rr2$cum_effects
      flu_dlnm_meta[[paste0(v, "_scaled")]] <- rr2$meta
    } else {
      flu_dlnm_fail[[paste0(v, "_scaled")]] <- tibble(variable = v, effect_type = "per_scaled_unit", reason = rr2$error)
    }

    rr3 <- run_one_dlnm(
      df_sub, v,
      max_lag = MAX_LAG, focus_lags = FOCUS_LAGS, focus_win = FOCUS_WIN,
      strata_var = STRATA_VAR, cluster_var = cluster_var,
      df_var_target = DF_VAR_TARGET, df_lag = DF_LAG,
      effect_type = "per_iqr", max_miss_lag0 = MAX_MISS_LAG0
    )
    if (isTRUE(rr3$ok)) {
      flu_dlnm_lag[[paste0(v, "_iqr")]] <- rr3$lag_effects
      flu_dlnm_cum[[paste0(v, "_iqr")]] <- rr3$cum_effects
      flu_dlnm_meta[[paste0(v, "_iqr")]] <- rr3$meta
    } else {
      flu_dlnm_fail[[paste0(v, "_iqr")]] <- tibble(variable = v, effect_type = "per_iqr", reason = rr3$error)
    }
    }
  }

  if (length(agg_cols_flu) > 0) {
    for (coln in agg_cols_flu) {
      rr <- run_clogit_agg_exposures(df_sub, coln, strata_var = STRATA_VAR, cluster_var = cluster_var)
      if (isTRUE(rr$ok) && nrow(rr$res) > 0) flu_agg_ok[[coln]] <- rr$res
      if (nrow(rr$fail) > 0) flu_agg_fail[[coln]] <- rr$fail
    }
  }

  flu_clogit_df <- if (length(flu_clogit_ok) > 0) bind_rows(flu_clogit_ok) else tibble()
  flu_clogit_fail_df <- if (length(flu_clogit_fail) > 0) bind_rows(flu_clogit_fail) else tibble()
  flu_agg_df <- if (length(flu_agg_ok) > 0) bind_rows(flu_agg_ok) else tibble()
  flu_agg_fail_df <- if (length(flu_agg_fail) > 0) bind_rows(flu_agg_fail) else tibble()
  flu_dlnm_lag_df <- if (length(flu_dlnm_lag) > 0) bind_rows(flu_dlnm_lag) else tibble()
  flu_dlnm_cum_df <- if (length(flu_dlnm_cum) > 0) bind_rows(flu_dlnm_cum) else tibble()
  flu_dlnm_meta_df <- if (length(flu_dlnm_meta) > 0) bind_rows(flu_dlnm_meta) else tibble()
  flu_dlnm_fail_df <- if (length(flu_dlnm_fail) > 0) bind_rows(flu_dlnm_fail) else tibble()

  env_main_ok <- list()
  env_main_fail <- list()

  for (i in seq_along(env_exposure_vars)) {
    v <- env_exposure_vars[i]
    cat(sprintf("  [环境 %d/%d] %s\n", i, length(env_exposure_vars), v))

    rr <- run_env_main_lag_models(
      df = df_sub,
      base_var = v,
      strata_var = STRATA_VAR,
      cluster_var = cluster_var,
      outcome_var = OUTCOME_VAR
    )

    if (isTRUE(rr$ok) && nrow(rr$res) > 0) env_main_ok[[v]] <- rr$res
    if (nrow(rr$fail) > 0) env_main_fail[[v]] <- rr$fail
  }

  ext_count_vars_exist <- EXT_TEMP_COUNT_MAIN_VARS[EXT_TEMP_COUNT_MAIN_VARS %in% names(df_sub)]

  if (length(ext_count_vars_exist) > 0) {
    for (coln in ext_count_vars_exist) {
      cat(sprintf("  [环境计数主变量] %s\n", coln))

      rr <- run_env_count_main_model(
        df = df_sub,
        exposure_col = coln,
        display_var = coln,
        strata_var = STRATA_VAR,
        cluster_var = cluster_var,
        outcome_var = OUTCOME_VAR
      )

      if (isTRUE(rr$ok) && nrow(rr$res) > 0) env_main_ok[[coln]] <- rr$res
      if (nrow(rr$fail) > 0) env_main_fail[[coln]] <- rr$fail
    }
  }

  env_main_df <- if (length(env_main_ok) > 0) bind_rows(env_main_ok) else tibble()
  env_main_fail_df <- if (length(env_main_fail) > 0) bind_rows(env_main_fail) else tibble()


  temp_nl_overall_list <- list()
  temp_nl_lagspec_list <- list()
  temp_nl_contour_list <- list()
  temp_nl_meta_list <- list()
  temp_nl_fail_list <- list()

  if (isTRUE(RUN_TEMP_NL_DLNM) && length(temp_nl_dlnm_vars) > 0) {
    for (i in seq_along(temp_nl_dlnm_vars)) {
      tv <- temp_nl_dlnm_vars[i]

      rr <- run_temp_nl_dlnm_analysis(
        df = df_sub,
        temp_var = tv,
        strata_var = STRATA_VAR,
        cluster_var = cluster_var,
        outcome_var = OUTCOME_VAR,
        max_lag = TEMP_NL_DLNM_MAX_LAG,
        df_var = TEMP_NL_DLNM_DF_VAR,
        df_lag = TEMP_NL_DLNM_DF_LAG,
        pred_q = TEMP_NL_DLNM_PRED_Q,
        pred_n = TEMP_NL_DLNM_PRED_N
      )

      if (isTRUE(rr$ok)) {
        temp_nl_overall_list[[tv]] <- rr$overall
        temp_nl_lagspec_list[[tv]] <- rr$lag_specific
        temp_nl_contour_list[[tv]] <- rr$contour
        temp_nl_meta_list[[tv]] <- rr$meta
      } else {
        temp_nl_fail_list[[tv]] <- tibble(variable = tv, reason = rr$error)
      }
    }
  }

  temp_nl_overall_df <- if (length(temp_nl_overall_list) > 0) bind_rows(temp_nl_overall_list) else tibble()
  temp_nl_lagspec_df <- if (length(temp_nl_lagspec_list) > 0) bind_rows(temp_nl_lagspec_list) else tibble()
  temp_nl_contour_df <- if (length(temp_nl_contour_list) > 0) bind_rows(temp_nl_contour_list) else tibble()
  temp_nl_meta_df <- if (length(temp_nl_meta_list) > 0) bind_rows(temp_nl_meta_list) else tibble()
  temp_nl_fail_df <- if (length(temp_nl_fail_list) > 0) bind_rows(temp_nl_fail_list) else tibble()


  pollutant_lag_all_list <- list()
  pollutant_lag_report_list <- list()
  pollutant_cum_list <- list()
  pollutant_meta_list <- list()
  pollutant_fail_list <- list()

  if (isTRUE(RUN_POLLUTANT_LIN_DLNM) && length(pollutant_lin_dlnm_vars) > 0) {
    for (i in seq_along(pollutant_lin_dlnm_vars)) {
      pv <- pollutant_lin_dlnm_vars[i]

      rr <- run_pollutant_linear_dlnm_analysis(
        df = df_sub,
        pollutant_var = pv,
        strata_var = STRATA_VAR,
        cluster_var = cluster_var,
        outcome_var = OUTCOME_VAR,
        max_lag = POLLUTANT_LIN_DLNM_MAX_LAG,
        df_lag = POLLUTANT_LIN_DLNM_DF_LAG,
        report_lags = POLLUTANT_LIN_DLNM_LAGS_TO_REPORT
      )

      if (isTRUE(rr$ok)) {
        pollutant_lag_all_list[[pv]] <- rr$lag_all
        pollutant_lag_report_list[[pv]] <- rr$lag_report
        pollutant_cum_list[[pv]] <- rr$cumulative
        pollutant_meta_list[[pv]] <- rr$meta
      } else {
        pollutant_fail_list[[pv]] <- tibble(variable = pv, reason = rr$error)
      }
    }
  }

  pollutant_lag_all_df <- if (length(pollutant_lag_all_list) > 0) bind_rows(pollutant_lag_all_list) else tibble()
  pollutant_lag_report_df <- if (length(pollutant_lag_report_list) > 0) bind_rows(pollutant_lag_report_list) else tibble()
  pollutant_cum_df <- if (length(pollutant_cum_list) > 0) bind_rows(pollutant_cum_list) else tibble()
  pollutant_meta_df <- if (length(pollutant_meta_list) > 0) bind_rows(pollutant_meta_list) else tibble()
  pollutant_fail_df <- if (length(pollutant_fail_list) > 0) bind_rows(pollutant_fail_list) else tibble()


  lag2_group_test_list <- list()
  lag2_group_test_fail_list <- list()

  lag2_group_or_detail_list <- list()
  lag2_group_or_detail_fail_list <- list()

  n_lag2_try  <- 0
  n_lag2_ok   <- 0
  n_lag2_fail <- 0

  if (isTRUE(RUN_GROUP_STRATIFIED)) {
    group_vars_exist_local <- ANALYSIS_GROUP_VARS[ANALYSIS_GROUP_VARS %in% names(df_sub)]

    current_group_var <- NA_character_
    if (grepl("^group__", subset_tag)) {
      parts <- strsplit(subset_tag, "__", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        current_group_var <- parts[2]
        group_vars_exist_local <- setdiff(group_vars_exist_local, current_group_var)
      }
    }


    if (length(flu_exposure_vars) > 0 && length(group_vars_exist_local) > 0) {
      for (gv in group_vars_exist_local) {

        for (v in flu_exposure_vars) {
          n_lag2_try <- n_lag2_try + 1

          rr_int <- tryCatch(
            run_lag2_group_interaction_test(
              df = df_sub,
              base_var = v,
              group_var = gv,
              model_family = "flu_primary",
              strata_var = STRATA_VAR,
              cluster_var = cluster_var,
              outcome_var = OUTCOME_VAR
            ),
            error = function(e) {
              list(
                ok = FALSE,
                res = tibble(
                  variable = v,
                  var_label = add_var_label(v),
                  group = add_group(v),
                  group_var = gv,
                  group_var_label = add_group_var_label(gv),
                  model_family = "flu_primary",
                  lag = 2,
                  reason = paste0("unexpected error: ", e$message)
                )
              )
            }
          )

          if (isTRUE(rr_int$ok) && !is.null(rr_int$res) && nrow(rr_int$res) > 0) {
            n_lag2_ok <- n_lag2_ok + 1
            lag2_group_test_list[[length(lag2_group_test_list) + 1]] <- rr_int$res
          } else {
            n_lag2_fail <- n_lag2_fail + 1
            fail_res <- rr_int$res
            if (is.null(fail_res) || nrow(fail_res) == 0) {
              fail_res <- tibble(
                variable = v,
                var_label = add_var_label(v),
                group = add_group(v),
                group_var = gv,
                group_var_label = add_group_var_label(gv),
                model_family = "flu_primary",
                lag = 2,
                reason = "empty fail result"
              )
            }
            lag2_group_test_fail_list[[length(lag2_group_test_fail_list) + 1]] <- fail_res
          }

          rr_or_detail <- tryCatch(
            run_lag2_group_interaction_or_detail(
              df = df_sub,
              base_var = v,
              group_var = gv,
              model_family = "flu_primary",
              strata_var = STRATA_VAR,
              cluster_var = cluster_var,
              outcome_var = OUTCOME_VAR
            ),
            error = function(e) {
              list(
                ok = FALSE,
                detail = tibble(
                  variable = v,
                  var_label = add_var_label(v),
                  group = add_group(v),
                  group_var = gv,
                  group_var_label = add_group_var_label(gv),
                  model_family = "flu_primary",
                  lag = 2,
                  group_level = NA_character_,
                  reference_level = NA_character_,
                  beta = NA_real_,
                  se = NA_real_,
                  or = NA_real_,
                  ci_low = NA_real_,
                  ci_high = NA_real_,
                  p_value = NA_real_,
                  p_interaction = NA_real_,
                  n_levels = NA_integer_,
                  n_cases = NA_integer_,
                  n_controls = NA_integer_,
                  n_strata = NA_integer_,
                  adjust_vars = NA_character_,
                  reason = paste0("unexpected error: ", e$message)
                )
              )
            }
          )

          if (isTRUE(rr_or_detail$ok) && !is.null(rr_or_detail$detail) && nrow(rr_or_detail$detail) > 0) {
            lag2_group_or_detail_list[[length(lag2_group_or_detail_list) + 1]] <- rr_or_detail$detail
          } else {
            fail_detail <- rr_or_detail$detail
            if (is.null(fail_detail) || nrow(fail_detail) == 0) {
              fail_detail <- tibble(
                variable = v,
                var_label = add_var_label(v),
                group = add_group(v),
                group_var = gv,
                group_var_label = add_group_var_label(gv),
                model_family = "flu_primary",
                lag = 2,
                group_level = NA_character_,
                reference_level = NA_character_,
                beta = NA_real_,
                se = NA_real_,
                or = NA_real_,
                ci_low = NA_real_,
                ci_high = NA_real_,
                p_value = NA_real_,
                p_interaction = NA_real_,
                n_levels = NA_integer_,
                n_cases = NA_integer_,
                n_controls = NA_integer_,
                n_strata = NA_integer_,
                adjust_vars = NA_character_,
                reason = "empty OR detail fail result"
              )
            }
            lag2_group_or_detail_fail_list[[length(lag2_group_or_detail_fail_list) + 1]] <- fail_detail
          }
        }
      }
    }

    env_vars_for_lag2_test <- env_exposure_vars[paste0(env_exposure_vars, "_lag2") %in% names(df_sub)]

    if (length(env_vars_for_lag2_test) > 0 && length(group_vars_exist_local) > 0) {
      for (gv in group_vars_exist_local) {

        for (v in env_vars_for_lag2_test) {
          n_lag2_try <- n_lag2_try + 1

          rr_int <- tryCatch(
            run_lag2_group_interaction_test(
              df = df_sub,
              base_var = v,
              group_var = gv,
              model_family = "env_primary",
              strata_var = STRATA_VAR,
              cluster_var = cluster_var,
              outcome_var = OUTCOME_VAR
            ),
            error = function(e) {
              list(
                ok = FALSE,
                res = tibble(
                  variable = v,
                  var_label = add_var_label(v),
                  group = add_group(v),
                  group_var = gv,
                  group_var_label = add_group_var_label(gv),
                  model_family = "env_primary",
                  lag = 2,
                  reason = paste0("unexpected error: ", e$message)
                )
              )
            }
          )

          if (isTRUE(rr_int$ok) && !is.null(rr_int$res) && nrow(rr_int$res) > 0) {
            n_lag2_ok <- n_lag2_ok + 1
            lag2_group_test_list[[length(lag2_group_test_list) + 1]] <- rr_int$res
          } else {
            n_lag2_fail <- n_lag2_fail + 1
            fail_res <- rr_int$res
            if (is.null(fail_res) || nrow(fail_res) == 0) {
              fail_res <- tibble(
                variable = v,
                var_label = add_var_label(v),
                group = add_group(v),
                group_var = gv,
                group_var_label = add_group_var_label(gv),
                model_family = "env_primary",
                lag = 2,
                reason = "empty fail result"
              )
            }
            lag2_group_test_fail_list[[length(lag2_group_test_fail_list) + 1]] <- fail_res
          }

          rr_or_detail <- tryCatch(
            run_lag2_group_interaction_or_detail(
              df = df_sub,
              base_var = v,
              group_var = gv,
              model_family = "env_primary",
              strata_var = STRATA_VAR,
              cluster_var = cluster_var,
              outcome_var = OUTCOME_VAR
            ),
            error = function(e) {
              list(
                ok = FALSE,
                detail = tibble(
                  variable = v,
                  var_label = add_var_label(v),
                  group = add_group(v),
                  group_var = gv,
                  group_var_label = add_group_var_label(gv),
                  model_family = "env_primary",
                  lag = 2,
                  group_level = NA_character_,
                  reference_level = NA_character_,
                  beta = NA_real_,
                  se = NA_real_,
                  or = NA_real_,
                  ci_low = NA_real_,
                  ci_high = NA_real_,
                  p_value = NA_real_,
                  p_interaction = NA_real_,
                  n_levels = NA_integer_,
                  n_cases = NA_integer_,
                  n_controls = NA_integer_,
                  n_strata = NA_integer_,
                  adjust_vars = NA_character_,
                  reason = paste0("unexpected error: ", e$message)
                )
              )
            }
          )

          if (isTRUE(rr_or_detail$ok) && !is.null(rr_or_detail$detail) && nrow(rr_or_detail$detail) > 0) {
            lag2_group_or_detail_list[[length(lag2_group_or_detail_list) + 1]] <- rr_or_detail$detail
          } else {
            fail_detail <- rr_or_detail$detail
            if (is.null(fail_detail) || nrow(fail_detail) == 0) {
              fail_detail <- tibble(
                variable = v,
                var_label = add_var_label(v),
                group = add_group(v),
                group_var = gv,
                group_var_label = add_group_var_label(gv),
                model_family = "env_primary",
                lag = 2,
                group_level = NA_character_,
                reference_level = NA_character_,
                beta = NA_real_,
                se = NA_real_,
                or = NA_real_,
                ci_low = NA_real_,
                ci_high = NA_real_,
                p_value = NA_real_,
                p_interaction = NA_real_,
                n_levels = NA_integer_,
                n_cases = NA_integer_,
                n_controls = NA_integer_,
                n_strata = NA_integer_,
                adjust_vars = NA_character_,
                reason = "empty OR detail fail result"
              )
            }
            lag2_group_or_detail_fail_list[[length(lag2_group_or_detail_fail_list) + 1]] <- fail_detail
          }
        }
      }
    }
  }

  lag2_group_test_df <- if (length(lag2_group_test_list) > 0) bind_rows(lag2_group_test_list) else tibble()
  lag2_group_test_fail_df <- if (length(lag2_group_test_fail_list) > 0) bind_rows(lag2_group_test_fail_list) else tibble()

  lag2_group_or_detail_df <- if (length(lag2_group_or_detail_list) > 0) bind_rows(lag2_group_or_detail_list) else tibble()
  lag2_group_or_detail_fail_df <- if (length(lag2_group_or_detail_fail_list) > 0) bind_rows(lag2_group_or_detail_fail_list) else tibble()

  if (nrow(lag2_group_test_df) > 0) {
    lag2_group_test_df <- lag2_group_test_df %>%
      mutate(
        p_interaction_fdr = p.adjust(p_interaction, method = "fdr"),
        interaction_sig = case_when(
          is.na(p_interaction) ~ NA_character_,
          p_interaction < 0.05 ~ "Pint<0.05",
          TRUE ~ "Pint≥0.05"
        ),
        interaction_sig_fdr = case_when(
          is.na(p_interaction_fdr) ~ NA_character_,
          p_interaction_fdr < 0.05 ~ "FDR<0.05",
          TRUE ~ "FDR≥0.05"
        )
      ) %>%
      arrange(model_family, variable, group_var, p_interaction)
  }

  if (nrow(lag2_group_test_fail_df) > 0) {
    lag2_group_test_fail_df <- lag2_group_test_fail_df %>%
      arrange(model_family, variable, group_var)
  }

  if (nrow(lag2_group_or_detail_df) > 0) {
    lag2_group_or_detail_df <- lag2_group_or_detail_df %>%
      mutate(
        p_interaction_fdr = p.adjust(p_interaction, method = "fdr"),
        interaction_sig = case_when(
          is.na(p_interaction) ~ NA_character_,
          p_interaction < 0.05 ~ "Pint<0.05",
          TRUE ~ "Pint≥0.05"
        ),
        interaction_sig_fdr = case_when(
          is.na(p_interaction_fdr) ~ NA_character_,
          p_interaction_fdr < 0.05 ~ "FDR<0.05",
          TRUE ~ "FDR≥0.05"
        ),
        or_ci = ifelse(
          is.finite(or) & is.finite(ci_low) & is.finite(ci_high),
          sprintf("%.3f (%.3f, %.3f)", or, ci_low, ci_high),
          NA_character_
        )
      ) %>%
      arrange(model_family, variable, group_var, group_level, p_interaction)
  }

  if (nrow(lag2_group_or_detail_fail_df) > 0) {
    lag2_group_or_detail_fail_df <- lag2_group_or_detail_fail_df %>%
      arrange(model_family, variable, group_var, group_level)
  }


  if (nrow(lag2_group_test_fail_df) > 0 && "reason" %in% names(lag2_group_test_fail_df)) {
    print(
      lag2_group_test_fail_df %>%
        count(reason, sort = TRUE) %>%
        slice_head(n = 10)
    )
  }


  
  invisible(list(
    subset_tag = subset_tag,
    flu_clogit_df = flu_clogit_df,
    flu_dlnm_lag_df = flu_dlnm_lag_df,
    flu_dlnm_cum_df = flu_dlnm_cum_df,
    env_main_df = env_main_df,
    temp_nl_overall_df = temp_nl_overall_df,
    pollutant_lag_all_df = pollutant_lag_all_df,
    pollutant_cum_df = pollutant_cum_df,
    lag2_group_test_df = lag2_group_test_df,
    lag2_group_test_fail_df = lag2_group_test_fail_df,
    lag2_group_or_detail_df = lag2_group_or_detail_df,
    lag2_group_or_detail_fail_df = lag2_group_or_detail_fail_df,
    n_rows = nrow(df_sub),
    n_cases = sum(df_sub[[OUTCOME_VAR]] == 1, na.rm = TRUE),
    n_controls = sum(df_sub[[OUTCOME_VAR]] == 0, na.rm = TRUE),
    n_strata = dplyr::n_distinct(df_sub[[STRATA_VAR]])
  ))

}

combine_final_tables <- function(result_list, output_dir_base = output_dir) {
  summary_dir <- file.path(output_dir_base, "summary_combined")
  dir.create(summary_dir, showWarnings = FALSE, recursive = TRUE)

  valid_res <- result_list[!vapply(result_list, is.null, logical(1))]
  if (length(valid_res) == 0) {
    return(NULL)
  }

  safe_extract_df <- function(res_obj, element_name) {
    if (is.null(res_obj)) return(NULL)
    if (!element_name %in% names(res_obj)) return(NULL)
    x <- res_obj[[element_name]]
    if (is.null(x)) return(NULL)
    if (!inherits(x, c("data.frame", "tbl_df", "tbl"))) return(NULL)
    if (nrow(x) == 0) return(NULL)
    x
  }

  bind_with_subset <- function(valid_res, element_name) {
    out <- bind_rows(
      lapply(names(valid_res), function(ss) {
        x <- safe_extract_df(valid_res[[ss]], element_name)
        if (is.null(x)) return(NULL)
        x %>% mutate(subset = ss, .before = 1)
      })
    )
    if (is.null(out)) out <- tibble()
    out
  }

  safe_add_or_ci <- function(df,
                             est_col = "or",
                             low_col = "ci_low",
                             high_col = "ci_high",
                             out_col = "or_ci") {
    if (nrow(df) == 0) {
      df[[out_col]] <- character(0)
      return(df)
    }

    if (!all(c(est_col, low_col, high_col) %in% names(df))) {
      df[[out_col]] <- NA_character_
      return(df)
    }

    df %>%
      mutate(
        !!out_col := ifelse(
          is.finite(.data[[est_col]]) & is.finite(.data[[low_col]]) & is.finite(.data[[high_col]]),
          sprintf("%.3f (%.3f, %.3f)", .data[[est_col]], .data[[low_col]], .data[[high_col]]),
          NA_character_
        )
      )
  }

  safe_add_rr_ci <- function(df,
                             est_col = "cum_or",
                             low_col = "cum_ci_low",
                             high_col = "cum_ci_high",
                             out_col = "rr_ci") {
    if (nrow(df) == 0) {
      df[[out_col]] <- character(0)
      return(df)
    }

    if (!all(c(est_col, low_col, high_col) %in% names(df))) {
      df[[out_col]] <- NA_character_
      return(df)
    }

    df %>%
      mutate(
        !!out_col := ifelse(
          is.finite(.data[[est_col]]) & is.finite(.data[[low_col]]) & is.finite(.data[[high_col]]),
          sprintf("%.3f (%.3f, %.3f)", .data[[est_col]], .data[[low_col]], .data[[high_col]]),
          NA_character_
        )
      )
  }

  add_fdr_columns <- function(df, p_col = "p_interaction") {
    if (nrow(df) == 0) {
      df$p_interaction_fdr_global <- numeric(0)
      df$p_interaction_fdr_by_model <- numeric(0)
      df$interaction_sig <- character(0)
      df$interaction_sig_fdr_global <- character(0)
      df$interaction_sig_fdr_by_model <- character(0)
      return(df)
    }

    if (!(p_col %in% names(df))) {
      df$p_interaction_fdr_global <- NA_real_
      df$p_interaction_fdr_by_model <- NA_real_
      df$interaction_sig <- NA_character_
      df$interaction_sig_fdr_global <- NA_character_
      df$interaction_sig_fdr_by_model <- NA_character_
      return(df)
    }

    df <- df %>%
      mutate(
        p_interaction_fdr_global = NA_real_,
        p_interaction_fdr_by_model = NA_real_
      )

    idx_ok_global <- which(is.finite(df[[p_col]]))
    if (length(idx_ok_global) > 0) {
      df$p_interaction_fdr_global[idx_ok_global] <-
        p.adjust(df[[p_col]][idx_ok_global], method = "fdr")
    }

    if ("model_family" %in% names(df)) {
      df <- df %>%
        group_by(model_family) %>%
        group_modify(~ {
          dd <- .x
          dd$p_interaction_fdr_by_model <- NA_real_
          idx_ok <- which(is.finite(dd[[p_col]]))
          if (length(idx_ok) > 0) {
            dd$p_interaction_fdr_by_model[idx_ok] <-
              p.adjust(dd[[p_col]][idx_ok], method = "fdr")
          }
          dd
        }) %>%
        ungroup()
    }

    df %>%
      mutate(
        interaction_sig = case_when(
          is.na(.data[[p_col]]) ~ NA_character_,
          .data[[p_col]] < 0.05 ~ "Pint<0.05",
          TRUE ~ "Pint≥0.05"
        ),
        interaction_sig_fdr_global = case_when(
          is.na(p_interaction_fdr_global) ~ NA_character_,
          p_interaction_fdr_global < 0.05 ~ "FDR(global)<0.05",
          TRUE ~ "FDR(global)≥0.05"
        ),
        interaction_sig_fdr_by_model = case_when(
          is.na(p_interaction_fdr_by_model) ~ NA_character_,
          p_interaction_fdr_by_model < 0.05 ~ "FDR(by_model)<0.05",
          TRUE ~ "FDR(by_model)≥0.05"
        )
      )
  }

  env_alllags_combined        <- bind_with_subset(valid_res, "env_main_df")
  flu_clogit_combined         <- bind_with_subset(valid_res, "flu_clogit_df")
  flu_dlnm_lag_combined       <- bind_with_subset(valid_res, "flu_dlnm_lag_df")
  flu_dlnm_cum_combined       <- bind_with_subset(valid_res, "flu_dlnm_cum_df")
  temp_nl_overall_combined    <- bind_with_subset(valid_res, "temp_nl_overall_df")
  pollutant_lag_all_combined  <- bind_with_subset(valid_res, "pollutant_lag_all_df")
  pollutant_cum_combined      <- bind_with_subset(valid_res, "pollutant_cum_df")
  lag2_group_test_combined    <- bind_with_subset(valid_res, "lag2_group_test_df")
  lag2_group_test_fail_combined <- bind_with_subset(valid_res, "lag2_group_test_fail_df")
  lag2_group_or_detail_combined <- bind_with_subset(valid_res, "lag2_group_or_detail_df")
  lag2_group_or_detail_fail_combined <- bind_with_subset(valid_res, "lag2_group_or_detail_fail_df")

  final_key_summary <- bind_rows(
    if (nrow(env_alllags_combined) > 0) {
      env_alllags_combined %>% mutate(result_type = "env_all_lags")
    } else NULL,
    if (nrow(flu_dlnm_cum_combined) > 0) {
      flu_dlnm_cum_combined %>% mutate(result_type = "flu_dlnm_cumulative")
    } else NULL,
    if (nrow(temp_nl_overall_combined) > 0) {
      temp_nl_overall_combined %>% mutate(result_type = "temp_nonlinear_dlnm_overall")
    } else NULL,
    if (nrow(pollutant_cum_combined) > 0) {
      pollutant_cum_combined %>% mutate(result_type = "pollutant_linear_distributedlag_cumulative")
    } else NULL
  )

  if (nrow(final_key_summary) > 0) {
    final_key_summary <- final_key_summary %>%
      relocate(result_type, .after = subset)
  }

  lag2_flu_clogit <- tibble()
  if (nrow(flu_clogit_combined) > 0 && "lag" %in% names(flu_clogit_combined)) {
    lag2_flu_clogit <- flu_clogit_combined %>%
      filter(lag == 2) %>%
      mutate(
        model_family = "Flu primary exposure",
        model_type = "CLOGIT",
        lag2_source = "flu_clogit_lag2",
        exposure_term_final = paste0(variable, "_lag2")
      ) %>%
      select(any_of(c(
        "subset", "model_family", "model_type", "lag2_source",
        "variable", "var_label", "group", "exposure_term_final",
        "effect_type", "scale_value", "scale_label", "iqr_value",
        "adjust_vars", "or", "ci_low", "ci_high", "p_value",
        "n_cases", "n_controls", "n_strata"
      ))) %>%
      safe_add_or_ci(est_col = "or", low_col = "ci_low", high_col = "ci_high", out_col = "or_ci")
  }

  lag2_flu_dlnm <- tibble()
  if (nrow(flu_dlnm_lag_combined) > 0 && "lag" %in% names(flu_dlnm_lag_combined)) {
    lag2_flu_dlnm <- flu_dlnm_lag_combined %>%
      filter(lag == 2) %>%
      mutate(
        model_family = "Flu primary exposure",
        model_type = "DLNM",
        lag2_source = "flu_dlnm_lag2",
        exposure_term_final = paste0(variable, "_lag2")
      ) %>%
      select(any_of(c(
        "subset", "model_family", "model_type", "lag2_source",
        "variable", "var_label", "group", "exposure_term_final",
        "effect_type", "scale_value", "scale_label", "iqr_value",
        "adjust_vars", "or", "ci_low", "ci_high", "p_value",
        "n_cases", "n_controls", "n_strata"
      ))) %>%
      safe_add_or_ci(est_col = "or", low_col = "ci_low", high_col = "ci_high", out_col = "or_ci")
  }

  lag2_env_main <- tibble()
  if (nrow(env_alllags_combined) > 0 && "exposure_term" %in% names(env_alllags_combined)) {
    lag2_env_main <- env_alllags_combined %>%
      filter(grepl("_lag2$", exposure_term)) %>%
      mutate(
        model_family = "Environmental primary exposure",
        model_type = "CLOGIT",
        lag2_source = "env_clogit_lag2",
        exposure_term_final = exposure_term
      ) %>%
      select(any_of(c(
        "subset", "model_family", "model_type", "lag2_source",
        "variable", "var_label", "group", "exposure_term_final",
        "effect_type", "scale_value", "scale_label", "iqr_value",
        "adjust_vars", "or", "ci_low", "ci_high", "p_value",
        "n_cases", "n_controls", "n_strata"
      ))) %>%
      safe_add_or_ci(est_col = "or", low_col = "ci_low", high_col = "ci_high", out_col = "or_ci")
  }

  lag2_pollutant_dl <- tibble()
  if (nrow(pollutant_lag_all_combined) > 0 && "lag" %in% names(pollutant_lag_all_combined)) {
    lag2_pollutant_dl <- pollutant_lag_all_combined %>%
      filter(lag == 2) %>%
      mutate(
        model_family = "Environmental secondary exposure",
        model_type = "Linear distributed-lag",
        lag2_source = "pollutant_linear_dl_lag2",
        exposure_term_final = paste0(variable, "_lag2")
      ) %>%
      select(any_of(c(
        "subset", "model_family", "model_type", "lag2_source",
        "variable", "var_label", "group", "exposure_term_final",
        "effect_type", "scale_value", "scale_label", "iqr_value",
        "adjust_vars", "or", "ci_low", "ci_high", "p_value",
        "n_cases", "n_controls", "n_strata"
      ))) %>%
      safe_add_or_ci(est_col = "or", low_col = "ci_low", high_col = "ci_high", out_col = "or_ci")
  }

  lag2_summary <- bind_rows(
    lag2_flu_clogit,
    lag2_flu_dlnm,
    lag2_env_main,
    lag2_pollutant_dl
  )

  if (nrow(lag2_summary) > 0) {
    lag2_summary <- lag2_summary %>%
      arrange(model_family, model_type, variable, subset, effect_type)
  }

  if (nrow(lag2_group_test_combined) > 0) {
    lag2_group_test_combined <- lag2_group_test_combined %>%
      add_fdr_columns(p_col = "p_interaction") %>%
      arrange(model_family, variable, group_var, subset, p_interaction)
  } else {
    lag2_group_test_combined <- tibble(
      subset = character(),
      variable = character(),
      var_label = character(),
      group = character(),
      group_var = character(),
      group_var_label = character(),
      model_family = character(),
      lag = numeric(),
      p_interaction = numeric(),
      p_interaction_fdr_global = numeric(),
      p_interaction_fdr_by_model = numeric(),
      interaction_sig = character(),
      interaction_sig_fdr_global = character(),
      interaction_sig_fdr_by_model = character(),
      n_levels = integer(),
      n_cases = integer(),
      n_controls = integer(),
      n_strata = integer(),
      adjust_vars = character()
    )
  }

  if (nrow(lag2_group_test_fail_combined) > 0) {
    lag2_group_test_fail_combined <- lag2_group_test_fail_combined %>%
      arrange(model_family, variable, group_var, subset)
  }

  if (nrow(lag2_group_or_detail_combined) > 0) {
    lag2_group_or_detail_combined <- lag2_group_or_detail_combined %>%
      add_fdr_columns(p_col = "p_interaction") %>%
      mutate(
        or_ci = ifelse(
          is.finite(or) & is.finite(ci_low) & is.finite(ci_high),
          sprintf("%.3f (%.3f, %.3f)", or, ci_low, ci_high),
          NA_character_
        )
      ) %>%
      arrange(model_family, variable, group_var, subset, group_level, p_interaction)
  } else {
    lag2_group_or_detail_combined <- tibble(
      subset = character(),
      variable = character(),
      var_label = character(),
      group = character(),
      group_var = character(),
      group_var_label = character(),
      model_family = character(),
      lag = numeric(),
      group_level = character(),
      reference_level = character(),
      beta = numeric(),
      se = numeric(),
      or = numeric(),
      ci_low = numeric(),
      ci_high = numeric(),
      p_value = numeric(),
      or_ci = character(),
      p_interaction = numeric(),
      p_interaction_fdr_global = numeric(),
      p_interaction_fdr_by_model = numeric(),
      interaction_sig = character(),
      interaction_sig_fdr_global = character(),
      interaction_sig_fdr_by_model = character(),
      n_levels = integer(),
      n_cases = integer(),
      n_controls = integer(),
      n_strata = integer(),
      adjust_vars = character(),
      reason = character()
    )
  }

  if (nrow(lag2_group_or_detail_fail_combined) > 0) {
    lag2_group_or_detail_fail_combined <- lag2_group_or_detail_fail_combined %>%
      arrange(model_family, variable, group_var, subset, group_level)
  }

  lag2_fail_reason_summary <- tibble()
  if (nrow(lag2_group_test_fail_combined) > 0 && "reason" %in% names(lag2_group_test_fail_combined)) {
    lag2_fail_reason_summary <- lag2_group_test_fail_combined %>%
      count(model_family, reason, sort = TRUE)
  }

  
  invisible(list(
    env_alllags_combined = env_alllags_combined,
    flu_clogit_combined = flu_clogit_combined,
    flu_dlnm_lag_combined = flu_dlnm_lag_combined,
    flu_dlnm_cum_combined = flu_dlnm_cum_combined,
    temp_nl_overall_combined = temp_nl_overall_combined,
    pollutant_lag_all_combined = pollutant_lag_all_combined,
    pollutant_cum_combined = pollutant_cum_combined,
    lag2_group_or_detail_combined = lag2_group_or_detail_combined,
    lag2_group_or_detail_fail_combined = lag2_group_or_detail_fail_combined,
    lag2_group_test_combined = lag2_group_test_combined,
    lag2_group_test_fail_combined = lag2_group_test_fail_combined,
    lag2_fail_reason_summary = lag2_fail_reason_summary,
    final_key_summary = final_key_summary,
    lag2_summary = lag2_summary
  ))
}


df <- read_csv(data_path, locale = locale(encoding = "UTF-8"), show_col_types = FALSE)
if (nzchar(EXCLUDE_CENTRE)) {
  if (!(CENTRE_VAR %in% names(df))) stop(paste0("Missing centre column: ", CENTRE_VAR))
  df <- df %>% filter(as.character(.data[[CENTRE_VAR]]) != EXCLUDE_CENTRE)
}


pres_cols <- grep("^PRES(_lag[0-9]+|_avg_lag0_[0-9]+|_max_lag0_[0-9]+)?$", names(df), value = TRUE)

if (length(pres_cols) > 0) {
  converted <- character()
  for (col in pres_cols) {
    x <- suppressWarnings(as.numeric(df[[col]]))
    typical <- suppressWarnings(median(abs(x), na.rm = TRUE))
    if (is.finite(typical) && typical > 2000) {
      df[[col]] <- x / 100
      converted <- c(converted, col)
    } else {
      df[[col]] <- x
    }
  }
}

lag0_cols_all <- names(df)[grepl("_lag0$", names(df))]
base_vars_all <- unique(gsub("_lag0$", "", lag0_cols_all))

GLOBAL_IQR_MAP <<- build_global_iqr_map(
  df = df,
  base_vars = base_vars_all,
  max_lag = MAX_LAG
)

global_iqr_df <- tibble(
  variable = names(GLOBAL_IQR_MAP),
  global_iqr = as.numeric(GLOBAL_IQR_MAP),
  var_label = add_var_label(names(GLOBAL_IQR_MAP)),
  group = add_group(names(GLOBAL_IQR_MAP))
) %>%
  arrange(group, variable)


stopifnot(OUTCOME_VAR %in% names(df))
stopifnot(STRATA_VAR %in% names(df))
stopifnot(EVENT_DATE_VAR %in% names(df))

df <- add_heating_flag(df, event_date_var = EVENT_DATE_VAR)

if (RUN_COVID_WAVE_ADJUST) {
  df <- add_covid_major_wave_flag(df, date_var = EVENT_DATE_VAR, out_var = COVID_WAVE_VAR)
}


print(table(df$heating_season, useNA = "ifany"))

if (RUN_COVID_WAVE_ADJUST) {
  print(table(df[[COVID_WAVE_VAR]], useNA = "ifany"))
}


print(head(df %>% select(all_of(EVENT_DATE_VAR), event_date, heating_season,
                         any_of(COVID_WAVE_VAR)), 10))

all_results <- list()

all_results[["all"]] <- run_dual_strategy_analysis(
  df_sub = df,
  subset_tag = "all",
  output_dir_base = output_dir
)

if (isTRUE(RUN_HEATING_STRATIFIED)) {
  subset_levels <- c("heating", "non_heating")

  for (ss in subset_levels) {

    df_ss <- df %>% filter(heating_season == ss)



    if (nrow(df_ss) == 0) {
      cat("该子集无数据，跳过。\n")
      all_results[[ss]] <- NULL
      next
    }

    all_results[[ss]] <- tryCatch({
      run_dual_strategy_analysis(
        df_sub = df_ss,
        subset_tag = ss,
        output_dir_base = output_dir
      )
    }, error = function(e) {
      NULL
    })
  }
}

if (isTRUE(RUN_GROUP_STRATIFIED)) {

  group_vars_exist <- ANALYSIS_GROUP_VARS[ANALYSIS_GROUP_VARS %in% names(df)]

  print(group_vars_exist)

  group_registry <- list()

  for (gv in group_vars_exist) {

    valid_levels <- get_valid_group_levels(
      df = df,
      group_var = gv,
      outcome_var = OUTCOME_VAR,
      min_cases = MIN_CASES_PER_GROUP_LEVEL,
      min_rows = MIN_ROWS_PER_GROUP_LEVEL,
      keep_reference = KEEP_REFERENCE_LEVELS
    )

    if (nrow(valid_levels) == 0) {
      next
    }

    print(valid_levels)
    group_registry[[gv]] <- valid_levels

    for (ii in seq_len(nrow(valid_levels))) {
      gl <- valid_levels$group_level[ii]

      subset_tag <- make_group_subset_tag(gv, gl, prefix = "group")


      df_g <- df %>%
        filter(!is.na(.data[[gv]])) %>%
        filter(as.character(.data[[gv]]) == as.character(gl))



      if (nrow(df_g) == 0) {
        all_results[[subset_tag]] <- NULL
        next
      }

      all_results[[subset_tag]] <- tryCatch({
        rr <- run_dual_strategy_analysis(
          df_sub = df_g,
          subset_tag = subset_tag,
          output_dir_base = output_dir
        )

        if (!is.null(rr)) {
          rr$group_var <- gv
          rr$group_var_label <- add_group_var_label(gv)
          rr$group_level <- gl
        }
        rr
      }, error = function(e) {
        NULL
      })
    }
  }

  if (length(group_registry) > 0) {
    group_registry_df <- bind_rows(
      lapply(names(group_registry), function(gv) {
        group_registry[[gv]] %>%
          mutate(
            group_var = gv,
            group_var_label = add_group_var_label(gv),
            .before = 1
          )
      })
    )

    write.csv(
      group_registry_df,
      file.path(output_dir, paste0("分组分析注册表_", CONTROL_STRATEGY, ".csv")),
      row.names = FALSE
    )
  }
}

combined_results <- combine_final_tables(
  result_list = all_results,
  output_dir_base = output_dir
)

group_result_names <- names(all_results)[grepl("^group__", names(all_results))]
group_valid_res <- all_results[group_result_names]
group_valid_res <- group_valid_res[!vapply(group_valid_res, is.null, logical(1))]

if (length(group_valid_res) > 0) {
  group_summary_dir <- file.path(output_dir, "summary_groups")
  dir.create(group_summary_dir, showWarnings = FALSE, recursive = TRUE)

  extract_group_meta <- function(res_obj, default_subset_name) {
    tibble(
      subset = default_subset_name,
      group_var = if (!is.null(res_obj$group_var)) res_obj$group_var else NA_character_,
      group_var_label = if (!is.null(res_obj$group_var_label)) res_obj$group_var_label else NA_character_,
      group_level = if (!is.null(res_obj$group_level)) as.character(res_obj$group_level) else NA_character_,
      n_rows = if (!is.null(res_obj$n_rows)) res_obj$n_rows else NA_real_,
      n_cases = if (!is.null(res_obj$n_cases)) res_obj$n_cases else NA_real_,
      n_controls = if (!is.null(res_obj$n_controls)) res_obj$n_controls else NA_real_,
      n_strata = if (!is.null(res_obj$n_strata)) res_obj$n_strata else NA_real_
    )
  }

  group_meta_df <- bind_rows(
    lapply(names(group_valid_res), function(ss) {
      extract_group_meta(group_valid_res[[ss]], ss)
    })
  )

  group_env_alllags <- bind_rows(
    lapply(names(group_valid_res), function(ss) {
      x <- group_valid_res[[ss]]$env_main_df
      if (is.null(x) || nrow(x) == 0) return(NULL)
      meta <- extract_group_meta(group_valid_res[[ss]], ss)
      x %>% mutate(subset = ss, .before = 1) %>%
        left_join(meta, by = "subset")
    })
  )

  group_flu_dlnm_cum <- bind_rows(
    lapply(names(group_valid_res), function(ss) {
      x <- group_valid_res[[ss]]$flu_dlnm_cum_df
      if (is.null(x) || nrow(x) == 0) return(NULL)
      meta <- extract_group_meta(group_valid_res[[ss]], ss)
      x %>% mutate(subset = ss, .before = 1) %>%
        left_join(meta, by = "subset")
    })
  )

  group_temp_nl <- bind_rows(
    lapply(names(group_valid_res), function(ss) {
      x <- group_valid_res[[ss]]$temp_nl_overall_df
      if (is.null(x) || nrow(x) == 0) return(NULL)
      meta <- extract_group_meta(group_valid_res[[ss]], ss)
      x %>% mutate(subset = ss, .before = 1) %>%
        left_join(meta, by = "subset")
    })
  )

  group_pollutant_cum <- bind_rows(
    lapply(names(group_valid_res), function(ss) {
      x <- group_valid_res[[ss]]$pollutant_cum_df
      if (is.null(x) || nrow(x) == 0) return(NULL)
      meta <- extract_group_meta(group_valid_res[[ss]], ss)
      x %>% mutate(subset = ss, .before = 1) %>%
        left_join(meta, by = "subset")
    })
  )
cat(" - summary_combined\n")
cat(" - summary_groups\n")
cat(" - group__*\n")
