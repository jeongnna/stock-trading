# ---
# Input file:
#   stock_data.csv
#   stock_name.csv
#   kospi_list.xls
#   kosdaq_list.xls
#   kospi_index.csv
#   kosdaq_index.csv
#
# Output file:
# ---


library(tidyverse)
library(data.table)
library(readxl)


# Load stock data
stock_df <- fread("../data/stock_data.csv")
stock_name <- fread("../data/stock_name.csv")

stock_df <-
    stock_df %>%
    select(-name) %>%
    left_join(stock_name, by="code")


# Load market index
kospi <- fread("../data/kospi_index.csv")
kosdaq <- fread("../data/kosdaq_index.csv")

kospi <- na.omit(kospi)
kosdaq <- na.omit(kosdaq)


# Load market item info
kospi_list <- read_excel("../data/kospi_list.xls")
kosdaq_list <- read_excel("../data/kosdaq_list.xls")

kospi_list$code <- paste0("A", kospi_list$code)
kosdaq_list$code <- paste0("A", kosdaq_list$code)


# Create logreturn feature
stock_df$logreturn <- c(NA, diff(log(stock_df$closing)))
kospi$logreturn <- c(NA, diff(log(kospi$closing)))
kosdaq$logreturn <- c(NA, diff(log(kosdaq$closing)))


# Create stock info data
stock_info <-
    stock_df %>%
    group_by(code, name) %>%
    tally()

stock_info$market <- "none"
stock_info$market[stock_info$code %in% kospi_list$code] <- "kospi"
stock_info$market[stock_info$code %in% kosdaq_list$code] <- "kosdaq"

in_market <- stock_info$code[stock_info$market != "none"]
stock_df <- stock_df %>% filter(code %in% in_market)
stock_info <- stock_info %>% filter(code %in% in_market)


# Select full obs data
stock_info <- stock_info %>% filter(n == 2075)
stock_df <- stock_df %>% filter(code %in% stock_info$code)


# Identify all stocks have identical timeset
nstock <- nrow(stock_info)
timeset <- stock_df$time[stock_df$code == stock_info$code[1]]
bool <- TRUE # initialize bool

for (i in 2:nstock) {
    bool <- bool * identical(timeset, stock_df$time[stock_df$code == stock_info$code[i]])
    if (!bool) stop("discoverd inconsistent timeset.")
}


# Adjust and apply timeset
timeset <-
    timeset %>%
    intersect(kospi$time) %>%
    intersect(kosdaq$time) # warning: set operation returns the unclassed object

timeset <- timeset[-1] # logreturn in the 1st row is NA.

stock_df <- stock_df %>% filter(time %in% timeset)
kospi <- kospi %>% filter(time %in% timeset)
kosdaq <- kosdaq %>% filter(time %in% timeset)

timeset <- as.Date(timeset, origin="1970-01-01")


# Create logreturn matrix
#   - dim of matrix is (397, 2066)
#   - rows are each stock
#   - columns are each time point
nobs <- length(timeset)
logret <- matrix(nrow=nstock, ncol=nobs) # initialize logret

for (i in 1:nstock) {
    wb <- 1 + (i-1) * nobs
    we <- wb + nobs - 1
    logret[i, ] <- stock_df$logreturn[wb:we]
}

kospi <- kospi$logreturn
kosdaq <- kosdaq$logreturn


# Set up index of training, validation and test sets
test_idx <- which(year(timeset) >= 2018)
train_idx <- setdiff(1:nobs, test_idx)
val_idx <- intersect(which(year(timeset) >= 2016), train_idx)
tune_idx <- setdiff(train_idx, val_idx)
