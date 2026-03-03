local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))
local VIPService = require(script.Parent:WaitForChild("VIPService"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local VIPRemotesFolder = RemotesFolder:WaitForChild("ShopRemotes"):WaitForChild("VIP")

local BuyVIPRemote = VIPRemotesFolder:WaitForChild("BuyVIP")
local VIPStatusRemote = VIPRemotesFolder:WaitForChild("VIPStatus")

local ONE_WEEK_PRODUCT_ID = 3548752161
local ONE_MONTH_PRODUCT_ID = 3548752035
local VALID_VIP_PRODUCT_IDS = {
	[ONE_WEEK_PRODUCT_ID] = true,
	[ONE_MONTH_PRODUCT_ID] = true,
}

local function pushStatusToClient(player: Player)
	local hasVIP, expiresAt = VIPService.GetVIPInfoByUserId(player.UserId)
	player:SetAttribute("HasVIP", hasVIP)
	player:SetAttribute("VIPExpiresAt", expiresAt)
	VIPStatusRemote:FireClient(player, {
		HasVIP = hasVIP,
		ExpiresAt = expiresAt,
		Now = os.time(),
	})
end

BuyVIPRemote.OnServerEvent:Connect(function(player: Player, subscriptionType)
	print("[VIP] BuyVIPRemote fired by", player.Name, "payload:", subscriptionType)
	local productId = tonumber(subscriptionType)
	if not productId then
		if subscriptionType == "1_WEEK" then
			productId = ONE_WEEK_PRODUCT_ID
		elseif subscriptionType == "1_MONTH" then
			productId = ONE_MONTH_PRODUCT_ID
		end
	end

	if not productId or not VALID_VIP_PRODUCT_IDS[productId] then
		warn("[VIP] Invalid VIP product payload from", player.Name, subscriptionType)
		return
	end

	local success = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)

	if not success then
		NotificationHandler.SendNotification(player, "Failed to open VIP purchase.", 4, "Error")
		warn("[VIP] PromptProductPurchase failed for", player.Name, "productId:", productId)
	else
		print("[VIP] Prompted purchase for", player.Name, "productId:", productId)
	end
end)

VIPStatusRemote.OnServerEvent:Connect(function(player: Player, requestType: string)
	if requestType ~= "REQUEST_STATUS" then
		return
	end

	pushStatusToClient(player)
end)

Players.PlayerAdded:Connect(function(player)
	VIPService.RefreshPlayer(player)
	pushStatusToClient(player)
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if not VALID_VIP_PRODUCT_IDS[productId] then
		return
	end

	print("[VIP] Prompt finished userId=", userId, "productId=", productId, "wasPurchased=", wasPurchased)
	local player = Players:GetPlayerByUserId(userId)
	if player and not wasPurchased then
		NotificationHandler.SendNotification(player, "VIP purchase canceled.", 3, "Error")
	end
end)



return {}