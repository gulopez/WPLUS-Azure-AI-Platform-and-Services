1- Launch the Skillable Lab

2- Open Notepad

3- Go to Resources Tab and click  Keybopard - > Username to copy the username in notepad

4- In a new line click  Keybopard - > Tap to copy the username in notepad

5- In the Skillable lab in the Resources Tab click on the URL icon to open up a browser session in your Laptop

6- Copy the Username from the notepad to the browser session

7- Copy the TAP value from the notepad to the browser session

8- Complete the Authentication

9- Inside the Azure portal, in the blue menu on top click the icon for Cloud Shell

10- Make sure the shell is running Powershell

11- Click on Manage Files - Upload -> Select the RestoreLab.ps1 stored locally

12 - Go to Instructions Tab in the Skillable Lab and Required Lab Setup - Step 4 -> copy the name of the Foundry resource in Notepad

13 Replace the name of the Foundry resource in the command bellow

.\RestoreLab.ps1 -FoundryName "ai-foundry-5948377011"

by Default the script sets a default  Resource Group, Project Name and Deployment Location but it is possible to pass different values in case you want to run this in your own subscription

#Example
.\RestoreLab.ps1  -FoundryName "ai-foundry-5948377011" -ResourceGroupName "azureaiworkshoprg" -ProjectName "firstProject"

