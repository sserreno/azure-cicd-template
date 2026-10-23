using 'main.bicep'

param env = 'dev'
param appName = readEnvironmentVariable('APP_NAME')
param tier = readEnvironmentVariable('TIER', 'free')
param location = readEnvironmentVariable('REGION', 'swedencentral')
param regionCode = readEnvironmentVariable('REGION_CODE', 'sdc')
param githubOidcRepo = readEnvironmentVariable('GITHUB_OIDC_REPO')
param deployRefs = ['refs/heads/main']
param trustPullRequests = true
param budgetContactEmails = [readEnvironmentVariable('BUDGET_EMAIL')]
param budgetAmount = int(readEnvironmentVariable('BUDGET_AMOUNT', '1'))
param extraAllowedLocations = empty(readEnvironmentVariable('EXTRA_ALLOWED_LOCATIONS', '')) ? [] : split(readEnvironmentVariable('EXTRA_ALLOWED_LOCATIONS', ''), ',')
