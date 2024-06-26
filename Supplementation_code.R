##### load packages -----
library(dplyr)
library(brms)
library(rstan)
library(ggplot2)
library(bayestestR)
library(bayesplot)
library(tidybayes)
library(stats)
library(tidyr)

##### load data as CSV files -----
updated_comb <- read.csv("G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/SUPPLEMENTATION PAPER/Data sheets/updated_comb.csv")
updated_weight <- read.csv("G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/SUPPLEMENTATION PAPER/Data sheets/final_weight.csv")
# weight is actually mass
ivi_data <- read.csv("G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/R/FINAL clean provisioning data 2013-2019.csv")

##### combine data for body mass and survival spreadsheets-----

# join the two data frames together by a common column
# 1. weight and survival spreadsheets 
combined_data <- left_join(updated_comb, updated_weight, by = c("yearsite", "site", "year", "colour"))
# check: file has same number of observations as updated_comb, good, no issues 

#2. basic info about whats included in analysis 

# number of sites in each year 
sites_count_year <- combined_data %>% 
  group_by(year) %>% 
  summarise(sites_per_year = n_distinct(site))
print(sites_count_year)
# this is maximum number included. 2 are present in IVI data but missing here (both from 2016)
# and 19 are present here but not in the IVI data 

# number of supplemented nests in each year 
control_supplemented <- combined_data %>% 
  group_by(year) %>% 
  subset(treatment == 1) %>% 
  summarise(num_supp = n_distinct(site))
print(control_supplemented)

##### create weight at final measurement (assumed fledging) spreadsheet -----

# group the data by yearsite and colour of nestling, and find the maximum age for each group
max_ages <- combined_data %>%
  group_by(yearsite, colour) %>%
  summarize(max_age = max(age))

# join the maximum ages back to the combined data to filter for only the highest age measurements
assumed_fledge_data <- combined_data %>%
  left_join(max_ages, by = c("yearsite", "colour")) %>%
  filter(age == max_age) %>%
  select(-max_age) # remove max_age column (don't need it)
# this spreadsheet then also includes only the survival data recorded at the last recorded nest visit
# but for ALL nestlings, whether they survived or not 
# later i also create a spreadsheet for use in the body mass at fledging model which only has the weights of surviving nestlings


##### calculate number hatched (ie max brood size)
assumed_fledge_data <- assumed_fledge_data %>% 
  group_by(yearsite) %>% 
  mutate(number_hatched = n_distinct(colour)) 

##### calculate number fledged 
assumed_fledge_data <- assumed_fledge_data %>% 
  group_by(yearsite) %>% 
  mutate(number_fledged = sum(surv))

##### calculate nestling age in IVI spreadsheet -----
summary(ivi_data$julian2)
ivi_data$jhatchdate <- ivi_data$julian2-186

#Create julian for date in season for relevant dataset (2013-2017)

ivi_data <- subset(ivi_data, year != 2018 & year != 2019)


summary(ivi_data$jdate2)
ivi_data$dayinseason <- ivi_data$jdate2-186 #-186 not 187 to align with hatchdate

#Calculate nestling age

ivi_data$nestlingage <- ivi_data$dayinseason - ivi_data$jhatchdate
hist(ivi_data$nestlingage) #check distribution (confirm logical)
summary(ivi_data$nestlingage) #no problems 

##### set appropriate categorical variables -----

# 1. assumed_fledge_data sheet
assumed_fledge_data$fyear = as.factor(assumed_fledge_data$year)
assumed_fledge_data$ftreatment = as.factor(assumed_fledge_data$treatment) 
assumed_fledge_data$fpair = as.factor(assumed_fledge_data$yearsite)
assumed_fledge_data$fsite = as.factor(assumed_fledge_data$site)

#2. ivi_data sheet 
ivi_data$fyear = as.factor(ivi_data$year)
ivi_data$ftreatment = as.factor(ivi_data$supplimented)
ivi_data$fpair = as.factor(ivi_data$yearsite)
ivi_data$fsite = as.factor(ivi_data$site)

##### calculate & manipulate IVI -----

# Combine provisioning start date & time

ivi_data$DTstart <- as.POSIXct(as.character(paste(ivi_data$date, ivi_data$start)), 
                           format = "%d/%m/%Y %H:%M:%S")

# Calculate IVI

ivi_data <- (data=ivi_data) %>% 
  group_by (fpair) %>% 
  arrange(DTstart) %>% 
  mutate(IVI = ifelse(visit_type == "fail"| lag(visit_type == "fail"), NA, DTstart - lag(DTstart, default = first(DTstart)))) %>% 
  ungroup()

