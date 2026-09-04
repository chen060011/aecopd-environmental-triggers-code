suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
  library(splines)
  library(sandwich)
})

CONTROL_STRATEGY <- "monthly_weekday"

DATA_DIR <- Sys.getenv("AECOPD_DATA_DIR", ".")
data_path <- Sys.getenv("AECOPD_ANALYSIS_INPUT", file.path(DATA_DIR, "analysis_input.csv"))

output_dir <- file.path(Sys.getenv("AECOPD_OUTPUT_DIR", "results"), CONTROL_STRATEGY)
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

EXPOSURE_H1 <- "A_H1N1占比_lag2"
EXPOSURE_H3 <- "A_H3N2占比_lag2"
BASE_H1 <- "A_H1N1占比"
BASE_H3 <- "A_H3N2占比"

FLU_TEMP_AVG_COL <- "Tavg_avg_lag0_2"
FLU_RHUM_AVG_COL <- "RHUM_avg_lag0_2"
FLU_TEMP_DF <- 6
FLU_RHUM_DF <- 3

SCALE_VALUE <- 10
SCALE_LABEL <- "per 10 percentage points"

VAR_LABEL_MAP <- c(
  "A_H1N1占比" = "A(H1N1)pdm09 (%)",
  "A_H3N2占比" = "A(H3N2) (%)",
  "covid_major_wave" = "COVID major-wave period",
  "holiday" = "Public holiday"
)

add_var_label <- function(v) {
  out <- unname(VAR_LABEL_MAP[v])
  ifelse(is.na(out), v, out)
}

theme_pub <- function(base_size = 11) {
  theme_classic(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 1, hjust = 0),
      plot.subtitle = element_text(size = base_size - 1, hjust = 0),
      axis.title = element_text(face = "bold"),
      axis.text = element_text(color = "black"),
      axis.line = element_line(linewidth = 0.4),
      axis.ticks = element_line(linewidth = 0.4),
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      legend.position = "top",
      legend.title = element_blank(),
      legend.key = element_blank(),
      panel.grid = element_blank(),
      plot.margin = margin(8, 10, 8, 8)
    )
}

COL_H1 <- "#C23B22"   # 深红
COL_H3 <- "#355C9A"   # 深蓝
COL_CONTRAST <- "#3F3F3F"

safe_is_finite <- function(x) is.finite(x) & !is.na(x)

get_cluster_var <- function(df, candidates = CLUSTER_CANDIDATES) {
  hit <- candidates[candidates %in% names(df)]
  if (length(hit) == 0) return(NULL)
  hit[1]
}

normalize_calendar_covariates <- function(df) {
  if ("public_holiday" %in% names(df) && !("holiday" %in% names(df))) {
    df <- df %>% mutate(holiday = as.numeric(public_holiday))
  }
  if ("holiday" %in% names(df)) {
    df <- df %>% mutate(holiday = as.numeric(holiday))
  }
  if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(df)) {
    df[[COVID_WAVE_VAR]] <- as.numeric(df[[COVID_WAVE_VAR]])
  }
  df
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
  if (!event_date_var %in% names(df)) stop(paste0("缺少事件日列: ", event_date_var))
  df %>%
    mutate(
      event_date = parse_event_date(.data[[event_date_var]]),
      heating_season = case_when(
        is.na(event_date) ~ NA_character_,
        vapply(event_date, is_heating_date, logical(1)) ~ "heating",
        TRUE ~ "non_heating"
      )
    )
}

