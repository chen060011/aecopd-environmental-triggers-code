packages <- c(
  "tidyverse",
  "survival",
  "dlnm",
  "splines",
  "sandwich"
)
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing)
