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
local PURCHASE_PROMPT_COOLDOWN = 0.75
local lastPromptAt: {[number]: number} = {}
local processingReceipts: {[string]: number} = {}
local maintainingUsers: {[number]: boolean} = {}

local function canPrompt(player: Player): boolean
	local now = os.clock()
	local previous = lastPromptAt[player.UserId]
	if previous and (now - previous) < PURCHASE_PROMPT_COOLDOWN then
		return false
	end
	lastPromptAt[player.UserId] = now
	return true
end



PurchaseGamePassRemote.OnServerEvent:Connect(function(player, msg: string)
	if type(msg) ~= "string" then
		return
	end
	if not canPrompt(player) then
		return
	end

	local GamepassID

	if msg == "1" or msg == "1733042964" then
		GamepassID = 1733042964
	elseif msg == "2" or msg == "1733058985" then
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



local ProfileManager = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("ProfileManager"))

local function processPurchase(player, productId, goldAmount, purchaseId): boolean
	local profile = ProfileManager.GetProfile(player)
	if not profile or not profile:IsActive() or player:GetAttribute("DataReady") ~= true then
		return false
	end
	profile.Data.ProcessedPurchases = profile.Data.ProcessedPurchases or {}
	if profile.Data.ProcessedPurchases[purchaseId] then
		return ProfileManager.ConfirmPurchase(player, purchaseId)
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Cash")
	if not gold then
		return false
	end
	local finalGoldAmount = goldAmount
	if VIPService.HasVIPByUserId(player.UserId) then
		finalGoldAmount = math.floor(goldAmount * 1.1)
	end
	-- A cache miss may yield while checking VIP. Recheck session ownership.
	if not player.Parent or ProfileManager.GetProfile(player) ~= profile or not profile:IsActive()
		or player:GetAttribute("DataReady") ~= true then return false end
	gold.Value += finalGoldAmount
	profile.Data.ProcessedPurchases[purchaseId] = true
	-- Keep the in-memory grant/marker on a timeout. A queued save may succeed
	-- later; retries confirm that same grant instead of awarding it twice.
	if not ProfileManager.ConfirmPurchase(player, purchaseId) then return false end
	NotificationHandler.SendNotification(player, "Purchase successful", 3, "Success")

	print(player.Name .. " purchased " .. goldAmount .. "ProductID: " .. productId)
	return true
end