ivi_data$IVI <- ivi_data$IVI/60

# Limit dataset to first 12 days & exclude hatch day 0

ivi_data <- (data=ivi_data) %>%
  filter(ivi_data$nestlingage <=12) 
ivi_data <- (data=ivi_data) %>%
  filter(ivi_data$nestlingage >0)


# deal with camera fail lines 
# We removed NAs since these are generated by fails recorded either on the current or previous line

ivi_data <- (data=ivi_data) %>% 
  filter(!is.na (IVI))
summary(ivi_data$IVI)

# check for outliers in IVI

dotchart(ivi_data$IVI) # outliers seem obvious, remove obvious outliers 
# Longest IVI is 9296 minutes (6.5 days) which is obviously unrealistic. It is from 2015. 
# The 7 longest IVIs are from 2015 and 2016, assumed to be related to camera settings (see manuscript)

ivi_data <- (data=ivi_data) %>%
  filter(ivi_data$IVI <4000)
dotchart(ivi_data$IVI)


# log transform IVI
hist(ivi_data$IVI)
ivi_data$logIVI <- log(ivi_data$IVI)
hist(ivi_data$logIVI)

##### centering and scaling data -----

# setting scale=2 means that the variables are scaled by 2SD instead of the automatic 1
# scaling by 2SD so that continuous perdictors in my models can be directly compared to treatment effect 
# which has 2 levels (i.e., supplemented 1 and control 0)
#Gelman A, 2008. Scaling regression inputs by dividing by two standard deviations. Stat Med 27:2865-2873.

assumed_fledge_data$hatch_date_sc <- scale(assumed_fledge_data$hatch_date_in_july, scale = 2)
assumed_fledge_data$brood_size_sc <- scale(assumed_fledge_data$number_fledged, scale = 2)
assumed_fledge_data$age_sc <- scale(assumed_fledge_data$age, scale = 2)
assumed_fledge_data$number_hatched_sc <- scale(assumed_fledge_data$number_hatched, scale = 2)

ivi_data$brood_size_sc <- scale(ivi_data$chicks, scale = 2)
ivi_data$hatch_date_sc <- scale(ivi_data$jhatchdate, scale = 2)
ivi_data$age_sc <- scale(ivi_data$nestlingage, scale = 2)

##### other manipulations needed for models -----
# determine the min and max ages at which final measurements were taken only for surviving nestlings i.e., age of assumed fledging 
# this will be used in the body mass at fledging model 
# for this we only want the fledge data i.e., the weights of the nestlings which survived until assumed fledging
# in the assumed_fledge_data spreadsheet we have all of the last weight measurements taken for each nestling colour
# so i need to filter this to only have the final weight for surviving nestlings 

filtered_assumed_fledge <- subset(assumed_fledge_data,surv ==1)
filtered_assumed_fledge <- subset(filtered_assumed_fledge, select = -age_at_death)
# range is now 21-35 days at final weight measurement for surviving nestlings 
# during this time growth is roughly linear, based on Eriks thesis figures, so dont need to remove any points as outliers 


##### Comparing datasets between fledge data and ivi data -----

# Count unique sites within years in ivi_data
ivi_unique_sites <- ivi_data %>%
  group_by(year) %>%
  summarise(unique_sites = n_distinct(site))

# Count unique sites within years in assumed_fledge_data
fledge_unique_sites <- assumed_fledge_data %>%
  group_by(year) %>%
  summarise(unique_sites = n_distinct(site))

# Print the results
print("ivi_data:")
print(ivi_unique_sites)

print("assumed_fledge_data:")
print(fledge_unique_sites)

# Get unique sites within years in ivi_data
ivi_unique_sites <- ivi_data %>%
  group_by(year) %>%
  distinct(site) %>%
  ungroup()

# Get unique sites within years in assumed_fledge_data
fledge_unique_sites <- assumed_fledge_data %>%
  group_by(year) %>%
  distinct(site) %>%
  ungroup()

# Find sites in assumed_fledge_data not present in ivi_data
sites_not_in_ivi_data <- fledge_unique_sites %>%
  anti_join(ivi_unique_sites, by = c("year", "site"))


# Find sites in ivi_data not present in assumed_fledge_data
sites_not_in_fledge_data <- ivi_unique_sites %>%
  anti_join(fledge_unique_sites, by = c("year", "site"))

# Print the results
print(sites_not_in_ivi_data)
print(sites_not_in_fledge_data)

##### models confirming no treatment related differences -----

# checking for treatment related differences prior to treatment 
# this is to confirm that the randomisation of supplemented nests was successful 

## 1. treatment related differences in hatch date 

