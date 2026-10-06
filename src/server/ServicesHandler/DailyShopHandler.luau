local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(RS.Modules.DailyShopConfig)
local Catalog = require(RS.Modules.DailyShopCatalog)
local Levels = require(RS.Modules.CalculateLevel)
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local Inventory = require(script.Parent.Parent.DataStore.InventoryHandler)
local Remote = RS:WaitForChild("Remotes"):WaitForChild("ShopRemotes")
	:WaitForChild("PurchaseGold"):WaitForChild("PurchaseGoldRemote")
local Shop = {}
local cached
local lastRequest, lastPurchase, busy = {}, {}, {}
local FOLDERS = {Knife = "Inventory", Revolver = "RevolverInventory"}

local function currentRotation()
	local now = os.time()
	local id = Catalog.Window(Config, now)
	if not cached or cached.RotationId ~= id then
		local entries, issues = Catalog.Build(Config, {
			Knife = require(RS.Modules.KnivesInfo), Revolver = require(RS.Modules.RevolversInfo),
		}, function(kind, name)
			local folder = ServerStorage:FindFirstChild(kind == "Knife" and "Knives" or "Revolvers")
			local tool = folder and folder:FindFirstChild(name)
			return tool ~= nil and tool:IsA("Tool")
		end)
		if #issues > 0 then warn("[DailyShop] Excluded missing/invalid catalog items: " .. table.concat(issues, ", ")) end
		cached = Catalog.Rotate(Config, entries, now)
	end
	return cached
end

local function context(player)
	local profile = Profiles.GetProfile(player)
	if player.Parent ~= Players or player:GetAttribute("DataReady") ~= true or not profile or not profile:IsActive() then return end
	local stats = player:FindFirstChild("leaderstats")
	local cash, xp = stats and stats:FindFirstChild("Cash"), stats and stats:FindFirstChild("XP")
	if not cash or not xp or not cash:IsA("IntValue") or not xp:IsA("IntValue")
		or cash.Value < 0 or xp.Value < 0 then return end
	return profile, stats, cash, Levels.GetLevel(xp.Value)
end

local function purchaseHistory(profile, rotation)
	local history = profile.Data.DailyShop
	if type(history) ~= "table" or history.RotationId ~= rotation.RotationId or type(history.Purchased) ~= "table" then
		history = {RotationId = rotation.RotationId, Purchased = {}}
		profile.Data.DailyShop = history
	end
	return history
end

function Shop.GetSnapshot(player)
	local rotation = currentRotation()
	local profile, stats, cash, level = context(player)
	local result = {Kind = Config.Protocol.Response, RotationId = rotation.RotationId,
		ResetsAt = rotation.ResetsAt, ServerNow = os.time(), Enabled = rotation.Enabled,
		Ready = profile ~= nil, Offers = {}}
	if not profile then return result end
	local history = purchaseHistory(profile, rotation)
	result.Cash, result.Level = cash.Value, level
	for _, offer in ipairs(rotation.Offers) do
		local copy = table.clone(offer)
		copy.Owned = Catalog.Owned(stats:FindFirstChild(FOLDERS[offer.ItemType]), offer.Name)
		copy.Purchased = history.Purchased[offer.Id] == true
		copy.State = Catalog.PurchaseState(offer, copy.Owned, copy.Purchased, level, cash.Value)
		table.insert(result.Offers, copy)
	end
	return result
end

local function buy(player, rotationId, itemId)
	local rotation = currentRotation()
	if not rotation.Enabled then return "Disabled" end
	if rotationId ~= rotation.RotationId then return "Expired" end
	local offer
	for _, candidate in ipairs(rotation.Offers) do if candidate.Id == itemId then offer = candidate; break end end
	if not offer then return "Unavailable" end
	local profile, stats, cash, level = context(player)
	if not profile then return "Loading" end
	local folder = stats:FindFirstChild(FOLDERS[offer.ItemType])
	if not folder then return "Loading" end
	local history = purchaseHistory(profile, rotation)
	local state = Catalog.PurchaseState(offer, Catalog.Owned(folder, offer.Name), history.Purchased[itemId] == true, level, cash.Value)
	if state ~= "Available" then return state end
	-- Recheck content policy even if a catalog table was accidentally changed.
	if offer.Rarity == "Godly" or not FOLDERS[offer.ItemType] then return "Unavailable" end
	-- No yielding work between checks, charge, grant and history. All three are
	-- saved together in the existing session-locked ProfileStore player record.
	local oldCash = cash.Value
	local existing = folder:FindFirstChild(offer.Name)
	local quantity = existing and existing:FindFirstChild("Quantity")
	local oldQuantity = quantity and quantity.Value
	cash.Value -= offer.Price
	local ok, granted = pcall(function()
		if offer.ItemType == "Knife" then return Inventory.AddKnife(player, offer.Name) end
		return Inventory.AddRevolver(player, offer.Name, 1)
	end)
	if not ok or not granted then
		cash.Value = oldCash
		if existing then
			if quantity then quantity.Value = oldQuantity end
		else
			local partial = folder:FindFirstChild(offer.Name)
			if partial then partial:Destroy() end
		end
		warn("[DailyShop] Item grant failed:", player.UserId, offer.Id, ok and "no item returned" or granted)
		return "GrantFailed"
	end
	history.Purchased[itemId] = true
	return "Success"
end

local function allowed(cooldowns, player, seconds)
	local now = os.clock()
	if cooldowns[player] and now - cooldowns[player] < seconds then return false end
	cooldowns[player] = now
	return true
end

function Shop.HandleRemote(player, action, rotationId, itemId)
	if player.Parent ~= Players or busy[player] then return end
	if action == Config.Protocol.Request then
		if rotationId ~= nil or itemId ~= nil or not allowed(lastRequest, player, Config.RequestCooldown) then return end
	elseif action == Config.Protocol.Buy then
		if type(rotationId) ~= "string" or #rotationId > 40 or type(itemId) ~= "string"
			or #itemId < 1 or #itemId > 80 or not allowed(lastPurchase, player, Config.PurchaseCooldown) then return end
	else return end
	busy[player] = true
	local ok, payload = pcall(function()
		local code = action == Config.Protocol.Buy and buy(player, rotationId, itemId) or nil
		local snapshot = Shop.GetSnapshot(player)
		snapshot.Code, snapshot.ItemId = code, itemId
		return snapshot
	end)
	busy[player] = nil
	if player.Parent ~= Players then return end
	if ok then
		Remote:FireClient(player, payload)
	else
		warn("[DailyShop] Request failed:", payload)
		Remote:FireClient(player, {Kind = Config.Protocol.Response, Ready = false, Code = "Error", Offers = {}})
	end
	if ok and payload.Code == "Success" then
		-- Queue the normal profile save after releasing the non-yielding transaction.
		Profiles.SaveProfile(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player], lastPurchase[player], busy[player] = nil, nil, nil
end)

return Shop
