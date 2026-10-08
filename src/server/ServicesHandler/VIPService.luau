local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local VIPService = {}

local configModule = game:GetService("ReplicatedStorage").Modules:FindFirstChild("DataConfig")
local dataConfig = configModule and require(configModule)
local VIPStore = DataStoreService:GetDataStore(dataConfig and dataConfig.VIPStoreName or "PlayerVIP_v1_TESTING")
local vipExpiryCache: {[number]: number} = {}

local function normalizeExpiry(value: any): number
	local n = tonumber(value)
	if not n or n ~= n or math.abs(n) == math.huge then
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

-- Dedicated store is canonical. Import a finite profile expiry only when the
-- dedicated record is absent; stale profile snapshots never override it.
function VIPService.ReconcilePlayer(player: Player, profileExpiry): boolean
	local ok, record = pcall(function()
		return VIPStore:UpdateAsync(tostring(player.UserId), function(old)
			if old ~= nil then
				assert(type(old) == "table", "Corrupt VIP record")
				return old
			end
			return {ExpiresAt = normalizeExpiry(profileExpiry), ProcessedPurchases = {}, AuthorityVersion = 1}
		end)
	end)
	if not ok or type(record) ~= "table" then return false end
	local expiry = tonumber(record.ExpiresAt or 0)
	if not expiry or expiry ~= expiry or math.abs(expiry) == math.huge then return false end
	if player.Parent ~= Players then return false end
	VIPService.ApplyToPlayer(player, normalizeExpiry(expiry))
	return true
end

function VIPService.SetVIPExpiry(userId: number, expiresAt: number): boolean
	expiresAt = normalizeExpiry(expiresAt)
	local ok = pcall(function()
		VIPStore:UpdateAsync(tostring(userId), function(old)
			assert(old == nil or type(old) == "table", "Corrupt VIP record")
			old = old or {}
			old.ExpiresAt = expiresAt
			old.UpdatedAt = os.time()
			return old
		end)
	end)

	if ok then
		VIPService.SetCachedExpiry(userId, expiresAt)
	end

	local player = Players:GetPlayerByUserId(userId)
	if ok and player then
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
			assert(old == nil or type(old) == "table", "Corrupt VIP record")
			old = old or {}
			local currentExpiry = normalizeExpiry(old.ExpiresAt)
			assert(old.ProcessedPurchases == nil or type(old.ProcessedPurchases) == "table", "Corrupt VIP receipts")
			old.ProcessedPurchases = old.ProcessedPurchases or {}
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

-- Caller has acknowledged the durable per-receipt archive. Failure leaves the
-- old marker in place, so retries remain safe.
function VIPService.ArchivePurchase(userId, purchaseId)
	return pcall(function()
		VIPStore:UpdateAsync(tostring(userId), function(old)
			if type(old) ~= "table" then return old end
			if type(old.ProcessedPurchases) == "table" then old.ProcessedPurchases[purchaseId] = nil end
			return old
		end)
	end)
end
function VIPService.ArchiveHistoricalPurchases(userId, receiptStore, limit)
	local ok, value = pcall(function() return VIPStore:UpdateAsync(tostring(userId),function(old) return old end) end)
	if not ok or type(value) ~= "table" or type(value.ProcessedPurchases) ~= "table" then return 0 end
	local archived = 0
	for id, granted in pairs(value.ProcessedPurchases) do
		if archived >= limit then break end
		if granted == true then
			local success, saved = pcall(function()
				return receiptStore:UpdateAsync(id,function(old)
					if old then assert(old == true or type(old) == "table" and old.Granted == true,"Invalid historical VIP receipt"); return old end
					return {Granted=true,PlayerId=userId,Historical=true,Version=1}
				end)
			end)
			if not success or not saved then break end
			if VIPService.ArchivePurchase(userId,id) then archived += 1 end
		end
	end
	return archived
end

return VIPService