PurchaseGoldRemote.OnServerEvent:Connect(function(player: Player, productID, rotationId, itemId)
	-- Tagged daily-shop commands share this existing remote. Numeric gold
	-- product IDs retain the original MarketplaceService purchase flow.
	if productID == "REQUEST_DAILY_SHOP" or productID == "BUY_DAILY_ITEM" then
		require(script.Parent.DailyShopHandler).HandleRemote(player, productID, rotationId, itemId)
		return
	end
	if typeof(productID) ~= "number" or productID ~= productID or math.abs(productID) == math.huge then
		return
	end
	productID = math.floor(productID)
	if productID <= 0 then
		return
	end
	if not canPrompt(player) then
		return
	end

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

Players.PlayerRemoving:Connect(function(player)
	lastPromptAt[player.UserId] = nil
end)


local DataStoreService = game:GetService("DataStoreService")
local configModule = ReplicatedStorage.Modules:FindFirstChild("DataConfig")
local dataConfig = configModule and require(configModule)
local PurchaseReceiptStore = DataStoreService:GetDataStore(dataConfig and dataConfig.ReceiptStoreName or "PurchaseReceipts_v1")
local ReceiptArchive = require(script.Parent.ReceiptArchive)

local function isReceiptProcessed(purchaseId: string): (boolean, boolean)
	return ReceiptArchive.Check(PurchaseReceiptStore, purchaseId)
end

MarketPlaceService.ProcessReceipt = function(receiptInfo)
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if processingReceipts[purchaseId] or maintainingUsers[receiptInfo.PlayerId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processingReceipts[purchaseId] = receiptInfo.PlayerId
	local function finish(decision)
		return decision
	end

	local ok, decision = pcall(function()
		-- Idempotency: check if this receipt was already processed
		local receiptRead, receiptProcessed = isReceiptProcessed(purchaseId)
		if not receiptRead then
			return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
		end
		if receiptProcessed then
			return finish(Enum.ProductPurchaseDecision.PurchaseGranted)
		end

		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			warn("[Purchase] Player not in server for receipt", receiptInfo.PlayerId)
			return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
		end

		local productId = receiptInfo.ProductId
		local vipDuration = VIP_PRODUCT_DURATIONS[productId]
		if vipDuration then
			local profile = ProfileManager.GetProfile(player)
			if not profile or not profile:IsActive() then return finish(Enum.ProductPurchaseDecision.NotProcessedYet) end
			-- A cross-server retry can have read archive absence before the old
			-- server finished archival. The owned profile's durable marker is
			-- the second replay barrier, even after the VIP hot marker is pruned.
			if profile.Data.ProcessedPurchases and profile.Data.ProcessedPurchases[purchaseId] then
				return finish(ProfileManager.ConfirmPurchase(player,purchaseId) and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet)
			end
			print("[Purchase] VIP receipt detected for", player.Name, "duration=", vipDuration)
			local success, newExpiry = VIPService.GrantDuration(player, vipDuration, purchaseId)
			if not success then
				warn("[Purchase] Failed to grant VIP for", player.Name, "productId=", productId)
				return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
			end

			VIPStatusRemote:FireClient(player, {
				HasVIP = true,
				ExpiresAt = newExpiry,
				Now = os.time(),
			})
			NotificationHandler.SendNotification(player, "VIP purchase successful", 4, "Success")
			local profile = ProfileManager.GetProfile(player)
			if not profile or not profile:IsActive() or player:GetAttribute("DataReady") ~= true then
				return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
			end
			profile.Data.ProcessedPurchases = profile.Data.ProcessedPurchases or {}
			profile.Data.ProcessedPurchases[purchaseId] = true
			if not ProfileManager.ConfirmPurchase(player, purchaseId) then return finish(Enum.ProductPurchaseDecision.NotProcessedYet) end
			return finish(Enum.ProductPurchaseDecision.PurchaseGranted)
		end

		local productInfo = ProductINFO[productId]
		if not productInfo then
			warn("[Purchase] Unknown productId in ProcessReceipt:", productId)
			NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
			return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
		end

		local goldAmount = productInfo

		if not processPurchase(player, productId, goldAmount, purchaseId) then
			return finish(Enum.ProductPurchaseDecision.NotProcessedYet)
		end
		return finish(Enum.ProductPurchaseDecision.PurchaseGranted)
	end)
	-- Unexpected errors must also release the per-receipt lock. A retry will
	-- confirm the existing marker if the grant happened before the error.
	if not ok then
		processingReceipts[purchaseId] = nil
		ReplicatedStorage:SetAttribute("ReceiptErrorCount", (ReplicatedStorage:GetAttribute("ReceiptErrorCount") or 0) + 1)
		warn("[Purchase] Receipt processing failed:", purchaseId, decision)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		-- Grants and their profile/VIP markers are already durable here. Archive
		-- first, then remove hot markers. An archive outage keeps all markers.
		if not ReceiptArchive.Commit(PurchaseReceiptStore, receiptInfo) then
			processingReceipts[purchaseId] = nil
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if player then ReceiptArchive.PruneProfile(ProfileManager.GetProfile(player), purchaseId) end
		if VIP_PRODUCT_DURATIONS[receiptInfo.ProductId] then VIPService.ArchivePurchase(receiptInfo.PlayerId, purchaseId) end
	end
	processingReceipts[purchaseId] = nil
	return decision
end

local function isProcessing(userId)
	for _, owner in pairs(processingReceipts) do if owner == userId then return true end end
	return false
end
return {
	IsProcessing = isProcessing,
	Maintain = function(userId, fn)
		if maintainingUsers[userId] or isProcessing(userId) then return false end
		maintainingUsers[userId] = true
		local ok, result = pcall(fn)
		maintainingUsers[userId] = nil
		return ok, result
	end,
}
