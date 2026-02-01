-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketPlaceService = game:GetService("MarketplaceService")

-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ShopRemotesFolder = RemotesFolder:WaitForChild("ShopRemotes")
local PurchaseGoldRemotesFolder = ShopRemotesFolder:WaitForChild("PurchaseGold")


-- // MODULES // --
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))


-- // REPLICATED STORAGE MODULES // --
local ReplicatedStorageModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ProductINFO = require(ReplicatedStorageModulesFolder:WaitForChild("ProductIDS"))

local PurchaseGoldRemote = PurchaseGoldRemotesFolder:WaitForChild("PurchaseGoldRemote")

local PurchaseGamePassRemote = RemotesFolder:WaitForChild("ShopRemotes"):WaitForChild("Gamepass"):WaitForChild("BuyGamePass")



PurchaseGamePassRemote.OnServerEvent:Connect(function(player, msg: string)
	local GamepassID

	if msg == "1" then
		GamepassID = 1269395072
	else
		return
	end

	local success, errorMessage = pcall(function()
		MarketPlaceService:PromptGamePassPurchase(player, GamepassID)
	end)

	if not success then
		NotificationHandler.SendNotification(player, "Something went wrong", 3, "Error")
	end
end)



local function processPurchase(player, productId, goldAmount)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local gold = leaderstats:FindFirstChild("Cash")
		if gold then
			gold.Value = gold.Value + goldAmount
			NotificationHandler.SendNotification(player, "Purchase successful", 3, "Success")
		end
	end

	print(player.Name .. " purchased " .. goldAmount .. "ProductID: " .. productId)
end

PurchaseGoldRemote.OnServerEvent:Connect(function(player: Player, productID: number)
	local productInfo = ProductINFO[productID]
	if not productInfo then
		return
	end

	local goldAmount = productInfo 

	local success, errorMessage = pcall(function()
		MarketPlaceService:PromptProductPurchase(player, productID)
	end)

	if not success then
		warn("Failed to prompt purchase for " .. player.Name .. ": " .. errorMessage)
		NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
		return
	end
end)


MarketPlaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId
	local productInfo = ProductINFO[productId]
	if not productInfo then
		NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local goldAmount = productInfo

	processPurchase(player, productId, goldAmount)


	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return {}