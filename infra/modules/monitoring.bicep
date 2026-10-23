// Paid tier only: Application Insights on a Log Analytics workspace, with a
// daily ingestion cap so a noisy app can't run up the bill.
param workspaceName string
param insightsName string
param location string
param tags object

@description('Daily ingestion cap in GB. 0.5 GB/day stays near the monthly free grant.')
param dailyQuotaGb string = '0.5'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: json(dailyQuotaGb)
    }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

output connectionString string = insights.properties.ConnectionString
