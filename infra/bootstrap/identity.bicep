// The pipeline's deploy identity for one environment: trusted by GitHub OIDC
// for the given refs, Contributor on this resource group only.
param name string
param location string
param tags object
param githubOidcRepo string
param deployRefs array
param trustPullRequests bool

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

var subjects = concat(
  map(deployRefs, ref => 'repo:${githubOidcRepo}:ref:${ref}'),
  trustPullRequests ? ['repo:${githubOidcRepo}:pull_request'] : []
)

// Federated credentials on one identity must be created one at a time.
@batchSize(1)
resource federated 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for (subject, i) in subjects: {
    parent: identity
    name: 'github-${i}'
    properties: {
      issuer: 'https://token.actions.githubusercontent.com'
      subject: subject
      audiences: ['api://AzureADTokenExchange']
    }
  }
]

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, contributorRoleId)
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
}

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
