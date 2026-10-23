// One-time, subscription-level setup for one environment. Run by
// scripts/setup-azure.sh with an Owner account, not by the pipelines.
targetScope = 'subscription'

@allowed(['dev', 'prod'])
param env string

@description('Short lowercase app name used in every resource name, e.g. "acme".')
param appName string

@allowed(['free', 'paid'])
@description('free: a policy allows only resource types that cannot charge. paid: monitoring is allowed too.')
param tier string = 'free'

@description('Region for everything. App Service F1 is not offered in every region; swedencentral has it.')
param location string = 'swedencentral'

@description('Short region code used in resource names.')
param regionCode string = 'sdc'

@description('The repository as GitHub names it in OIDC token subjects: owner@ownerId/repo@repoId.')
param githubOidcRepo string

@description('Git refs whose workflow runs may deploy this environment, e.g. refs/heads/main.')
param deployRefs array

@description('Also trust workflow runs triggered by pull requests (dev only, for what-if).')
param trustPullRequests bool = false

@description('Addresses that receive budget alerts.')
param budgetContactEmails array

@description('Monthly budget in the billing currency. 1 on the free tier: any charge at all alerts.')
param budgetAmount int = 1

@description('Extra locations to allow, e.g. "europe" for an Entra External ID tenant.')
param extraAllowedLocations array = []

@description('First day of the budget period. Leave the default.')
param budgetStartDate string = utcNow('yyyy-MM-01T00:00:00Z')

var tags = {
  env: env
  app: appName
  tier: tier
  managedBy: 'bicep'
}

var allowedLocations = concat([location, 'global'], extraAllowedLocations)

// Everything the design needs, including child types, so the policy blocks
// any other (possibly paid) resource. Add to this list when the design grows.
var freeResourceTypes = [
  'Microsoft.Resources/resourceGroups'
  'Microsoft.Resources/deployments'
  'Microsoft.Authorization/roleAssignments'
  'Microsoft.Authorization/policyAssignments'
  'Microsoft.Consumption/budgets'
  'Microsoft.ManagedIdentity/userAssignedIdentities'
  'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials'
  'Microsoft.Web/serverfarms'
  'Microsoft.Web/sites'
  'Microsoft.Web/sites/config'
  'Microsoft.Web/sites/extensions'
  'Microsoft.Web/sites/basicPublishingCredentialsPolicies'
  'Microsoft.Sql/servers'
  'Microsoft.Sql/servers/databases'
  'Microsoft.Sql/servers/firewallRules'
  'Microsoft.Sql/servers/administrators'
  'Microsoft.Sql/servers/azureADOnlyAuthentications'
]

var paidResourceTypes = concat(freeResourceTypes, [
  'Microsoft.OperationalInsights/workspaces'
  'Microsoft.Insights/components'
  'Microsoft.Web/sites/slots'
  'Microsoft.Web/sites/slots/config'
  'Microsoft.Web/sites/slots/basicPublishingCredentialsPolicies'
])

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${appName}-${env}-${regionCode}'
  location: location
  tags: tags
}

module identity 'identity.bicep' = {
  name: 'deploy-identity'
  scope: rg
  params: {
    name: 'id-${appName}-${env}-deploy-${regionCode}'
    location: location
    tags: tags
    githubOidcRepo: githubOidcRepo
    deployRefs: deployRefs
    trustPullRequests: trustPullRequests
  }
}

// Built-in policy definitions.
var allowedLocationsPolicy = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
var allowedRgLocationsPolicy = 'e765b5de-1225-4ba3-bd56-1ac6695af988'
var allowedResourceTypesPolicy = 'a08ec900-254a-4555-9bf5-e42af04b5c5c'

resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${appName}-allowed-locations'
  properties: {
    displayName: '${appName}: allowed locations'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', allowedLocationsPolicy)
    parameters: {
      listOfAllowedLocations: { value: allowedLocations }
    }
  }
}

resource allowedRgLocationsAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${appName}-allowed-rg-locations'
  properties: {
    displayName: '${appName}: allowed resource group locations'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', allowedRgLocationsPolicy)
    parameters: {
      listOfAllowedLocations: { value: [location] }
    }
  }
}

resource allowedResourceTypesAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${appName}-allowed-resource-types'
  properties: {
    displayName: '${appName}: allowed resource types (${tier} tier)'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', allowedResourceTypesPolicy)
    parameters: {
      listOfResourceTypesAllowed: { value: tier == 'free' ? freeResourceTypes : paidResourceTypes }
    }
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-${appName}-${env}'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      forecasted: {
        enabled: true
        operator: 'GreaterThan'
        threshold: tier == 'free' ? 50 : 80
        thresholdType: 'Forecasted'
        contactEmails: budgetContactEmails
      }
      actualOver100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: budgetContactEmails
      }
    }
  }
}

output resourceGroupName string = rg.name
output deployClientId string = identity.outputs.clientId
output deployPrincipalId string = identity.outputs.principalId
