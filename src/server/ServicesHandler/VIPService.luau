local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local VIPService = {}

local VIPStore = DataStoreService:GetDataStore("PlayerVIP_v1_TESTING")
local vipExpiryCache: {[number]: number} = {}

local function normalizeExpiry(value: any): number
	local n = tonumber(value)
	if not n then
		return 0
	end
	return math.max(0, math.floor(n))
end

local function isActive(expiresAt: number): boolean
	return expiresAt > os.time()
end

function VIPService.SetCachedExpiry(userId: number, expiresAt: number)
	vipExpiryCache[userId] = normalizeExpiry(expiresAt)
end

function VIPService.GetVIPExpiry(userId: number): number
	local cached = vipExpiryCache[userId]
	if cached ~= nil then
		return cached
	end

	local ok, data = pcall(function()
		return VIPStore:GetAsync(tostring(userId))
	end)

	if not ok then
		return 0
	end

	local expiresAt = type(data) == "table" and normalizeExpiry(data.ExpiresAt) or 0
	vipExpiryCache[userId] = expiresAt
	return expiresAt
end

function VIPService.HasVIPByUserId(userId: number): boolean
	local expiresAt = VIPService.GetVIPExpiry(userId)
	return isActive(expiresAt)
end

function VIPService.GetVIPInfoByUserId(userId: number): (boolean, number)
	local expiresAt = VIPService.GetVIPExpiry(userId)
	return isActive(expiresAt), expiresAt
end

function VIPService.ApplyToPlayer(player: Player, expiresAt: number)
	expiresAt = normalizeExpiry(expiresAt)
	VIPService.SetCachedExpiry(player.UserId, expiresAt)
	player:SetAttribute("VIPExpiresAt", expiresAt)
	player:SetAttribute("HasVIP", isActive(expiresAt))
end

function VIPService.RefreshPlayer(player: Player): (boolean, number)
	local expiresAt = VIPService.GetVIPExpiry(player.UserId)
	VIPService.ApplyToPlayer(player, expiresAt)
	return isActive(expiresAt), expiresAt
end

function VIPService.SetVIPExpiry(userId: number, expiresAt: number): boolean
	expiresAt = normalizeExpiry(expiresAt)
	local ok = pcall(function()
		VIPStore:UpdateAsync(tostring(userId), function(old)
			old = type(old) == "table" and old or {}
			old.ExpiresAt = expiresAt
			old.UpdatedAt = os.time()
			return old
		end)
	end)

	if ok then
		VIPService.SetCachedExpiry(userId, expiresAt)
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		VIPService.ApplyToPlayer(player, expiresAt)
	end

	return ok
end

function VIPService.GrantDuration(player: Player, secondsToAdd: number, purchaseId: string?): (boolean, number)
	secondsToAdd = math.max(0, math.floor(tonumber(secondsToAdd) or 0))
	local now = os.time()
	local newExpiry = now
	local ok = pcall(function()
		VIPStore:UpdateAsync(tostring(player.UserId), function(old)
			old = type(old) == "table" and old or {}
			local currentExpiry = normalizeExpiry(old.ExpiresAt)
			old.ProcessedPurchases = type(old.ProcessedPurchases) == "table" and old.ProcessedPurchases or {}
			if purchaseId and old.ProcessedPurchases[purchaseId] then
				newExpiry = currentExpiry
				return old
			end
			newExpiry = math.max(now, currentExpiry) + secondsToAdd
			old.ExpiresAt = newExpiry
			old.UpdatedAt = now
			if purchaseId then
				old.ProcessedPurchases[purchaseId] = true
			end
			return old
		end)
	end)
	if ok then
		VIPService.SetCachedExpiry(player.UserId, newExpiry)
		VIPService.ApplyToPlayer(player, newExpiry)
	else
		VIPService.ApplyToPlayer(player, VIPService.GetVIPExpiry(player.UserId))
	end

	return ok, newExpiry
end

Players.PlayerRemoving:Connect(function(player)
	vipExpiryCache[player.UserId] = nil
end)

return VIPService
