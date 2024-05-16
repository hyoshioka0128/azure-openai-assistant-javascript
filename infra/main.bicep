targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param resourceGroupName string = ''
param webappName string = 'webapp'
param apiServiceName string = 'api'
param appServicePlanName string = ''
param storageAccountName string = ''
param blobContainerName string = 'files'
param webappLocation string // Set in main.parameters.json

// Azure OpenAI -- Cognitive Services
param assistantId string // Set in main.parameters.json

var assistantGpt = {
  modelName: 'gpt-35-turbo'
  deploymentName: 'gpt-35-turbo'
  deploymentVersion: '1106'
  deploymentCapacity: 120
}

param openAiLocation string // Set in main.parameters.json
param openAiSkuName string = 'S0'
param openAiUrl string = ''

var finalOpenAiUrl = empty(openAiUrl) ? 'https://${openAi.outputs.name}.openai.azure.com' : openAiUrl
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// The application frontend webapp
module webapp './core/host/staticwebapp.bicep' = {
  dependsOn: [api]
  name: '${abbrs.webStaticSites}web-${resourceToken}'
  scope: resourceGroup
  params: {
    name: !empty(webappName) ? webappName : '${abbrs.webStaticSites}web-${resourceToken}'
    location: webappLocation
    tags: union(tags, { 'azd-service-name': webappName })
    rg: resourceGroup.name
  }
}

// The application backend API
module api './core/host/functions.bicep' = {
  name: 'api'
  scope: resourceGroup
  params: {
    name: '${abbrs.webSitesFunctions}api-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': apiServiceName })
    alwaysOn: false
    runtimeName: 'node'
    runtimeVersion: '20'
    appServicePlanId: appServicePlan.outputs.id
    storageAccountName: storage.outputs.name
    managedIdentity: true
    appSettings: {
      AZURE_OPENAI_API_ENDPOINT: finalOpenAiUrl
      AZURE_OPENAI_API_DEPLOYMENT_NAME: assistantGpt.deploymentName
     }
  }
  dependsOn: empty(openAiUrl) ? [] : [openAi]
}

// Compute plan for the Azure Functions API
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: resourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
    }
  }
}

// Storage for Azure Functions API
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    allowBlobPublicAccess: false
    containers: [
      {
        name: blobContainerName
        publicAccess: 'None'
      }
    ]
  }
}

module openAi 'core/ai/cognitiveservices.bicep' = if (empty(openAiUrl)) {
  name: 'openai'
  scope: resourceGroup
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: openAiLocation
    tags: tags
    sku: {
      name: openAiSkuName
    }
    disableLocalAuth: true
    deployments: [
      {
        name: assistantGpt.deploymentName
        model: {
          format: 'OpenAI'
          name: assistantGpt.modelName
          version: assistantGpt.deploymentVersion
        }
        sku: {
          name: 'Standard'
          capacity: assistantGpt.deploymentCapacity
        }
      }
    ]
  }
}

// Roles

// System roles
module openAiRoleApi 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'openai-role-api'
  params: {
    principalId: api.outputs.identityPrincipalId
    // Cognitive Services OpenAI User
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

module storageRoleApi 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'storage-role-api'
  params: {
    principalId: api.outputs.identityPrincipalId
    // Storage Blob Data Contributor
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'ServicePrincipal'
  }
}

module openAiRoleOpenAi 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'openai-role-openAi'
  params: {
    principalId: openAi.outputs.identityPrincipalId
    // Cognitive Services OpenAI User
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name

output AZURE_OPENAI_ENDPOINT string = finalOpenAiUrl
output AZURE_DEPLOYMENT_NAME string = assistantGpt.deploymentName
output ASSISTANT_ID string = assistantId

output WEBAPP_URL string = webapp.outputs.uri
output DEPLOYMENT_TOKEN string = webapp.outputs.DEPLOYMENT_TOKEN