# need only data for first hatched nestling of each pair (ie year specific site)
first_hatch_only <- assumed_fledge_data %>% 
  group_by(fpair) %>% 
  filter(hatch_date_in_july == min(hatch_date_in_july))

# use first hatched spreadsheet to check for treatment related differences 
hatch_date_test <- brm(hatch_date_in_july ~ ftreatment + (1|fsite) + (1|fyear), 
                       data = first_hatch_only, 
                       family = gaussian(), 
                       warmup = 1000, 
                       iter = 6000, 
                       chains = 3, 
                       cores = parallel::detectCores(), 
                       control = list(adapt_delta = 0.99, max_treedepth = 15), 
                       backend = "cmdstanr")
summary(hatch_date_test)
fixef(hatch_date_test)
# conc: no treatment related differences in hatch date of first nestling 

# p-map
p_map(hatch_date_test, null=0, precision=2^10, method="kernel", effects= c("fixed"), component= c("all"))# 0.652
p_direction(hatch_date_test)
#Probability of Direction 

#Parameter   |     pd
#(Intercept) |   100%
#ftreatment1 | 83.23%


## 2. treatment related differences in number of nestlings hatched 

# checking this since supplementation didnt begin until 5 days post hatch
# so shouldnt be any differences between supplemented and control assigned nests prior to treatment 
# if assignment of treatment/control was random 

number_hatched_test <- brm(number_hatched ~ ftreatment + (1|fsite) + (1|fyear), 
                           data = first_hatch_only, 
                           family = poisson(), # note poisson distribution used 
                           warmup = 3000, 
                           iter = 6000, 
                           chains = 4, 
                           cores = parallel::detectCores(), 
                           control = list(adapt_delta = 0.99, max_treedepth = 20), 
                           backend = "cmdstanr")
summary(number_hatched_test)
fixef(number_hatched_test)
# conc: no treatment related differences in number of nestlings hatched 

# p-map
p_map(number_hatched_test, null=0, precision=2^10, method="kernel", effects= c("fixed"), component= c("all"))
# 0.782
p_direction(number_hatched_test)
#Probability of Direction 

#Parameter   |     pd
#  (Intercept) |   100%
#ftreatment1 | 76.34%

## 3. treatment related differences in clutch size 

# again, clutch size formed before supplementation began so shouldn't be differences 

clutch_size_test <- brm(clutch_size ~ ftreatment + (1|fsite) + (1|fyear),
                        data = first_hatch_only, 
                        family = poisson(), # note poisson distribution used 
                        warmup = 5000, 
                        iter = 10000, 
                        chains = 4, 
                        cores = parallel::detectCores(), 
                        control = list(adapt_delta = 0.99, max_treedepth = 20), 
                        backend = "cmdstanr")
summary(clutch_size_test)
fixef(clutch_size_test)

# p-map
p_map(clutch_size_test, null=0, precision=2^10, method="kernel", effects= c("fixed"), component= c("all"))
#0.995
p_direction(clutch_size_test)
#Probability of Direction 

#Parameter   |     pd
#  (Intercept) |   100%
#ftreatment1 | 50.01%

##### models testing research questions -----

### 1. IVI
# we ran 2 different models for IVI. See manuscript for detailed explaination of why
# in short: if supplemented nests have higher survival = also have higher brood sizes 
# test using 2 models to tease apart effect of brood size (increased survival) versus true treatment effect

## a. IVI model including brood size as fixed effect 
ivi_model <- brm(bf(logIVI ~ 1 + ftreatment + brood_size_sc + hatch_date_sc + age_sc +
                      (1|fsite) + (1|fpair) + (1|fyear), 
                    sigma ~ 1+ ftreatment), 
                 data = ivi_data, 
                 family = gaussian(),
                 warmup = 7000, 
                 iter = 10000,
                 chains = 4, 
                 cores = parallel::detectCores(), 
                 control = list(adapt_delta = 0.99, max_treedepth = 20), 
                 backend = "cmdstanr")
summary(ivi_model)
fixef(ivi_model)
ranef(ivi_model)

# p-map
p_map(ivi_model, null=0, precision=2^10, method="kernel", effects= c("fixed"), component= c("all"))
p_direction(ivi_model)
#Parameter         |     pd
#  (Intercept)       |   100%
#sigma_Intercept   | 91.47%
#ftreatmenty       | 67.69%
#brood_size_sc     |   100%
#hatch_date_sc     | 87.52%
#age_sc            |   100%
#sigma_ftreatmenty | 91.38%

