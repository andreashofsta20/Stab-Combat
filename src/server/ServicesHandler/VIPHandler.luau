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
local nextPrompt, nextStatus, statusLoading = {}, {}, {}
local PROMPT_COOLDOWN, STATUS_COOLDOWN = 0.75, 1

local function pushStatusToClient(player: Player)
	if player.Parent ~= Players or player:GetAttribute("DataReady") ~= true or statusLoading[player] then return end
	statusLoading[player] = true
	local ok, hasVIP, expiresAt = pcall(VIPService.GetVIPInfoByUserId, player.UserId)
	statusLoading[player] = nil
	if not ok or player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return end
	player:SetAttribute("HasVIP", hasVIP)
	player:SetAttribute("VIPExpiresAt", expiresAt)
	VIPStatusRemote:FireClient(player, {
		HasVIP = hasVIP,
		ExpiresAt = expiresAt,
		Now = os.time(),
	})
end

BuyVIPRemote.OnServerEvent:Connect(function(player: Player, subscriptionType)
	if player:GetAttribute("DataReady") ~= true then return end
	if type(subscriptionType) ~= "number" and type(subscriptionType) ~= "string" then return end
	if type(subscriptionType) == "string" and #subscriptionType > 32 then return end
	local productId = tonumber(subscriptionType)
	if not productId then
		if subscriptionType == "1_WEEK" then
			productId = ONE_WEEK_PRODUCT_ID
		elseif subscriptionType == "1_MONTH" then
			productId = ONE_MONTH_PRODUCT_ID
		end
	end

	if not productId or not VALID_VIP_PRODUCT_IDS[productId] then
		return
	end
	local now = os.clock()
	if now < (nextPrompt[player] or 0) then return end
	nextPrompt[player] = now + PROMPT_COOLDOWN

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
	local now = os.clock()
	if now < (nextStatus[player] or 0) then return end
	nextStatus[player] = now + STATUS_COOLDOWN

	pushStatusToClient(player)
end)

local readyConnections = {}
local function observePlayer(player)
	if readyConnections[player] then return end
	readyConnections[player] = player:GetAttributeChangedSignal("DataReady"):Connect(function()
		if player.Parent == Players then pushStatusToClient(player) end
	end)
	if player:GetAttribute("DataReady") == true then task.spawn(pushStatusToClient, player) end
end
Players.PlayerAdded:Connect(observePlayer)
for _, player in ipairs(Players:GetPlayers()) do observePlayer(player) end
Players.PlayerRemoving:Connect(function(player)
	if readyConnections[player] then readyConnections[player]:Disconnect(); readyConnections[player] = nil end
	nextPrompt[player], nextStatus[player], statusLoading[player] = nil, nil, nil
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
