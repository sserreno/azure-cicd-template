using 'main.bicep'

param env = 'prod'
param appName = readEnvironmentVariable('APP_NAME')
param tier = readEnvironmentVariable('TIER', 'free')
param regionCode = readEnvironmentVariable('REGION_CODE', 'sdc')
param paidPlanSku = readEnvironmentVariable('PAID_PLAN_SKU', 'B1')
param paidSqlSku = readEnvironmentVariable('PAID_SQL_SKU', 'Basic')
param sqlAdminGroupName = readEnvironmentVariable('SQL_ADMIN_GROUP_NAME')
param sqlAdminGroupObjectId = readEnvironmentVariable('SQL_ADMIN_GROUP_ID')
param microsoftAuthClientId = readEnvironmentVariable('MICROSOFT_AUTH_CLIENT_ID', '')
param githubAuthClientId = readEnvironmentVariable('GITHUB_AUTH_CLIENT_ID', '')
param githubAuthClientSecret = readEnvironmentVariable('GITHUB_AUTH_CLIENT_SECRET', '')
param emailAuthClientId = readEnvironmentVariable('EMAIL_AUTH_CLIENT_ID', '')
param emailAuthMetadataUrl = readEnvironmentVariable('EMAIL_AUTH_METADATA_URL', '')
param emailAuthClientSecret = readEnvironmentVariable('EMAIL_AUTH_CLIENT_SECRET', '')