## b. IVI model without brood size as fixed effect 
ivi_model2 <- brm(bf(logIVI ~ 1 + ftreatment + hatch_date_sc + age_sc +
                       (1|fsite) + (1|fpair) + (1|fyear), 
                     sigma ~ 1+ ftreatment), 
                  data = ivi_data, 
                  family = gaussian(),
                  warmup = 7000, 
                  iter = 10000,
                  chains = 4, 
                  cores = parallel::detectCores(), 
                  control = list(adapt_delta = 0.99, max_treedepth = 20), 
                  backend = "cmdstanr")
summary(ivi_model2)
fixef(ivi_model2)
ranef(ivi_model2)

#p-map
p_map(ivi_model2, null=0, precision=2^10, method="kernel", effects= c("all"), component= c("all"))
p_direction(ivi_model2)
#Parameter         |     pd
#(Intercept)       |   100%
#sigma_Intercept   | 94.55%
#ftreatmenty       | 51.63%
#hatch_date_sc     | 77.05%
#age_sc            |   100%
#sigma_ftreatmenty | 93.42%


### 2. fledging success i.e., probability of survival to fledging 

# The "bernoulli" family assumes that the response variable follows a Bernoulli distribution, 
# which models the probability of success (survival) as a function of the predictors. 
# In the context of logistic regression, the "bernoulli" family uses a logit link function to model the log-odds (logit) of success.
# By specifying the "bernoulli" family, the model estimates the probabilities of survival based on the given predictor variables, 
# and the coefficients represent the log-odds ratios associated with the predictors.
# To summarize, the choice of the "bernoulli" family for the response variable "surv" in this case is appropriate 
# because it aligns with the binary nature of the data, allowing for the modeling of survival probabilities using logistic regression.

# note to self: change this to just being called survival_prob_model before publication 
survival_prob_model2 <- brm(bf(surv ~ ftreatment + number_hatched_sc + hatch_date_sc + 
                                 (1 | fsite) + (1 | fpair) + (1 | fyear)),
                            data = assumed_fledge_data,
                            family = bernoulli(),
                            chains = 2,
                            iter = 10000,
                            warmup = 8000,
                            cores = parallel::detectCores(),
                            control = list(adapt_delta = 0.99, max_treedepth = 10),
                            backend = "cmdstanr")

summary(survival_prob_model2)
fixef(survival_prob_model2)
ranef(survival_prob_model2)

# p-map
p_map(survival_prob_model2, null=0, precision=2^10, method="kernel", effects= c("all"), component= c("all"))
p_direction(survival_prob_model2)
#Parameter         |     pd
#(Intercept)       | 52.45%
#ftreatment1       |   100%
#number_hatched_sc | 96.43%
#hatch_date_sc     | 99.92%


### 3. body mass at (assumed) fledging 

body_mass_fledge <- brm(bf(weight ~ 1 + ftreatment + brood_size_sc + hatch_date_sc + age_sc + # (called weight in spreadsheet but is actually mass values); brood size is number fledged here
                             (1|fsite) + (1|fpair) + (1|fyear), 
                        sigma ~ 1+ ftreatment), 
                        data = filtered_assumed_fledge, 
                        family = gaussian(),
                        warmup = 1000, 
                        iter = 6000,
                        chains = 4, 
                        cores = parallel::detectCores(), 
                        control = list(adapt_delta = 0.99, max_treedepth = 20), 
                        backend = "cmdstanr")

summary(body_mass_fledge)
fixef(body_mass_fledge)
ranef(body_mass_fledge)

# p-map
p_map(body_mass_fledge, null=0, precision=2^10, method="kernel", effects= c("all"), component= c("all"))
p_direction(body_mass_fledge)
#Parameter         |     pd
#(Intercept)       |   100%
#sigma_Intercept   |   100%
#ftreatment1       | 71.21%
#brood_size_sc     | 91.29%
#hatch_date_sc     | 80.55%
#age_sc            | 95.45%
#sigma_ftreatment1 | 75.39%


##### creating function for calculating proportion values -----

# without a function, the code needed to do this with a brms model is long and makes the code look messy 
# it also requires the user to manually check and correct the proportion to be the one in the opposite direction of the estimated effect 
# for example:
prop_neg <- body_mass_fledge %>% 
  spread_draws(b_brood_size_sc) %>%
  mutate(neg_count = sum(b_brood_size_sc<0)) %>% 
  mutate(pos_count= sum(b_brood_size_sc>0)) %>%
  mutate(proportion_neg = sum(neg_count)/(sum(pos_count)+ sum(neg_count))) %>% 
  pull(proportion_neg) %>% 
  mean()
prop_neg# final estimate from model was negative so need to calculate proportion of positive estimates 
p <- (1-prop_neg)
p # 0.087

