# Azure AI Foundry Deployment Automation

This PowerShell script automates the complete deployment of an Azure AI Foundry environment, including all required resources and configurations.

## 🎯 What This Script Does

The script automates the following tasks based on the lab instructions:

1. **Creates Azure AI Foundry Resource** (from `01-Create-Azure-Foundry-Project.md`)
   - Creates the AI Foundry hub
   - Creates the default project: `firstProject`

2. **Deploys AI Models** (from `02-Deploy-Models.md`)
   - gpt-4o
   - gpt-4o-mini
   - text-embedding-3-large
   - text-embedding-ada-002

3. **Creates Bing Grounding Resource** (from `Optional-01-Create-Bing-resource.md`)
   - Sets up Grounding with Bing Search

4. **Creates Azure AI Search Resource** (from `Optional-02-Create-Azure-AI-Search.md`)
   - Deploys AI Search service with Basic tier
   - Configures 1 replica, 1 partition
   - Enables free semantic search
   - Enables public network access with API key authentication

5. **Creates Cosmos DB Resource** (from `Cosmos.json`)
   - Deploys Cosmos DB with NoSQL API
   - Enables Vector Search capability
   - Creates RetailDB database and Products container
   - Configures Session consistency level
   - Enables automatic failover

6. **Creates SQL Server and Database** (from `SQLDB.json`)
   - Deploys SQL Server with secure authentication
   - Creates vectordb database
   - Configures GP_Gen5 SKU (2 vCores, 32GB)
   - Sets up firewall rules for Azure services
   - Generates and stores admin credentials

7. **Creates PostgreSQL Flexible Server** (from `postgres.json`)
   - Deploys PostgreSQL 15 Flexible Server
   - Creates books database
   - Configures Standard_D2s_v3 SKU (GeneralPurpose, 128GB)
   - Enables vector and Azure AI extensions
   - Sets up public network access
   - Generates and stores admin credentials

8. **Collects Configuration Information**
   - Retrieves all endpoints
   - Retrieves all API keys
   - Gathers subscription and tenant information

9. **Updates .env File**
   - Automatically populates all environment variables
   - Updates existing values or adds new ones

## 📋 Prerequisites

Before running the script, ensure you have:

- **Azure CLI** installed
  - Download from: https://aka.ms/installazurecliwindows
  - Verify installation: `az --version`

- **Azure Subscription** with appropriate permissions
  - Ability to create resources
  - Contributor or Owner role recommended

- **PowerShell 5.1 or higher**
  - Check version: `$PSVersionTable.PSVersion`

- **Lab Instance ID**
  - This is used for naming resources (e.g., `ai-foundry-53439517`)
  - The script will prompt you if not provided

## 🚀 How to Run

### Option 1: Basic Execution (Recommended)

```powershell
.\Deploy-AzureAIFoundry.ps1
```

The script will prompt you for the Lab Instance ID.

### Option 2: With Lab Instance ID Parameter

```powershell
.\Deploy-AzureAIFoundry.ps1 -LabInstanceId "53439517"
```

### Option 3: With Custom Parameters

```powershell
.\Deploy-AzureAIFoundry.ps1 `
    -ResourceGroupName "azureaiworkshoprg" `
    -Location "eastus2" `
    -LabInstanceId "53439517"
```

## 📝 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ResourceGroupName` | No | `azureaiworkshoprg` | Name of the resource group |
| `Location` | No | `eastus2` | Azure region for deployment |
| `LabInstanceId` | Yes* | - | Lab instance ID for naming (*prompted if not provided) |

## 🎨 Script Features

- **Color-coded output** for easy reading
- **Progress indicators** for each step
- **Error handling** with helpful messages
- **Idempotent execution** - safe to run multiple times
- **Automatic login** if not already authenticated
- **Comprehensive summary** at the end

## 📂 Resources Created

The script creates the following resources with naming pattern:

| Resource Type | Naming Pattern | Example |
|---------------|----------------|---------|
| AI Foundry Hub | `ai-foundry-{LabInstanceId}` | `ai-foundry-53439517` |
| AI Foundry Project | `firstProject` | `firstProject` |
| Bing Resource | `gwbing-{LabInstanceId}` | `gwbing-53439517` |
| AI Search | `aisearch-{LabInstanceId}` | `aisearch-53439517` |
| Cosmos DB | `cosmosaivector-{LabInstanceId}` | `cosmosaivector-53439517` |
| SQL Server | `sqlaivector-{LabInstanceId}` | `sqlaivector-53439517` |
| SQL Database | `vectordb` | `vectordb` |
| PostgreSQL Server | `pgaivector-{LabInstanceId}` | `pgaivector-53439517` |
| PostgreSQL Database | `books` | `books` |

## 🔧 What Gets Updated in .env File

The script updates or adds the following environment variables:

```bash
AI_FOUNDRY_PROJECT_ENDPOINT=https://...
AI_FOUNDRY_NAME=ai-foundry-53439517
AZURE_PROJECT_NAME=firstProject
AZURE_OPENAI_ENDPOINT=https://...
AZURE_OPENAI_BASE_URL_ENDPOINT=https://...
AZURE_OPENAI_API_KEY=...
MODEL_DEPLOYMENT_NAME=gpt-4o
MODEL_API_VERSION=2025-01-01-preview
AZURE_OPENAI_EMBEDDING_ENDPOINT=https://...
AZURE_OPENAI_EMBEDDING_API_KEY=...
EMBEDDING_MODEL_DEPLOYMENT_NAME=text-embedding-3-large
EMBEDDING_MODEL_API_VERSION=2023-05-15
AZURE_OPENAI_EMBEDDING_ADA_ENDPOINT=https://...
AZURE_OPENAI_EMBEDDING_ADA_API_KEY=...
EMBEDDING_ADA_MODEL_DEPLOYMENT_NAME=text-embedding-ada-002
EMBEDDING_ADA_MODEL_API_VERSION=2023-05-15
GROUNDING_WITH_BING_CONNECTION_NAME=gwbing-53439517
TENANT_ID=...
AZURE_SUBSCRIPTION_ID=...
AZURE_RESOURCE_GROUP=azureaiworkshoprg
AZURE_AI_SEARCH_ENDPOINT=https://aisearch-53439517.search.windows.net
AZURE_AI_SEARCH_API_KEY=...
COSMOS_ENDPOINT=https://cosmosaivector-53439517.documents.azure.com:443/
COSMOS_KEY=...
SQL_SERVER=sqlaivector-53439517.database.windows.net
SQL_PWD=...
POSTGRES_HOST=pgaivector-53439517.postgres.database.azure.com
POSTGRES_USER=postgres
POSTGRES_PASSWORD=...
POSTGRES_DATABASE=books
POSTGRES_PORT=5432
```

## ⚠️ Important Notes

### Manual Steps Still Required

Due to Azure CLI limitations with AI Foundry, you may need to complete these steps manually in the portal:

1. **Connect Bing Resource to AI Foundry**
   - Visit: https://ai.azure.com
   - Navigate to your AI Foundry
   - Go to **Management Center** → **Connected Resources**
   - Click **+ New Connection** → **Grounding with Bing Search**
   - Select your Bing resource and click **Add Connection**

2. **Connect AI Search to AI Foundry**
   - Same location as above
   - Click **+ New Connection** → **Azure AI Search**
   - Select your AI Search service and click **Add Connection**

### Model Deployment Notes

- Model deployment can take several minutes
- Some models may require quota approval
- If a model fails to deploy, deploy it manually in the AI Foundry portal

## 🔍 Troubleshooting

### "Azure CLI is not installed"
- Install from: https://aka.ms/installazurecliwindows
- Restart PowerShell after installation

### "Not logged in to Azure"
- The script will automatically run `az login`
- Follow the browser authentication prompts

### "Resource already exists"
- The script is idempotent and will skip existing resources
- If you want to recreate, delete the resources in the portal first

### Model Deployment Fails
- Check quota limits in your subscription
- Some models require approval
- Deploy manually in the portal: https://ai.azure.com

### Permission Denied Errors
- Ensure you have Contributor or Owner role
- Contact your subscription administrator

## 📊 Expected Execution Time

- **Fast path** (resources exist): 2-3 minutes
- **Full deployment**: 25-35 minutes
  - AI Foundry creation: 2-5 minutes
  - Model deployments: 10-15 minutes (cumulative)
  - Bing & AI Search: 2-3 minutes
  - Cosmos DB: 5-10 minutes
  - SQL Server & Database: 3-5 minutes
  - PostgreSQL Server & Database: 5-10 minutes
  - Configuration collection: 1 minute

## 🎓 Next Steps After Deployment

1. **Verify in Azure Portal**
   ```
   https://portal.azure.com
   ```
   - Navigate to your resource group
   - Verify all resources are created

2. **Configure in AI Foundry Portal**
   ```
   https://ai.azure.com
   ```
   - Connect Bing and AI Search resources
   - Verify model deployments
   - Test the deployed models

3. **Verify .env File**
   - Check that all values are populated
   - Ensure no placeholder values remain

4. **Test Your Setup**
   - Run the lab notebooks
   - Verify connectivity to all services

## 📝 Example Output

```
═══════════════════════════════════════════════════════════════
  Checking Prerequisites
═══════════════════════════════════════════════════════════════

→ Checking Azure CLI installation...
✓ Azure CLI is installed (version: 2.58.0)
→ Checking Azure login status...
✓ Logged in to Azure (Subscription: Visual Studio Enterprise)

═══════════════════════════════════════════════════════════════
  Setting Up Resource Group
═══════════════════════════════════════════════════════════════

→ Checking if resource group 'azureaiworkshoprg' exists...
✓ Resource group 'azureaiworkshoprg' already exists

═══════════════════════════════════════════════════════════════
  Creating Azure AI Foundry Resource
═══════════════════════════════════════════════════════════════

→ Creating AI Foundry: ai-foundry-53439517
→ Project Name: firstProject
→ Creating AI Foundry hub...
✓ AI Foundry hub created successfully
→ Creating AI Foundry project: firstProject...
✓ AI Foundry project created successfully

...
```

## 🤝 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the original lab instructions
3. Verify your Azure permissions
4. Check Azure service health status

## 📄 License

This script is provided as-is for educational purposes as part of the Azure AI Workshop.

---

**Happy Deploying! 🚀**
