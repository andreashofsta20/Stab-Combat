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
local VIPService = require(script.Parent:WaitForChild("VIPService"))


-- // REPLICATED STORAGE MODULES // --
local ReplicatedStorageModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ProductINFO = require(ReplicatedStorageModulesFolder:WaitForChild("ProductIDS"))

local PurchaseGoldRemote = PurchaseGoldRemotesFolder:WaitForChild("PurchaseGoldRemote")

local PurchaseGamePassRemote = RemotesFolder:WaitForChild("ShopRemotes"):WaitForChild("Gamepass"):WaitForChild("BuyGamePass")
local VIPStatusRemote = RemotesFolder:WaitForChild("ShopRemotes"):WaitForChild("VIP"):WaitForChild("VIPStatus")

local VIP_PRODUCT_DURATIONS = {
	[3548752161] = 7 * 24 * 60 * 60,
	[3548752035] = 30 * 24 * 60 * 60,
}



PurchaseGamePassRemote.OnServerEvent:Connect(function(player, msg: string)
	local GamepassID

	if msg == "1" then
		GamepassID = 1733042964
	elseif msg == "2" then
		GamepassID = 1733058985
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
			local finalGoldAmount = goldAmount
			if VIPService.HasVIPByUserId(player.UserId) then
				finalGoldAmount = math.floor(goldAmount * 1.1)
			end
			gold.Value = gold.Value + finalGoldAmount
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
	print("[Purchase] ProcessReceipt received productId=", receiptInfo.ProductId, "playerId=", receiptInfo.PlayerId)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		warn("[Purchase] Player not in server for receipt", receiptInfo.PlayerId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId
	local vipDuration = VIP_PRODUCT_DURATIONS[productId]
	if vipDuration then
		print("[Purchase] VIP receipt detected for", player.Name, "duration=", vipDuration)
		local success, newExpiry = VIPService.GrantDuration(player, vipDuration)
		if not success then
			warn("[Purchase] Failed to grant VIP for", player.Name, "productId=", productId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		VIPStatusRemote:FireClient(player, {
			HasVIP = true,
			ExpiresAt = newExpiry,
			Now = os.time(),
		})
		NotificationHandler.SendNotification(player, "VIP purchase successful", 4, "Success")
		print("[Purchase] VIP granted to", player.Name, "newExpiry=", newExpiry)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productInfo = ProductINFO[productId]
	if not productInfo then
		warn("[Purchase] Unknown productId in ProcessReceipt:", productId)
		NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local goldAmount = productInfo

	processPurchase(player, productId, goldAmount)


	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return {}