# to fix this: 
# I first created a function that just calculates how many estimates from the posterior draws are negative 
prop_calc_neg <- function(model,effect) {
  model_name <- deparse(substitute(model))
  result <- model %>%
    spread_draws({{ effect }}) %>%
    mutate(neg_count = sum({{ effect }} < 0)) %>%
    mutate(pos_count = sum({{ effect }} > 0)) %>%
    mutate(proportion_neg = sum(neg_count) / (sum(pos_count) + sum(neg_count))) %>%
    pull(proportion_neg) %>%
    mean()
  
  cat("in", model_name, "proportion of negative estimates for", deparse(substitute(effect)), ":", result, "\n")
  return(result)
}

# then upgraded to function that calculated proportion of estimates in opposite direction of estimated effect 
prop_opposite <- function(model, effect) {
  model_name <- deparse(substitute(model))
  
  result <- model %>%
    spread_draws({{ effect }}) %>%
    mutate(neg_count = sum({{ effect }} < 0)) %>%
    mutate(pos_count = sum({{ effect }} > 0)) %>%
    mutate(proportion_neg = sum(neg_count) / (sum(pos_count) + sum(neg_count))) %>%
    pull(proportion_neg) %>%
    mean()
  
  if (result > 0.5) {
    result <- 1 - result
    cat("in", model_name, "proportion of estimates in opposite direction for", deparse(substitute(effect)), ":", result, "\n")
  } else {
    cat("in", model_name, "proportion of estimates in opposite direction for", deparse(substitute(effect)), ":", result, "\n")
  }
  
  return(result)
}

# examples of usage in next section 
# to use the function user needs to load: tidyverse / dplyr
# (must also provide a valid model object and effect)

# note: 
# currently written to work with brms models (ie using spread_draws)
# but could be easily modified to be used with other Bayesian models 
# e.g., by adding a line to inherit model class 

##### using created function to calculate proportion values for models -----
## models confirming no treatment related differences 

prop <- prop_opposite(hatch_date_test, b_ftreatment1)
prop <- prop_opposite(number_hatched_test, b_ftreatment1)
prop <- prop_opposite(clutch_size_test, b_ftreatment1)

## models testing research questions 
# 1. IVI
# a
# fixed effects: ftreatment + brood_size_sc + hatch_date_sc + age_sc

prop <- prop_opposite(ivi_model, b_ftreatmenty)
prop <- prop_opposite(ivi_model, b_brood_size_sc)
prop <- prop_opposite(ivi_model, b_hatch_date_sc)
prop <- prop_opposite(ivi_model, b_age_sc)

# IVI 
# b
# just need for ftreatment 
prop <- prop_opposite(ivi_model2, b_ftreatmenty)

# 2. fledging success
# fixed effects: ftreatment + number_hatched_sc + hatch_date_sc
prop <- prop_opposite(survival_prob_model2, b_ftreatment1)
prop <- prop_opposite(survival_prob_model2, b_number_hatched_sc)
prop <- prop_opposite(survival_prob_model2, b_hatch_date_sc)

# 3. Body mass at fledge 
# fixed effects: ftreatment + brood_size_sc + hatch_date_sc + age_sc
prop <- prop_opposite(body_mass_fledge, b_ftreatment1)
prop <- prop_opposite(body_mass_fledge, b_brood_size_sc)
prop <- prop_opposite(body_mass_fledge, b_hatch_date_sc)
prop <- prop_opposite(body_mass_fledge, b_age_sc)

##note to self:
# just realized that the 'pr' value is just 1-p_direction so I didnt need to do that whole journey with the function creation etc.

##### creating figures -----
# Create a data frame with control data included
results <- data.frame(
  models = rep(c("IVI", "Survival", "Body Condition"), each = 2),
  estimates = c(5.00, 5.01, -0.08, 2.31, 635.89, 647.15),
  CIs_upper = c(5.24, 5.37, 1.19, 5.12, 712.52, 764.24),
  CIs_lower = c(4.77, 4.67, -1.43, -0.32, 552.75, 524.2),
  response_variable = rep(c("IVI", "Survival", "Body Condition"), each = 2),
  treatment = rep(c("Control", "Supplemented"), times = 3),
  color = factor(rep(c("Control", "Supplemented"), times = 3), levels = c("Control", "Supplemented"))
)

# Set the levels of models in the desired order
results$models <- factor(results$models, levels = c("IVI", "Survival", "Body Condition"))

# Set the levels of response_variable in the desired order
results$response_variable <- factor(results$response_variable, levels = c("IVI", "Survival", "Body Condition"))

# Assign colors and rearrange order
colors <- c("cadetblue4", "burlywood4")
names(colors) <- levels(results$color)

