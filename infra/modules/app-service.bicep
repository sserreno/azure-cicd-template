// One Linux App Service running a Node 22 app that serves the frontend and
// the API (docs/adr/0002-app-service-and-azure-sql.md).
// free: the F1 plan, which stops instead of billing at its daily CPU quota.
// paid: the given plan SKU with Always On.
param planName string
param appName string
param identityName string
param location string
param tags object

@allowed(['free', 'paid'])
param tier string

param paidPlanSku string

@description('SQL server FQDN and database name, read by the app at startup.')
param sqlServerFqdn string
param sqlDatabaseName string

@description('Application Insights connection string; empty on the free tier.')
param appInsightsConnectionString string = ''

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

var microsoftSignIn = !empty(microsoftAuthClientId)
var githubSignIn = !empty(githubAuthClientId)
var emailSignIn = !empty(emailAuthClientId)
var anySignIn = microsoftSignIn || githubSignIn || emailSignIn

// The app's own identity, used to sign in to SQL. User-assigned so its
// client ID is known here and the pipeline can create its database user.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: tier == 'free' ? { name: 'F1', tier: 'Free' } : { name: paidPlanSku }
  properties: {
    reserved: true // Linux
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      appCommandLine: 'node dist/src/server.js'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      // F1 can't stay warm; paid plans can, so the first request isn't slow.
      alwaysOn: tier == 'paid'
      healthCheckPath: tier == 'paid' ? '/api/health' : null
      appSettings: concat([
        { name: 'SQL_SERVER', value: sqlServerFqdn }
        { name: 'SQL_DATABASE', value: sqlDatabaseName }
        { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
        // The pipeline deploys a built package; no build on the server.
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
      ], githubSignIn ? [
        { name: 'GITHUB_PROVIDER_AUTHENTICATION_SECRET', value: githubAuthClientSecret }
      ] : [], emailSignIn ? [
        // App Service Authentication reads a custom provider's secret from
        // <provider>_AUTHENTICATION_SECRET.
        { name: 'EMAIL_AUTHENTICATION_SECRET', value: emailAuthClientSecret }
        { name: 'EMAIL_SIGN_IN', value: 'on' }
      ] : [], !empty(appInsightsConnectionString) ? [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
      ] : [])
    }
  }
}

// App Service Authentication with whichever providers are configured.
// Unauthenticated requests still reach the app, which decides per route.
resource auth 'Microsoft.Web/sites/config@2024-04-01' = if (anySignIn) {
  parent: app
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: false
      unauthenticatedClientAction: 'AllowAnonymous'
    }
    httpSettings: {
      requireHttps: true
    }
    login: {
      tokenStore: {
        enabled: false
      }
    }
    identityProviders: union(microsoftSignIn ? {
      azureActiveDirectory: {
        enabled: true
        registration: {
          // "common" accepts work, school and personal Microsoft accounts.
          // No client secret: sign-in uses the implicit ID-token flow.
          openIdIssuer: '${environment().authentication.loginEndpoint}common/v2.0'
          clientId: microsoftAuthClientId
        }
      }
    } : {}, githubSignIn ? {
      gitHub: {
        enabled: true
        registration: {
          clientId: githubAuthClientId
          clientSecretSettingName: 'GITHUB_PROVIDER_AUTHENTICATION_SECRET'
        }
      }
    } : {}, emailSignIn ? {
      // "Sign in with email" through Entra External ID, at /.auth/login/email.
      customOpenIdConnectProviders: {
        email: {
          enabled: true
          registration: {
            clientId: emailAuthClientId
            clientCredential: {
              method: 'ClientSecretPost'
              clientSecretSettingName: 'EMAIL_AUTHENTICATION_SECRET'
            }
            openIdConnectConfiguration: {
              wellKnownOpenIdConfiguration: emailAuthMetadataUrl
            }
          }
          login: {
            nameClaimType: 'name'
            scopes: ['openid', 'profile', 'email']
          }
        }
      }
    } : {})
  }
}

// Basic-auth publishing credentials stay off: the pipeline deploys with its
// Entra ID identity.
resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'ftp'
  properties: {
    allow: false
  }
}

output name string = app.name
output defaultHostname string = app.properties.defaultHostName
output identityName string = identity.name
output identityClientId string = identity.properties.clientId
