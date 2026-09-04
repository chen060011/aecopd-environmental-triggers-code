required <- c("tidyverse", "survival", "splines", "sandwich", "tsModel", "dlnm")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]

cran_missing <- setdiff(missing, "dlnm")
if (length(cran_missing)) {
  install.packages(cran_missing, repos = "https://cloud.r-project.org")
}

if (!requireNamespace("dlnm", quietly = TRUE)) {
  install.packages(
    "https://cran.r-project.org/src/contrib/Archive/dlnm/dlnm_2.4.7.tar.gz",
    repos = NULL,
    type = "source"
  )
}

still_missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(still_missing)) {
  stop("Missing R packages after installation: ", paste(still_missing, collapse = ", "))
}

cat("R package requirements satisfied. dlnm version:", as.character(packageVersion("dlnm")), "\n")