# Create a ggplot with three panels and grid lines
ggplot(results, aes(x = models, y = estimates, color = color)) +
  geom_point(position = position_dodge(width = 0.5), size = 4) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.5),
    width = 0.2
  ) +
  scale_color_manual(values = colors) + 
  labs(y = "", x = "") +
  theme_minimal() +
  theme(legend.position = "none", 
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.border = element_rect(color = "black", size = 0.5, fill = NA),
        axis.text.x = element_blank(),  # Remove x-axis labels
        axis.text.y = element_text(size = 12, face = "bold"),  # Modify y-axis text
        axis.title.x = element_blank(),  # Remove x-axis title
        axis.title.y = element_text(size = 12, face = "bold"),
        strip.text.x = element_text(size = 12, face = "bold"),  # Modify top axis text
        strip.text.y = element_text(size = 12, face = "bold")) +  # Modify right axis text
  facet_grid(response_variable ~ treatment, scales = "free_y")

# Create a ggplot with separate panels for different traits and grid lines
final_plot <- ggplot(results, aes(x = models, y = estimates, color = color)) +
  geom_point(position = position_dodge(width = 0.5), size = 4) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.5),
    width = 0.2
  ) +
  scale_color_manual(values = colors) + 
  labs(y = "", x = "") +
  theme_minimal() +
  theme(legend.position = "none", 
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.border = element_rect(color = "black", size = 0.5, fill = NA),
        axis.text.x = element_blank(),  # Remove x-axis labels
        #axis.text.x = element_text(size = 12, face = "bold"),  # Modify x-axis text
        axis.text.y = element_text(size = 12, face = "bold"),  # Modify y-axis text
        #axis.title.x = element_text(size = 12, face = "bold"),  # Modify x-axis title
        axis.title.x = element_blank(),  # Remove x-axis title
        axis.title.y = element_text(size = 12, face = "bold"),
        strip.text.x = element_text(size = 12, face = "bold"),  # Modify top axis text
        strip.text.y = element_text(size = 12, face = "bold")) +  # Modify right axis text
  facet_wrap(~ response_variable, scales = "free_y", ncol = 1)
final_plot

# save fig in high res 
# Specify the file path and name
#file_path <- "G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/SUPPLEMENTATION PAPER/figures/Supp_Figure_1_600DPI.tiff"
  
# Save the combined plot with high DPI
#ggsave(file_path, plot = final_plot, width = 12, height = 8, dpi = 600)


##### Remake figure 1 -----

# 1. IVI 
# Create a data frame with control data included
IVI <- data.frame(
  estimates = c(5.00, 5.01), 
  CIs_lower = c(4.77, 4.67), 
  CIs_upper = c(5.24, 5.37), 
  treatment = c("Control", "Supplemented"), 
  color = factor(c("Control", "Supplemented"), levels = c("Control", "Supplemented")))


# Colors
colors <- c("cadetblue4", "burlywood4")


# Plotting
IVI_plot <- ggplot(IVI, aes(x = treatment, y = estimates, color = color)) +
  geom_point(position = position_dodge(width = 0.2), size = 3) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.2),
    width = 0.2
  ) +
  scale_color_manual(values = colors) +
  labs(
    x = "Treatment",
    y = "log IVI (minutes)",
    color = "Treatment"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",  # Remove legend
    panel.grid.major = element_blank(),  # Remove background grid lines
    panel.grid.minor = element_blank(),  # Remove background grid lines
    axis.line = element_line(color = "black"),  # Add black axis lines
    text = element_text(size = 14),  # Set text size to 14
    axis.title = element_text(face = "bold", size = 14),  # Bold and size 14 axis titles
    axis.text.x = element_text(face = "bold"),
    axis.title.x = element_blank()) +
  scale_y_continuous(limits = c(4.5, 5.4), breaks = seq(4.5, 5.4, by = 0.1))  # Set y-axis limits and breaks


# 2. Survival 
# Create a data frame with control data included
Survival <- data.frame(
  estimates = c(-0.08, 2.31), 
  CIs_lower = c(-1.43, -0.32), 
  CIs_upper = c(1.19, 5.12), 
  treatment = c("Control", "Supplemented"), 
  color = factor(c("Control", "Supplemented"), levels = c("Control", "Supplemented")))


# Colors
colors <- c("cadetblue4", "burlywood4")


