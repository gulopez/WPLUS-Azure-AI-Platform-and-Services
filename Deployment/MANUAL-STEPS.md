# Manual Steps - Connect Resources in AI Foundry Portal

After running the deployment script, you need to manually connect the Bing and AI Search resources to your AI Foundry. This is because these connections require portal-based configuration.

## Prerequisites

✅ Deployment script has completed successfully  
✅ All resources are created in Azure  
✅ You have the resource names from the script output  

---

## 🔗 Step 1: Connect Bing Resource

### 1.1 Open AI Foundry Portal

1. Go to [https://ai.azure.com](https://ai.azure.com/)
2. Sign in with your Azure credentials
3. Click **Azure AI Foundry** at the top left
4. Click on your AI Foundry (e.g., `ai-foundry-53439517`)

![Navigate to AI Foundry](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/aifoundryfromaifoundryportal.png)

### 1.2 Navigate to Connected Resources

1. On the left side, in the **Management Center** section
2. Under **Resource**, click **Connected resources**

![Connected Resources](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/foundryconnectedresources.png)

### 1.3 Add Bing Connection

1. Click **+ New connection**
2. In the search box, type **bing**
3. Click **Grounding with Bing Search**

![New Bing Connection](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/newconnbing1.png)

4. Review the name of the Bing resource (e.g., `gwbing-53439517`)
5. Click **Add connection** on the right

![Add Bing Connection](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/gwbingaddconn.png)

6. Wait for the green tick with "Connected" label
7. Click **Close** button

![Bing Connected](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/gwbingconnected.png)

### 1.4 Verify Bing Connection

1. You should see the Bing resource in the Connected resources list

![Bing in List](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/gwbingconnectedinlist.png)

✅ **Bing connection complete!**

---

## 🔍 Step 2: Connect Azure AI Search

### 2.1 Navigate to Connected Resources

(Same as Step 1.2 if you're continuing from above)

1. Ensure you're in **Management Center** → **Connected resources**

### 2.2 Add AI Search Connection

1. Click **+ New connection**
2. Click **Azure AI Search**

![New AI Search Connection](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/newconnaisearch.png)

3. Review the name of the AI Search service (e.g., `aisearch-53439517`)
4. Click **Add connection** on the right

![Add AI Search Connection](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/aisearchaddconn.png)

5. Wait for the green tick with "Connected" label
6. Click **Close** button

![AI Search Connected](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/aisearchconnected.png)

### 2.3 Verify AI Search Connection

1. You should see the AI Search service in the Connected resources list

![AI Search in List](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/aisearchconnectedinlist.png)

✅ **AI Search connection complete!**

---

## ✅ Step 3: Verify All Connections

### 3.1 Check Connected Resources List

You should now see all connected resources:

- **Bing Grounding** (e.g., `gwbing-53439517`)
- **Azure AI Search** (e.g., `aisearch-53439517`)
- Plus any default connections created with the AI Foundry

### 3.2 Verify Model Deployments

1. In the left menu, scroll down to **Models + endpoints**
2. Verify you see these models:
   - ✅ gpt-4o
   - ✅ gpt-4o-mini
   - ✅ text-embedding-3-large
   - ✅ text-embedding-ada-002

![Models List](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/images/listofmodelsdeployed.png)

---

## 🎉 All Done!

Your Azure AI Foundry is now fully configured with:

✅ AI Foundry Hub and Project  
✅ Four AI models deployed  
✅ Bing Grounding connected  
✅ Azure AI Search connected  
✅ .env file updated with all keys and endpoints  

---

## 🔧 Troubleshooting

### Can't find the resource in the connection dialog?

**Problem:** The Bing or AI Search resource doesn't appear in the list

**Solutions:**
1. Wait 2-3 minutes for Azure to fully provision the resource
2. Refresh the page
3. Verify the resource exists in [Azure Portal](https://portal.azure.com)
4. Check that the resource is in the same subscription

### Connection fails with permission error?

**Problem:** "You don't have permission to connect this resource"

**Solutions:**
1. Verify you have Contributor role on both resources
2. Check that both resources are in the same subscription
3. Ensure the AI Foundry has the necessary managed identity permissions

### Can't see Management Center?

**Problem:** The Management Center menu is not visible

**Solutions:**
1. Make sure you're on the AI Foundry hub page, not the project page
2. Click "Azure AI Foundry" at the top left to go back to the hub
3. Try refreshing the page

---

## 📚 Related Documentation

- [Lab 00 - 03: Connect to Bing Resources](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/03-Connect-to-Bing-Resources.md)
- [Lab 00 - 04: Connect to Azure AI Search](Lab%2000%20-%20Prequisite%20-%20AI%20Foundry%20Resource%20Creation/04-Connect-to-Azure-AI-Search.md)

---

## ⏱️ Expected Time

- **Bing Connection:** 1-2 minutes
- **AI Search Connection:** 1-2 minutes
- **Verification:** 1 minute
- **Total:** 3-5 minutes

---

**Need Help?** Review the screenshots in the lab documentation folders for visual guidance.
