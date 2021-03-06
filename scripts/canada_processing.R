# ==============================================================================
# THIS FILE GETS AND PROCESSES CANADA CENSUS DATA ON VISIBLE MINORITIES
# ==============================================================================

can_dir <- "Canada Data"
if (!file.exists(can_dir)) {
    dir.create(can_dir)
}

library(dplyr)
library(stringr)
library(tidyr)
library(readr)
library(data.table)

#------------------------------------------------------------------------------
# MAP FROM STATISTICS CANADA VISIBLE MINORITIES TO 5-CLASS VISIBLE MINORITIES
#------------------------------------------------------------------------------

# Create lookup table for sub-groups and groups
# Combine East Asian and White/Arab groups for summary purposes
minorities <- c("South Asian", "Chinese", "Black", "Filipino",
                   "Latin American", "Arab", "Southeast Asian",
                   "West Asian", "Korean", "Japanese",
                   "Visible minority, n.i.e.", "Multiple visible minorities",
                   "Not a visible minority")
minorities_to_groups <- c("South Asian", "East Asian", "Black", "East Asian",
                          "Other", "White", "East Asian",
                          "Other", "East Asian", "East Asian",
                          "Other", "Other",
                          "White")
groups <- data.table(Description = minorities, Group = minorities_to_groups)

#------------------------------------------------------------------------------
# GET AND CLEAN CANADIAN DATA (n.b. Toronto is a Metro in this data set)
#------------------------------------------------------------------------------

# Data files are available only via manual download from the following URL:
# http://www12.statcan.gc.ca/nhs-enm/2011/dp-pd/prof/details/download-telecharger/comprehensive/comp-csv-tab-nhs-enm.cfm?Lang=E
can_census_zip <- paste(can_dir, "99-004-XWE2011001-401_CSV.ZIP", sep = "/")
can_census_dir <- paste(can_dir, "99-004-XWE2011001-401_CSV", sep = "/")

if (!file.exists(can_census_dir)) {
    stop("Error: The directory with Canadian census data must be in the
             Canada Data directory in the working directory.")
}

# Helper function to load and clean the data for one province
province_classes <- rep("character", 14)
my_load_data <- function(filename) {
    province_data <- fread(filename, colClasses = province_classes) %>%
        filter(Topic == "Visible minority population") %>%
        select(Geo_Code, CMA_CA_Name, Characteristic, Total) %>%
        rename(Tract = Geo_Code, Metro_Name = CMA_CA_Name,
               Description = Characteristic, Population = Total) %>%
        mutate(Population = as.numeric(Population)) %>%
        mutate(Metro = as.numeric(substr(Tract, 1, 3))) %>%
        mutate(Description = factor(str_trim(Description)))

    return(province_data)
}

fileNames <- list.files(can_census_dir, pattern="*.csv", full.names=TRUE)
can_data <- lapply(fileNames, my_load_data) %>%
    bind_rows()

# Check for missing data values
if (all(colSums(is.na(can_data)) != 0)) {
    warning("Warning: Canada data has missing values.")
}

# Subset largest Metro's, down to a population of about 500K
top_cma_codes <- can_data %>%
    group_by(Metro) %>%
    summarize(Cma_Population = sum(Population)) %>%
    select(Metro, Cma_Population) %>%
    ungroup() %>%
    top_n(10, Cma_Population)
can_data_3 <- can_data %>%
    filter(Metro %in% top_cma_codes$Metro)

# Correct for encoding limitations in fread and read_csv
# Also trim hyphenated names for display purposes
montreal_data <- filter(can_data_3, Metro == 462) %>%
    mutate(Metro_Name = "Montreal")
quebec_data <- filter(can_data_3, Metro == 421) %>%
    mutate(Metro_Name = "Quebec")
other_data <- filter(can_data_3, (Metro != 462) & (Metro != 421)) %>%
    mutate(Metro_Name = sub(" [[:punct:]] [[:alpha:]]* *[[:punct:]]* *[[:alpha:]]*$", "",
                          Metro_Name))
can_data_4 <- bind_rows(montreal_data, quebec_data, other_data) %>%
    inner_join(groups, by = "Description") %>%
    select(-Description)

#------------------------------------------------------------------------------
# SAVE ANALYTIC DATA
#------------------------------------------------------------------------------

analytic_file <- "canada_processing.csv"
write.csv(can_data_4, analytic_file, row.names = FALSE)

cma_file <- "canada_cma.csv"
write.csv(top_cma_codes, cma_file, row.names = FALSE)