# Plotting
Survival_plot <- ggplot(Survival, aes(x = treatment, y = estimates, color = color)) +
  geom_point(position = position_dodge(width = 0.2), size = 3) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.2),
    width = 0.2
  ) +
  scale_color_manual(values = colors) +
  labs(
    x = "Treatment",
    y = "Survival (log odds ratio)",
    color = "Treatment"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",  # Remove legend
    panel.grid.major = element_blank(),  # Remove background grid lines
    panel.grid.minor = element_blank(),  # Remove background grid lines
    axis.line = element_line(color = "black"),  # Add black axis lines
    text = element_text(size = 14),  # Set text size to 14
    axis.title = element_text(face = "bold", size = 14),  # Bold and size 14 axis titles
    axis.text.x = element_text(face = "bold"),
    axis.title.x = element_blank()) +
  scale_y_continuous(limits = c(-2, 6), breaks = seq(-2, 6, by = 1))  # Set y-axis limits and breaks


# 3. Body Condition 
Body_condition <- data.frame(
  estimates = c(635.89, 647.15), 
  CIs_lower = c(552.75, 524.2), 
  CIs_upper = c(712.52, 764.24), 
  treatment = c("Control", "Supplemented"), 
  color = factor(c("Control", "Supplemented"), levels = c("Control", "Supplemented")))


# Colors
colors <- c("cadetblue4", "burlywood4")


# Plotting
Bodycon_plot <- ggplot(Body_condition, aes(x = treatment, y = estimates, color = color)) +
  geom_point(position = position_dodge(width = 0.2), size = 3) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.2),
    width = 0.2
  ) +
  scale_color_manual(values = colors) +
  labs(
    x = "Treatment",
    y = "Mass (grams)",
    color = "Treatment"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",  # Remove legend
    panel.grid.major = element_blank(),  # Remove background grid lines
    panel.grid.minor = element_blank(),  # Remove background grid lines
    axis.line = element_line(color = "black"),  # Add black axis lines
    text = element_text(size = 14),  # Set text size to 14
    axis.title = element_text(face = "bold", size = 14),  # Bold and size 14 axis titles
    axis.text.x = element_text(face = "bold"),
    axis.title.x = element_blank()) +
  scale_y_continuous(limits = c(500, 800), breaks = seq(500, 800, by = 50))  # Set y-axis limits and breaks


# Arrange figures side by side
combined_plot <- (IVI_plot + Survival_plot + Bodycon_plot) +
  plot_annotation(tag_levels = "A")

combined_plot


# save fig in high res 
# Specify the file path and name
file_path <- "G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/SUPPLEMENTATION PAPER/figures/Supp_Figure_1_600DPI.tiff"

# Save the combined plot with high DPI
ggsave(file_path, plot = combined_plot, width = 24, height = 8, dpi = 600)




















##### creating quail ESM -----

# 'ivi_data' has 'date' in the format dd/mm/yyyy
# Convert 'date' in 'ivi_data' to the same format as 'Date' in 'quail'
# Convert date columns to a common format
ivi_data$date <- as.Date(ivi_data$date, format = "%d/%m/%Y")
quail$Date <- as.Date(quail$Date, format = "%d-%b")

# Merge dataframes
merged_quail <- merge(ivi_data, quail, by.x = c("date", "year", "yearsite"), by.y = c("Date", "Year", "yearsite"), all = TRUE)

merged_quail %>%
  group_by(nestlingage, chicks,year) %>%
  summarise(Supp = list(Supp)) %>%
  ungroup() %>%
  select(year, nestlingage, chicks, Supp) %>%
  unnest(Supp) -> output_table

output_table %>%
  group_by(year, nestlingage, chicks) %>%
  na.omit() %>% 
  summarise(
    min_supp = min(Supp, na.rm = TRUE),
    max_supp = max(Supp, na.rm = TRUE),
    mean_supp = mean(Supp, na.rm = TRUE)
  ) -> summary_table

summary_table %>%
  mutate(range = paste(min_supp, max_supp, sep = "-")) %>%
  arrange(year, nestlingage, chicks) -> summary_table_ordered_with_range

summary_table_ordered_with_range %>%
  select(-min_supp, -max_supp, -mean_supp) %>%
  rename(
    Year = year,
    `Nestling Age` = nestlingage,
    `Brood Size` = chicks,
    `Number of Quail Provided (Range)` = range
  ) -> summary_table_final

##### remove before publication -----

## testing quail data stuff
quail <- read.csv("G:/.shortcut-targets-by-id/15aIOTzK-SdA0QZzPxWaQk_8cNO0OoEUl/Rebekah thesis/SUPPLEMENTATION PAPER/Data sheets/quail_pattern_test.csv")
quail$Supp <- as.numeric(quail$Supp)

#quail <- na.omit(quail)

names(quail)

# Convert "date" variable to date format
quail$date <- as.Date(quail$date)

