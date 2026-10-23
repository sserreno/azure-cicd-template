// App infrastructure for one environment. Deployed by the pipeline into the
// resource group created by bootstrap/main.bicep. The tier picks free or
// paid SKUs (docs/adr/0001-free-and-paid-tiers.md).
@allowed(['dev', 'prod'])
param env string

@description('Short lowercase app name used in every resource name, e.g. "acme".')
@minLength(2)
@maxLength(12)
param appName string

@allowed(['free', 'paid'])
@description('free: services that cannot charge. paid: always-on plan, a database that never pauses, and monitoring.')
param tier string = 'free'

param location string = resourceGroup().location

@description('Short region code used in resource names.')
param regionCode string = 'sdc'

@description('Display name of the Entra ID group that administers the SQL server.')
param sqlAdminGroupName string

@description('Object ID of that Entra ID group.')
param sqlAdminGroupObjectId string

@description('App Service plan SKU for the paid tier: B1 is the cheapest always-on plan; S1 or P0v3 add deployment slots.')
param paidPlanSku string = 'B1'

@description('Azure SQL SKU for the paid tier: Basic (2 GB), S0 (250 GB) or a vCore SKU such as GP_S_Gen5_1.')
param paidSqlSku string = 'Basic'

@description('Client ID of the Entra app registration for "Sign in with Microsoft". Empty leaves it off.')
param microsoftAuthClientId string = ''

@description('Client ID of the GitHub OAuth app for "Sign in with GitHub". Empty leaves it off.')
param githubAuthClientId string = ''

@secure()
param githubAuthClientSecret string = ''

@description('Client ID of an Entra External ID app registration for "Sign in with email". Empty leaves it off.')
param emailAuthClientId string = ''

@description('OpenID Connect metadata document URL of that app registration.')
param emailAuthMetadataUrl string = ''

@secure()
param emailAuthClientSecret string = ''

var tags = {
  env: env
  app: appName
  tier: tier
  managedBy: 'bicep'
}

var sqlServerName = 'sql-${appName}-${env}-${regionCode}'
var sqlDatabaseName = 'sqldb-${appName}'

module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    serverName: sqlServerName
    databaseName: sqlDatabaseName
    location: location
    tags: tags
    tier: tier
    paidSku: paidSqlSku
    adminGroupName: sqlAdminGroupName
    adminGroupObjectId: sqlAdminGroupObjectId
  }
}

module monitoring 'modules/monitoring.bicep' = if (tier == 'paid') {
  name: 'monitoring'
  params: {
    workspaceName: 'log-${appName}-${env}-${regionCode}'
    insightsName: 'appi-${appName}-${env}-${regionCode}'
    location: location
    tags: tags
  }
}

module web 'modules/app-service.bicep' = {
  name: 'app-service'
  params: {
    planName: 'asp-${appName}-${env}-${regionCode}'
    appName: 'app-${appName}-${env}-${regionCode}'
    identityName: 'id-${appName}-${env}-app-${regionCode}'
    location: location
    tags: tags
    tier: tier
    paidPlanSku: paidPlanSku
    sqlServerFqdn: sql.outputs.serverFqdn
    sqlDatabaseName: sqlDatabaseName
    appInsightsConnectionString: tier == 'paid' ? monitoring!.outputs.connectionString : ''
    microsoftAuthClientId: microsoftAuthClientId
    githubAuthClientId: githubAuthClientId
    githubAuthClientSecret: githubAuthClientSecret
    emailAuthClientId: emailAuthClientId
    emailAuthMetadataUrl: emailAuthMetadataUrl
    emailAuthClientSecret: emailAuthClientSecret
  }
}

output appName string = web.outputs.name
output appHostname string = web.outputs.defaultHostname
output appIdentityName string = web.outputs.identityName
output appIdentityClientId string = web.outputs.identityClientId
output sqlServerName string = sql.outputs.serverName
output sqlServerFqdn string = sql.outputs.serverFqdn
output sqlDatabaseName string = sql.outputs.databaseName