add_covid_major_wave_flag <- function(df, date_var = EVENT_DATE_VAR, out_var = COVID_WAVE_VAR) {
  if (!date_var %in% names(df)) stop(paste0("缺少日期列: ", date_var))
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

get_vcov_matrix <- function(fit, cluster_vec = NULL) {
  vv <- NULL
  if (!is.null(cluster_vec) && requireNamespace("sandwich", quietly = TRUE)) {
    vv <- tryCatch(sandwich::vcovCL(fit, cluster = cluster_vec), error = function(e) NULL)
  }
  if (is.null(vv)) vv <- tryCatch(vcov(fit), error = function(e) NULL)
  vv
}

extract_beta_se <- function(fit, coef_name, cluster_vec = NULL) {
  beta <- tryCatch(as.numeric(coef(fit)[[coef_name]]), error = function(e) NA_real_)
  vv <- get_vcov_matrix(fit, cluster_vec)

  if (!is.finite(beta) || is.null(vv) || !(coef_name %in% rownames(vv))) {
    return(list(ok = FALSE, beta = NA_real_, se = NA_real_))
  }

  se <- sqrt(as.numeric(vv[coef_name, coef_name]))
  if (!is.finite(se) || se <= 0) {
    return(list(ok = FALSE, beta = beta, se = se))
  }

  list(ok = TRUE, beta = beta, se = se)
}

wald_contrast_two_coefs <- function(fit, coef1, coef2, cluster_vec = NULL) {
  vv <- get_vcov_matrix(fit, cluster_vec)
  cf <- tryCatch(coef(fit), error = function(e) NULL)

  if (is.null(cf) || is.null(vv)) {
    return(list(ok = FALSE, reason = "coef or vcov unavailable"))
  }
  if (!(coef1 %in% names(cf)) || !(coef2 %in% names(cf))) {
    return(list(ok = FALSE, reason = "coefficient not found"))
  }
  if (!(coef1 %in% rownames(vv)) || !(coef2 %in% rownames(vv))) {
    return(list(ok = FALSE, reason = "coefficient not found in vcov"))
  }

  b1 <- as.numeric(cf[[coef1]])
  b2 <- as.numeric(cf[[coef2]])
  v11 <- as.numeric(vv[coef1, coef1])
  v22 <- as.numeric(vv[coef2, coef2])
  v12 <- as.numeric(vv[coef1, coef2])

  diff_beta <- b1 - b2
  diff_var <- v11 + v22 - 2 * v12

  if (!is.finite(diff_var) || diff_var <= 0) {
    return(list(ok = FALSE, reason = "invalid diff variance"))
  }

  diff_se <- sqrt(diff_var)
  z <- diff_beta / diff_se
  p <- 2 * (1 - pnorm(abs(z)))

  list(
    ok = TRUE,
    beta_diff = diff_beta,
    se_diff = diff_se,
    z = z,
    p_value = p
  )
}

format_p <- function(p) {
  case_when(
    is.na(p) ~ NA_character_,
    p < 0.001 ~ "P<0.001",
    TRUE ~ paste0("P=", sprintf("%.3f", p))
  )
}

run_h1n1_h3n2_lag2 <- function(df, subset_tag,
                               strata_var = STRATA_VAR,
                               outcome_var = OUTCOME_VAR) {

  cluster_var <- get_cluster_var(df, CLUSTER_CANDIDATES)

  need <- c(
    outcome_var, strata_var,
    EXPOSURE_H1, EXPOSURE_H3,
    FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL,
    "holiday",
    if (RUN_COVID_WAVE_ADJUST) COVID_WAVE_VAR else NULL,
    if (!is.null(cluster_var)) cluster_var else NULL
  )

  required <- c(outcome_var, strata_var, EXPOSURE_H1, EXPOSURE_H3, FLU_TEMP_AVG_COL, FLU_RHUM_AVG_COL, "holiday")
  if (!all(required %in% names(df))) {
    stop("缺少 H1N1/H3N2 分析所需列。")
  }

  d <- df %>%
    select(all_of(intersect(need, names(df)))) %>%
    transmute(
      outcome = as.numeric(.data[[outcome_var]]),
      strata  = as.character(.data[[strata_var]]),
      h1 = suppressWarnings(as.numeric(.data[[EXPOSURE_H1]])),
      h3 = suppressWarnings(as.numeric(.data[[EXPOSURE_H3]])),
      temp_02 = suppressWarnings(as.numeric(.data[[FLU_TEMP_AVG_COL]])),
      rhum_02 = suppressWarnings(as.numeric(.data[[FLU_RHUM_AVG_COL]])),
      holiday2 = as.numeric(.data[["holiday"]]),
      covid_wave2 = if (RUN_COVID_WAVE_ADJUST && COVID_WAVE_VAR %in% names(.)) {
        suppressWarnings(as.numeric(.data[[COVID_WAVE_VAR]]))
      } else NA_real_,
      cluster = if (!is.null(cluster_var)) as.character(.data[[cluster_var]]) else NA_character_
    ) %>%
    filter(
      !is.na(outcome), !is.na(strata),
      safe_is_finite(h1), safe_is_finite(h3),
      safe_is_finite(temp_02), safe_is_finite(rhum_02),
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
    stop(paste0("子集 ", subset_tag, " 有效 strata 过少。"))
  }

  d <- d %>% filter(strata %in% valid_strata)

  fml <- as.formula(
    paste0(
      "outcome ~ h1 + h3 + ",
      "ns(temp_02, df = ", FLU_TEMP_DF, ") + ",
      "ns(rhum_02, df = ", FLU_RHUM_DF, ") + ",
      "holiday2",
      if (RUN_COVID_WAVE_ADJUST) " + covid_wave2" else "",
      " + strata(strata)"
    )
  )

  fit <- tryCatch(clogit(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) stop(paste0("子集 ", subset_tag, " clogit 拟合失败。"))

  h1_info <- extract_beta_se(fit, "h1", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
  h3_info <- extract_beta_se(fit, "h3", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)
  diff_info <- wald_contrast_two_coefs(fit, "h1", "h3", cluster_vec = if (!is.null(cluster_var)) d$cluster else NULL)

  if (!isTRUE(h1_info$ok) || !isTRUE(h3_info$ok) || !isTRUE(diff_info$ok)) {
    stop(paste0("子集 ", subset_tag, " 系数提取或 contrast 失败。"))
  }

  h1_or  <- exp(h1_info$beta * SCALE_VALUE)
  h1_low <- exp((h1_info$beta - 1.96 * h1_info$se) * SCALE_VALUE)
  h1_high <- exp((h1_info$beta + 1.96 * h1_info$se) * SCALE_VALUE)

  h3_or  <- exp(h3_info$beta * SCALE_VALUE)
  h3_low <- exp((h3_info$beta - 1.96 * h3_info$se) * SCALE_VALUE)
  h3_high <- exp((h3_info$beta + 1.96 * h3_info$se) * SCALE_VALUE)

  ror  <- exp(diff_info$beta_diff * SCALE_VALUE)
  ror_low <- exp((diff_info$beta_diff - 1.96 * diff_info$se_diff) * SCALE_VALUE)
  ror_high <- exp((diff_info$beta_diff + 1.96 * diff_info$se_diff) * SCALE_VALUE)

  out <- tibble(
    subset = subset_tag,
    exposure_window = "lag2",
    scale_label = SCALE_LABEL,

    h1_label = add_var_label(BASE_H1),
    h3_label = add_var_label(BASE_H3),

    h1_beta = h1_info$beta,
    h1_se = h1_info$se,
    h1_or = h1_or,
    h1_ci_low = h1_low,
    h1_ci_high = h1_high,

    h3_beta = h3_info$beta,
    h3_se = h3_info$se,
    h3_or = h3_or,
    h3_ci_low = h3_low,
    h3_ci_high = h3_high,

    beta_diff_h1_minus_h3 = diff_info$beta_diff,
    se_diff = diff_info$se_diff,
    z_value = diff_info$z,
    p_value = diff_info$p_value,
    p_label = format_p(diff_info$p_value),

    ror_h1_vs_h3 = ror,
    ror_ci_low = ror_low,
    ror_ci_high = ror_high,

    interpretation = case_when(
      diff_info$p_value < 0.05 & ror > 1 ~ "A(H1N1)pdm09 stronger",
      diff_info$p_value < 0.05 & ror < 1 ~ "A(H3N2) stronger",
      TRUE ~ "No significant difference"
    ),

    adjust_vars = paste0(
      "ns(", FLU_TEMP_AVG_COL, ",", FLU_TEMP_DF, ") + ",
      "ns(", FLU_RHUM_AVG_COL, ",", FLU_RHUM_DF, ") + public_holiday",
      if (RUN_COVID_WAVE_ADJUST) " + covid_major_wave" else ""
    ),

    n_cases = sum(d$outcome == 1),
    n_controls = sum(d$outcome == 0),
    n_strata = length(valid_strata)
  )

  out
}


cat("1) 读取数据...\n")
cat("当前策略文件: ", data_path, "\n")

df <- read_csv(data_path, locale = locale(encoding = "UTF-8"), show_col_types = FALSE)
cat("数据维度: ", nrow(df), " x ", ncol(df), "\n")

stopifnot(OUTCOME_VAR %in% names(df))
stopifnot(STRATA_VAR %in% names(df))
stopifnot(EVENT_DATE_VAR %in% names(df))

df <- add_heating_flag(df, event_date_var = EVENT_DATE_VAR)

if (RUN_COVID_WAVE_ADJUST) {
  df <- add_covid_major_wave_flag(df, date_var = EVENT_DATE_VAR, out_var = COVID_WAVE_VAR)
}

df <- normalize_calendar_covariates(df)

cat("供暖季分布:\n")
print(table(df$heating_season, useNA = "ifany"))

if (RUN_COVID_WAVE_ADJUST) {
  cat("COVID大流行期分布:\n")
  print(table(df[[COVID_WAVE_VAR]], useNA = "ifany"))
}

result_list <- list()

result_list[["all"]] <- run_h1n1_h3n2_lag2(df, subset_tag = "all")

if (isTRUE(RUN_HEATING_STRATIFIED)) {
  for (ss in c("heating", "non_heating")) {
    cat("\n----------------------------------\n")
    cat("准备分析子集: ", ss, "\n")
    cat("----------------------------------\n")

    df_ss <- df %>% filter(heating_season == ss)

    cat("记录数: ", nrow(df_ss), "\n")
    cat("病例数: ", sum(df_ss[[OUTCOME_VAR]] == 1, na.rm = TRUE), "\n")
    cat("对照数: ", sum(df_ss[[OUTCOME_VAR]] == 0, na.rm = TRUE), "\n")

    if (nrow(df_ss) == 0) {
      warning(paste0("子集 ", ss, " 无数据，跳过。"))
      next
    }

    result_list[[ss]] <- run_h1n1_h3n2_lag2(df_ss, subset_tag = ss)
  }
}

summary_df <- bind_rows(result_list) %>%
  mutate(
    subset = factor(subset, levels = c("all", "heating", "non_heating"))
  )

supp_table <- summary_df %>%
  mutate(
    subset_label = case_when(
      subset == "all" ~ "Overall",
      subset == "heating" ~ "Heating season",
      subset == "non_heating" ~ "Non-heating season",
      TRUE ~ as.character(subset)
    )
  ) %>%
  select(
    subset_label,
    exposure_window,
    h1_label, h1_or, h1_ci_low, h1_ci_high,
    h3_label, h3_or, h3_ci_low, h3_ci_high,
    ror_h1_vs_h3, ror_ci_low, ror_ci_high,
    p_value, p_label, interpretation,
    n_cases, n_controls, n_strata,
    adjust_vars
  )

write.csv(
  supp_table,
  file.path(output_dir, "H1N1_vs_H3N2_lag2_正式差异检验_汇总表.csv"),
  row.names = FALSE
)

supp_table_min <- summary_df %>%
  transmute(
    Subset = case_when(
      subset == "all" ~ "Overall",
      subset == "heating" ~ "Heating season",
      subset == "non_heating" ~ "Non-heating season",
      TRUE ~ as.character(subset)
    ),
    `Exposure window` = exposure_window,
    `OR for A(H1N1)pdm09` = sprintf("%.2f (%.2f–%.2f)", h1_or, h1_ci_low, h1_ci_high),
    `OR for A(H3N2)` = sprintf("%.2f (%.2f–%.2f)", h3_or, h3_ci_low, h3_ci_high),
    `ROR for H1N1 vs H3N2` = sprintf("%.2f (%.2f–%.2f)", ror_h1_vs_h3, ror_ci_low, ror_ci_high),
    `Wald test` = p_label,
    Interpretation = interpretation
  )

write.csv(
  supp_table_min,
  file.path(output_dir, "H1N1_vs_H3N2_lag2_正式差异检验_极简表.csv"),
  row.names = FALSE
)

report <- c(
  "=== Final publication-ready evidence for H1N1 vs H3N2 contrast ===",
  paste("生成日期:", as.character(Sys.Date())),
  paste("Control strategy:", CONTROL_STRATEGY),
  paste("数据文件:", data_path),
  paste("输出目录:", output_dir),
  "",
  "分析目标：",
  "仅保留与正文关键句直接对应的证据链：",
  "\"Wald 差异检验显示，在供暖期 lag 2 暴露窗口下，A(H1N1)pdm09 与 AECOPD 的关联显著强于 A(H3N2)\"",
  "",
  "模型形式：",
  paste0(
    "outcome ~ A_H1N1占比_lag2 + A_H3N2占比_lag2 + ns(",
    FLU_TEMP_AVG_COL, ",", FLU_TEMP_DF, ") + ns(",
    FLU_RHUM_AVG_COL, ",", FLU_RHUM_DF, ") + public_holiday",
    if (RUN_COVID_WAVE_ADJUST) " + covid_major_wave" else "",
    " + strata(match_id)"
  ),
  "",
  "核心输出文件：",
  "1) H1N1_vs_H3N2_lag2_正式差异检验_汇总表.csv",
  "2) H1N1_vs_H3N2_lag2_正式差异检验_极简表.csv"
)

writeLines(report, file.path(output_dir, "README_final_H1N1_vs_H3N2_lag2.txt"))

cat("\n全部完成。\n")
cat("总输出目录: ", output_dir, "\n")
cat("重点文件：\n")
cat(" - H1N1_vs_H3N2_lag2_正式差异检验_极简表.csv\n")