# Plot the data
ggplot(quail, aes(x = date, y = Supp, color = factor(Year))) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  labs(x = "Date", y = "Supp", color = "Year") +
  theme_minimal()


# Convert "date" variable to date format
quail$date <- as.Date(quail$date)

# Plot with separate figures for each year
ggplot(quail, aes(x = date, y = Supp)) +
  geom_point(aes(color = as.factor(Site))) +
  geom_smooth(method = "lm", se = FALSE, color = "grey") +
  labs(x = "Date", y = "Supp") +
  theme_minimal() +
  facet_wrap(~ Year, ncol = 1)



quail$date <- as.numeric(as.Date(quail$date))

cor_data <- quail %>%
  group_by(Year) %>%
  summarise(correlation = cor(Supp, date))


# Plot with separate figures for each year
ggplot(quail, aes(x = date, y = Supp)) +
  geom_point(aes(color = as.factor(Site))) +
  geom_smooth(method = "lm", se = FALSE, color = "grey") +
  labs(x = "Date", y = "Supp") +
  theme_minimal() +
  facet_wrap(~ Year, ncol = 1) +
  geom_text(data = cor_data, aes(label = paste("Correlation:", round(correlation, 2)), 
                                 x = Inf, y = Inf, hjust = 1, vjust = 1),
            color = "black", size = 4, fontface = "bold", show.legend = FALSE)



exp(0.08)


exp(5.5)/60


# Create a data frame
results <- data.frame(
  models = c("IVI", "Survival", "Body Condition"),
  estimates = c(0.01, 2.39, 11.26),
  CIs_upper = c(0.13, 3.93, 51.72),
  CIs_lower = c(0.10, 1.11, -28.55)
)

# Create a ggplot
ggplot(results, aes(x = models, y = estimates, color = models)) +
  geom_point(position = position_dodge(width = 0.3), size = 3) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.3),
    width = 0.2
  ) +
  labs(title = "Effect of Supplementation on Different Models",
       x = "Models",
       y = "Estimates") +
  theme_minimal() +
  theme(legend.position = "none")  # Remove legend if not needed


# making esm for quail stuff












##old figure versions

# Create a data frame
results <- data.frame(
  models = c("IVI", "Survival", "Body Condition"),
  estimates = c(0.01, 2.39, 11.26),
  CIs_upper = c(0.13, 3.93, 51.72),
  CIs_lower = c(-0.10, 1.11, -28.55)
)

# Assign colors and rearrange order
results$color <- factor(results$models, levels = c("IVI", "Survival", "Body Condition"))
results$models <- factor(results$models, levels = c("IVI", "Survival", "Body Condition"))
colors <- c("darkred", "darkolivegreen4", "darkred")
names(colors) <- levels(results$color)

# Create a ggplot
ggplot(results, aes(x = models, y = estimates, color = color)) +
  geom_hline(yintercept = 0, linetype = "longdash", color = "cornsilk3", size = 0.5, z = -Inf) +  # Add grey line behind points
  geom_point(position = position_dodge(width = 0), size = 4) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.3),
    width = 0.2
  ) +
  scale_color_manual(values = colors) +  # Set manual color scale
  labs(y = "", x = "") +
  theme_minimal() +
  theme(legend.position = "none", 
        panel.grid.major = element_blank(),  # Remove major grid lines
        panel.grid.minor = element_blank())  # Remove minor grid lines
###

# Assign colors and rearrange order
results$color <- factor(results$models, levels = c("IVI", "Survival", "Body Condition"))
results$models <- factor(results$models, levels = c("IVI", "Survival", "Body Condition"))
colors <- c("darkred", "darkolivegreen4", "darkred")
names(colors) <- levels(results$color)

# Create a ggplot
ggplot(results, aes(x = models, y = estimates, color = color)) +
  geom_hline(yintercept = 0, linetype = "longdash", color = "grey50", size = 0.5, z = -Inf) +  # Add grey line behind points
  geom_point(position = position_dodge(width = 0), size = 4) +
  geom_errorbar(
    aes(ymin = CIs_lower, ymax = CIs_upper),
    position = position_dodge(width = 0.3),
    width = 0.2
  ) +
  scale_color_manual(values = colors) +  # Set manual color scale
  labs(y = "", x = "") +
  theme_minimal() +
  theme(legend.position = "none", 
        panel.grid.major = element_blank(),  # Remove major grid lines
        panel.grid.minor = element_blank(),  # Remove minor grid lines
        axis.text.x = element_text(size = 16, face = "bold"),  # Modify x-axis text
        axis.text.y = element_text(size = 12, face = "bold"))  # Modify y-axis text


