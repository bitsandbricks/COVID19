#' COVID19DataProcessor
#' @importFrom R6 R6Class
#' @import magrittr
#' @import lubridate
#' @import ggplot2
#' @export
COVID19DataProcessor <- R6Class("COVID19DataProcessor",
  public = list(
   # parameters
   top.countries.count = 11,
   force.download = FALSE,
   filenames = NA,
   data.confirmed = NA,
   data.deaths    = NA,
   data.recovered = NA,
   data.confirmed.original = NA,
   data.deaths.original    = NA,
   data.recovered.original = NA,
   # consolidated
   data.na        = NA,
   data           = NA,
   data.latest    = NA,
   top.countries  = NA,
   min.date = NA,
   max.date = NA,
   initialize = function(force.download = FALSE){
    self$force.download <- force.download
    self
   },
   generateReport = function(output.file, overwrite = FALSE){
    self$preprocess()
    self$generateTopCountriesGGplot()

    self$generateTex(output.file)

   },
   preprocess = function(){
    self$downloadData()
    self$loadData()
    n.col <- ncol(self$data.confirmed)
    ## get dates from column names
    dates <- names(self$data.confirmed)[5:n.col] %>% substr(2,8) %>% mdy()
    range(dates)

    self$cleanData()

    nrow(self$data.confirmed)
    self$consolidate()
    nrow(self$data)
    max(self$data$date)

    self$calculateRates()
    nrow(self$data)

    # TODO imputation. By now remove rows with no confirmed data
    self$makeImputations()

    self$calculateTopCountries()
    self
   },
   downloadData = function(){
    self$filenames <- c('time_series_19-covid-Confirmed.csv',
                        'time_series_19-covid-Deaths.csv',
                        'time_series_19-covid-Recovered.csv')
    # url.path <- 'https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_'
    #url.path <- "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/tree/master/csse_covid_19_data/csse_covid_19_time_series"
    url.path <- "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/"
    bin <- lapply(self$filenames, FUN = function(...){downloadCOVID19(url.path = url.path, force = self$force.download, ...)})
   },
   loadData = function(){
    ## load data into R
    self$data.confirmed <- read.csv(file.path(data.dir, 'time_series_19-covid-Confirmed.csv'))
    self$data.deaths <- read.csv(file.path(data.dir,'time_series_19-covid-Deaths.csv'))
    self$data.recovered <- read.csv(file.path(data.dir,'time_series_19-covid-Recovered.csv'))

    dim(self$data.confirmed)
    ## [1] 347 53
    self
   },
   cleanData = function(){
    self$data.confirmed.original <- self$data.confirmed
    self$data.deaths.original    <- self$data.deaths
    self$data.recovered.original <- self$data.recovered
    self$data.confirmed <- self$data.confirmed %<>% cleanData() %>% rename(confirmed=count)
    self$data.deaths    <- self$data.deaths %<>% cleanData() %>% rename(deaths=count)
    self$data.recovered <- self$data.recovered %<>% cleanData() %>% rename(recovered=count)
    self
   },
   consolidate = function(){
    ## merge above 3 datasets into one, by country and date
    self$data <- self$data.confirmed %>% merge(self$data.deaths) %>% merge(self$data.recovered)
    self$data.na <- self$data %>% filter(is.na(confirmed))
    #self$data <- self$data %>% filter(is.na(confirmed))
    self$min.date <- min(self$data$date)
    self$max.date <- max(self$data$date)
    self$data
   },
   makeImputations = function(){
    # TODO imputation. By now remove rows with no confirmed data
    nrow(self$data)
    self$data <- self$data[!is.na(self$data$confirmed),]
    nrow(self$data)
   },
   makeImputationsNew = function(){
    stop("Under construction")
    rows.imputation <- which(is.na(self$data$confirmed) & self$data$date == self$max.date)
    self$data[rows.imputation,]
    #data.imputation <- self$data.na %>% filter(date == self$max.date)
    for (i in rows.imputation){
     #debug
     print(i)

     country.imputation <- self$data[i,]
     last.country.data <- country.imputation

     country.imputation <<- country.imputation
     i <<- i
     last.country.data <<- last.country.data

     while(is.na(last.country.data$confirmed)){
      last.country.data <- self$data %>% filter(country == country.imputation$country & date == self$max.date-1)
     }
     if (last.country.data$confirmed < 100){
      confirmed.imputation <- last.country.data$confirmed
      recovered.imputation <- last.country.data$recovered
      deaths.imputation    <- last.country.data$deaths
     }
     else{
      self$data %<>% filter(confirmed > 100) %>% mutate(dif = abs(log(confirmed/last.country.data$confirmed)))
      similar.trajectories <- self$data %>% filter(confirmed > 100) %>% filter(dif < log(1.3)) #%>% select(confirmed, dif)
      #similar.trajectories %>% filter(is.na(rate.inc.daily))

      summary((similar.trajectories %>%
                filter(is.finite(rate.inc.daily)))$rate.inc.daily)

      trajectories.agg <-
       similar.trajectories %>%
       filter(is.finite(rate.inc.daily)) %>%
       summarize(mean = mean(rate.inc.daily),
                 mean.trim.3 = mean(rate.inc.daily, trim = 0.3),
                 cv   = sd(rate.inc.daily),
                 min  = min(rate.inc.daily),
                 max  = max(rate.inc.daily))

      confirmed.imputation <- last.country.data$confirmed *(1+trajectories.agg$mean.trim.3)
      recovered.imputation <- last.country.data$recovered
      deaths.imputation    <- last.country.data$deaths
     }
     self$data[i,]$confirmed  <- confirmed.imputation
     self$data[i,]$recovered  <- recovered.imputation
     self$data[i,]$deaths     <- deaths.imputation
    }
   },
   calculateRates = function(){
    ## sort by country and date
    self$data %<>% arrange(country, date)
    ## daily increases of deaths and cured cases
    ## set NA to the increases on day1
    n <- nrow(self$data)
    day1 <- min(self$data$date)
    self$data %<>% mutate(confirmed.inc = ifelse(date == day1, NA, confirmed - lag(confirmed, n=1)),
                          deaths.inc = ifelse(date == day1, NA, deaths - lag(deaths, n=1)),
                          recovered.inc = ifelse(date == day1, NA, recovered - lag(recovered, n=1)))
    ## death rate based on total deaths and cured cases
    self$data %<>% mutate(rate.upper = (100 * deaths / (deaths + recovered)) %>% round(1))
    ## lower bound: death rate based on total confirmed cases
    self$data %<>% mutate(rate.lower = (100 * deaths / confirmed) %>% round(1))
    ## death rate based on the number of death/cured on every single day
    self$data %<>% mutate(rate.daily = (100 * deaths.inc / (deaths.inc + recovered.inc)) %>% round(1))
    self$data %<>% mutate(rate.inc.daily = (confirmed.inc/(confirmed-confirmed.inc)) %>% round(2))

    self$data %<>% mutate(remaining.confirmed = (confirmed - deaths - recovered))
    names(self$data)
    self$data
   },
   calculateTopCountries = function(){
    self$data.latest <- self$data %>% filter(date == max(date)) %>%
     select(country, date, confirmed, deaths, recovered, remaining.confirmed) %>%
     mutate(ranking = dense_rank(desc(confirmed)))
    ## top 10 countries: 12 incl. 'World' and 'Others'
    self$top.countries <- self$data.latest %>% filter(ranking <= self$top.countries.count) %>%
     arrange(ranking) %>% pull(country) %>% as.character()

    self$top.countries

    ## move 'Others' to the end
    self$top.countries %<>% setdiff('Others') %>% c('Others')
    ## [1] "World" "Mainland China"
    ## [3] "Italy" "Iran (Islamic Republic of)"
    ## [5] "Republic of Korea" "France"
    ## [7] "Spain" "US"
    ## [9] "Germany" "Japan"
    ## [11] "Switzerland" "Others"
    self$top.countries
   }
))