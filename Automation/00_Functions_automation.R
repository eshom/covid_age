Sys.setenv(LANG = "en")
Sys.setlocale("LC_ALL","English")

### Dependency preamble #############################################

# install pacman to streamline further package installation
if(!require("pacman", character.only = TRUE)) {
  install.packages("pacman", dep = TRUE)
  if (!require("pacman", character.only = TRUE))
    stop("Package pacman not found")
}

library(pacman)

# Required CRAN packages
packages_CRAN <- c("tidyverse","lubridate","gargle","rvest","httr","readxl",
                   "tictoc","parallel","data.table","git2r","usethis", "rio",
                   "remotes","here","googledrive","zip", "XML", "RCurl",
                   "taskscheduleR","countrycode", "xml2", "dplyr", "xml2",
                   "reticulate")

# Install required CRAN packages if not available yet
if(!sum(!p_isinstalled(packages_CRAN))==0) {
  p_install(
    package = packages_CRAN[!p_isinstalled(packages_CRAN)], 
    character.only = TRUE
  )
}

# Reuired github packages
packages_git <- c("googlesheets4")

# install from github if necessary
if (!p_isinstalled("googlesheets4")) {
  library(remotes)
  install_github("tidyverse/googlesheets4")
}

# Load the required CRAN/github packages
p_load(packages_CRAN, character.only = TRUE)
p_load(packages_git, character.only = TRUE)


### Functions for automate collection ####
##########################################

### get_input_rubric()
# Get overview spreadsheet with input data sources
# @param tab character, which sheet to get
get_input_rubric <- function(tab = "input") {
  
  # Spreadsheet on Google Docs
  ss_rubric <- "https://docs.google.com/spreadsheets/d/15kat5Qddi11WhUPBW3Kj3faAmhuWkgtQzioaHvAGZI0/edit#gid=0"
  
  # Read spreadsheet
  input_rubric <- read_sheet(ss_rubric, sheet = tab) %>% 
    # Drop if no source spreadsheet
    filter(!is.na(Sheet))
  
  # Return tibble
  input_rubric
  
}


### get_country_inputDB()
# Load just a single country
# @param ShortCode character specifying country to load

get_country_inputDB <- function(ShortCode) {
  
  # Get spreadsheet
  rubric <- get_input_rubric(tab = "input")
  
  # Find spreadsheet for country
  # TR: this assumes everthing on Drive. 
  ss_i   <- rubric %>% filter(Short == ShortCode) %>% '$'(Sheet)
  
  # Load spreadsheet
  out <- read_sheet(ss_i, 
                    sheet = "database", 
                    na = "NA", 
                    col_types= "cccccciccd")
  
  # Assign short code
  out$Short <- add_Short(out$Code,out$Date)
  
  # Output
  out
  
}

log_update <- function(pp, N){
  ss <- "https://docs.google.com/spreadsheets/d/1ftqFwX_Z29OrXxH9HnQWo31ApoEpxSqYOJspnIUAUbk/edit#gid=0"
  log_this <- tibble(pp = pp, Date = lubridate::today(), rows = N)
  sheet_append(log_this, ss = ss, sheet = "log")
}


# Functions inherited from EA, modifed by TR and EA

# @param pp base name of script (needs to be inside Automation/00_hydra/)
# @param tm what time should it be run at?
# @param email gmail account with permissions and local PAT set up
# @param wd repo base path.
sched <- function(
  pp = "Germany", 
  tm = "21:18", 
  email = "kikepaila@gmail.com",
  sch = "DAILY",
  wd = here()){
  
  # create a trigger script that will source the automate script
  # using encoding utf-8 
  
  # name of trigger script
  trigger_script <- here("Automation",
                         "00_hydra", 
                         "triggers", 
                         paste0(pp, "_trigger.R")  )
  
  # code within the trigger script
  script <- paste0('email <- "', email, '"\n',
                  'setwd("', wd, '")\n',
                  'source("Automation/00_hydra/', pp, 
                  '.R", encoding="utf-8")')
  
  # generate the trigger script
  writeLines(script, trigger_script)
  
  # schedule the trigger script
  tskname <- paste0("coverage_db_", pp, "_daily")
  
  # delete first any precedent task with that name
  try(taskscheduler_delete(taskname = tskname))
  
  # adjust time
  st <- Sys.time()
  hr <- lubridate::hour(st)
  mn <- lubridate::minute(st)
  st.in <- hr + mn / 60
  
  tm.in <- strsplit(tm,split=":") %>% unlist() %>% as.integer()
  tm.in.dec <- tm.in[1] + tm.in[2] / 60
  
  if (tm.in.dec < st.in){
    date.sched <- format((today() + 1), "%m/%d/%Y") 
  } else {
    date.sched <- format(today(), "%m/%d/%Y") 
  }
  
  taskscheduler_create(taskname = tskname, 
                       rscript = trigger_script, 
                       schedule = sch, 
                       starttime = tm, 
                       startdate = date.sched)
}
# remove a scheduled task
# @param pp script base name
delete_sched <- function(pp = "Germany"){
  tskname <- paste0("coverage_db_", pp, "_daily")
  taskscheduler_delete(taskname = tskname)
}



### Functions for editing data ######################################

### sort_input_data()
# Sorts input data nicely
# @param X 

sort_input_data <- function(X) {
  
  X %>% 
    # Date to DDMMYYYY
    mutate(Date2 = dmy(Date)) %>% 
    # Sort data
    arrange(Country,
            Region,
            Date2,
            Code,
            Sex, 
            Measure,
            Metric,
            suppressWarnings(as.integer(Age))) %>% 
    # Drop extra date variable
    select(-Date2)
  
}

### add_short()
# Create short labels from long labels
# @param Code Character vector of long labels
# @param Date Vector of dates

add_Short <- function(Code, Date) {
  
  # Apply elementwise
  mapply(function(Code, Date){
    
    # Remove date
    Short <- gsub(pattern = Date, replacement = "", Code)
    
    # Remove last character if not a letter
    last_char <- str_sub(Short,-1)
    if (last_char %in% c("\\.","_","-")){
      Short <- substr(Short,1,nchar(Short)-1)
    }
    
    # Return short label
    Short
    
  }, Code, Date)
  
}

# function to extract data from web 
##################################

scraplinks <- function(url){
  # Create an html document from the url
  webpage <- xml2::read_html(url)
  # Extract the URLs
  url_ <- webpage %>%
    rvest::html_nodes("a") %>%
    rvest::html_attr("href")
  # Extract the link text
  link_ <- webpage %>%
    rvest::html_nodes("a") %>%
    rvest::html_text()
  return(tibble(link = link_, url = url_))
}

# useful for automated capture
ddmmyyyy <- function(Date,sep = "."){
  paste(sprintf("%02d",day(Date)),
        sprintf("%02d",month(Date)),  
        year(Date),sep=sep)
}


