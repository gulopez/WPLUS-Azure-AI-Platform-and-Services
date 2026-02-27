# RestoreLab – Lab Environment Setup Guide

This guide provides step-by-step instructions for restoring the complete lab environment using the **RestoreLab.ps1** script.

## Prerequisites

- **RestoreLab.ps1** script (upload to Azure Cloud Shell)
- Skillable lab access with Azure subscription
- PowerShell environment available in Azure Cloud Shell

## Setup Instructions

### Step 1: Launch the Skillable Lab

Start your Skillable lab session.

### Step 2: Prepare Notepad

Open Notepad on your local machine to temporarily store credentials and resource names.

### Step 3: Copy Username

1. In Skillable Lab, go to the **Resources** tab
2. Click **Keyboard** → **Username**
3. Paste the username into Notepad

### Step 4: Copy TAP (Temporary Access Password)

1. In Skillable Lab **Resources** tab, click **Keyboard** 
2. Click **Password** (or TAP)
3. Paste the password into a new line in Notepad

### Step 5: Open Browser Session

1. In Skillable Lab **Resources** tab, click the **URL icon**
2. This opens a browser session connected to your Azure environment

### Step 6: Login to Azure Portal

1. Copy the **Username** from Notepad
2. Paste it into the browser login prompt

### Step 7: Enter Password

1. Copy the **TAP (Password)** from Notepad
2. Paste it into the password field in the browser

### Step 8: Complete Authentication

Complete any additional authentication steps (MFA, etc.) as prompted.

### Step 9: Open Cloud Shell

1. Inside the Azure Portal, look for the blue menu bar at the top
2. Click the **Cloud Shell icon** (looks like `>_` or `{ }`)

### Step 10: Verify PowerShell Shell

Ensure the Cloud Shell is running **PowerShell** (not Bash):
- If it shows `bash`, click the dropdown and select **PowerShell**
- Wait for the PowerShell environment to initialize

### Step 11: Upload RestoreLab.ps1

1. Click **Manage files** in Cloud Shell
2. Click **Upload**
3. Select the **RestoreLab.ps1** file from your local machine
4. Wait for the upload to complete

### Step 12: Copy the Foundry Resource Name

1. Go to the **Instructions** tab in Skillable Lab
2. Navigate to **Required Lab Setup** → **Step 4**
3. Copy the Foundry resource name (e.g., `ai-foundry-5948377011`)
4. Paste it into Notepad

### Step 13: Run the RestoreLab Script

Replace the Foundry name with the value you copied and run:

```powershell
.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011"
```

## Advanced Usage – Custom Parameters

By default, **RestoreLab.ps1** uses these defaults:
- **ResourceGroupName**: `azureaiworkshoprg`
- **ProjectName**: `firstProject`
- **Location**: `eastus2`
- **DeployModels**: `$true`

To override these defaults, pass custom values:

```powershell
.\RestoreLab.ps1 `
  -FoundryName "ai-foundry-5948377011" `
  -ResourceGroupName "azureaiworkshoprg" `
  -ProjectName "firstProject" `
  -Location "eastus2"
```

### Skip Optional Steps

To skip Bing Grounding or AI Search connections:

```powershell
.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011" -SkipBing

.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011" -SkipAISearch

.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011" -SkipBing -SkipAISearch
```

To skip model deployments:

```powershell
.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011" -DeployModels $false
```

## What RestoreLab.ps1 Does

The script automates the entire lab setup in three phases:

### Phase 1: Deploy AI Foundry
- Creates the AI Foundry account (Cognitive Services)
- Creates the project under the account
- Deploys default AI models:
  - GPT-4o
  - GPT-4o-mini
  - Text Embedding 3 Large
  - Text Embedding Ada 002

### Phase 2: Connect Bing Grounding
- Finds the existing Bing Search service in the resource group
- Creates a `BingLLMSearch` connection to the Foundry project
- Enables Bing grounding for AI applications

### Phase 3: Connect Azure AI Search
- Finds the existing Azure AI Search service in the resource group
- Creates a `CognitiveSearch` connection to the Foundry account
- Enables semantic search and RAG patterns

## Output – Environment Variables

After successful execution, the script displays a consolidated block of `.env` variables:

```
AZURE_OPENAI_ENDPOINT=https://...
AZURE_OPENAI_API_KEY=...
MODEL_DEPLOYMENT_NAME=gpt-4o
MODEL_NAME=gpt-4o
MODEL_VERSION=2024-11-20
AZURE_OPENAI_CHAT_ENDPOINT=...
MODEL_MINI_DEPLOYMENT_NAME=gpt-4o-mini
...
GROUNDING_WITH_BING_CONNECTION_NAME=...
AZURE_SEARCH_CONNECTION_NAME=...
AZURE_SEARCH_ENDPOINT=...
AZURE_SEARCH_KEY=...
```

**Copy these values into your `.env` file** for your application.

## Troubleshooting

### Script Fails with "Azure CLI not found"
- Ensure Azure Cloud Shell is open and initialized
- Verify you are in PowerShell (not Bash)

### "Resource group does not exist"
- Verify the resource group name is correct
- Check that you are authenticated to the correct Azure subscription

### Model deployment fails
- Some model deployments may require quota increases
- Models may be deployed asynchronously – check the Azure Portal
- The script will continue even if some models fail to deploy

### Connection creation fails
- Verify the Bing/Search resources exist in the resource group
- Check that the Foundry account exists
- Review error messages for API compatibility issues

## Next Steps

After RestoreLab completes:

1. **Open AI Foundry Portal**: https://ai.azure.com
2. **Verify resources**: Check all connections and models are present
3. **Review environment variables**: Use the `.env` output for your applications
4. **Test connections**: Create a simple prompt in the Playground to verify setup

## Support

For issues or questions:
- Check the **Error Messages** section in the RestoreLab output
- Review Azure Portal resource states
- Consult the AI Foundry documentation: https://learn.microsoft.com/en-us/azure/ai-services/ai-services-overview
