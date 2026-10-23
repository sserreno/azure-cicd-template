// Azure SQL logical server plus one database, signed in to with Entra ID
// only (docs/adr/0003-sql-with-managed-identity.md).
// free: the serverless free offer, which pauses rather than bills when its
//       monthly allowance runs out.
// paid: the given SKU, always available.
param serverName string
param databaseName string
param location string
param tags object
param adminGroupName string
param adminGroupObjectId string

@allowed(['free', 'paid'])
param tier string

@description('SKU name for the paid tier, e.g. Basic, S0 or GP_S_Gen5_1.')
param paidSku string

resource server 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: adminGroupName
      sid: adminGroupObjectId
      tenantId: tenant().tenantId
      // Everyone, including the app's managed identity, signs in with Entra ID.
      azureADOnlyAuthentication: true
    }
  }
}

// No firewall rules here: the pipeline allows exactly the app's outbound
// addresses after each deploy (scripts/sync-sql-firewall.sh).

var freeDatabase = {
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
    autoPauseDelay: 60
    minCapacity: json('0.5')
    maxSizeBytes: 34359738368 // 32 GB, the free offer's limit
    requestedBackupStorageRedundancy: 'Local'
    zoneRedundant: false
  }
}

// Serverless vCore SKUs (GP_S_*) never auto-pause on the paid tier, so the
// app never waits for a resume.
var paidDatabase = {
  sku: {
    name: paidSku
  }
  properties: union({
    requestedBackupStorageRedundancy: 'Local'
    zoneRedundant: false
  }, startsWith(paidSku, 'GP_S_') ? { autoPauseDelay: -1, minCapacity: json('0.5') } : {})
}

var database = tier == 'free' ? freeDatabase : paidDatabase

resource db 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: server
  name: databaseName
  location: location
  tags: tags
  sku: database.sku
  properties: database.properties
}

output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = db.name
