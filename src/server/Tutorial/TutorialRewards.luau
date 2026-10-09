-- Tutorial completion is an entitlement written by the verified server lesson.
-- TeleportData and client requests never authorize a reward. PendingReward is
-- saved before the return teleport; the main place applies its frozen terms.
-- The economy delta and AppliedReceipt share one session-locked profile record.
local Rewards = {}
local MAX = 2147483647

local function integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum and value <= maximum and value % 1 == 0
end
local function boundedText(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end
local function validReceipt(receipt)
	return type(receipt) == "table" and boundedText(receipt.Id, 160)
		and boundedText(receipt.SessionId, 128) and receipt.Id == "tutorial:" .. receipt.SessionId
		and integer(receipt.Version, 1, MAX) and integer(receipt.CompletedAt, 0, 9007199254740991)
		and integer(receipt.XP, 0, MAX) and integer(receipt.Gold, 0, MAX)
		and boundedText(receipt.Knife, 64) and boundedText(receipt.KnifeRarity, 200)
		and type(receipt.KnifeImage) == "string" and #receipt.KnifeImage <= 200
		and type(receipt.KnifeTradeable) == "boolean"
end
local function sameReceipt(a, b)
	if not validReceipt(a) or not validReceipt(b) then return false end
	for _, field in ipairs({"Id", "SessionId", "Version", "CompletedAt", "XP", "Gold", "Knife", "KnifeRarity", "KnifeImage", "KnifeTradeable"}) do
		if a[field] ~= b[field] then return false end
	end
	return true
end
local function stateOf(profile)
	local data = profile and profile.Data
	if type(data) ~= "table" then return "Invalid" end
	local state = data.Tutorial
	if state == nil then return "Eligible" end
	if type(state) ~= "table" or not integer(state.Version, 1, MAX) or type(state.Completed) ~= "boolean" then return "Invalid" end
	if state.PendingReward ~= nil and state.AppliedReceipt ~= nil then return "Invalid" end
	if state.PendingReward ~= nil then
		return state.Completed == true and validReceipt(state.PendingReward) and "Earned" or "Invalid"
	end
	if state.AppliedReceipt ~= nil then
		return state.Completed == true and validReceipt(state.AppliedReceipt) and "Granted" or "Invalid"
	end
	return state.Completed == false and "Eligible" or "Invalid"
end

function Rewards.Assess(profile)
	return stateOf(profile)
end
function Rewards.ReadReceipt(profile)
	local status = stateOf(profile)
	if status ~= "Earned" and status ~= "Granted" then return nil end
	local state = profile.Data.Tutorial
	return table.clone(state.AppliedReceipt or state.PendingReward)
end

-- Dependencies make backend outages, reloads and duplicate calls testable.
-- Snapshot and Publish must be synchronous; Save may yield.
function Rewards.New(deps)
	assert(type(deps) == "table" and type(deps.Profile) == "function" and type(deps.Save) == "function"
		and type(deps.Snapshot) == "function" and type(deps.Publish) == "function" and type(deps.Knives) == "table", "Missing tutorial reward dependencies")
	local engine, busy = {}, {}
	local now = deps.Now or os.time
	local function authority(player, profile)
		return player ~= nil and profile ~= nil and deps.Profile(player) == profile
			and player:GetAttribute("DataReady") == true and profile:IsActive()
			and (deps.Present == nil or deps.Present(player))
	end
	local function confirm(player, profile, receipt, applied, config)
		local timeout = config and config.RewardSaveTimeoutSeconds or 20
		if not integer(timeout, 1, 120) then return false, "Invalid save timeout" end
		local function saved(data)
			local state = type(data) == "table" and data.Tutorial
			if type(state) ~= "table" or state.Completed ~= true then return false end
			if applied then return state.PendingReward == nil and sameReceipt(state.AppliedReceipt, receipt) end
			return sameReceipt(state.PendingReward, receipt) or sameReceipt(state.AppliedReceipt, receipt)
		end
		if saved(profile.LastSavedData) then return true end
		local ok, result = pcall(deps.Save, player, profile, saved, timeout)
		-- Save returning true alone is insufficient: inspect the backend snapshot.
		if not ok or result ~= true or not saved(profile.LastSavedData) then return false, "Reward save pending" end
		return true
	end
	local function run(player, operation)
		if busy[player] then return false, "Reward operation in progress" end
		busy[player] = true
		local ok, result, detail = pcall(operation)
		busy[player] = nil
		if not ok then return false, "Reward operation failed: " .. tostring(result) end
		return result, detail
	end

	function engine.MarkEarned(player, profile, sessionId, config)
		if not authority(player, profile) then return false, "Profile unavailable" end
		if not boundedText(sessionId, 128) then return false, "Invalid tutorial session" end
		return run(player, function()
			local status = stateOf(profile)
			if status == "Invalid" then return false, "Invalid tutorial record" end
			if status ~= "Eligible" then
				local receipt = Rewards.ReadReceipt(profile)
				if receipt.SessionId ~= sessionId then return false, "Tutorial reward already earned" end
				local saved, reason = confirm(player, profile, receipt, status == "Granted", config)
				return saved, saved and receipt or reason
			end
			local terms = type(config) == "table" and config.Rewards
			local version = type(config) == "table" and config.Version
			if type(terms) ~= "table" or not integer(version, 1, MAX)
				or not integer(terms.XP, 0, MAX) or not integer(terms.Gold, 0, MAX)
				or not boundedText(terms.Knife, 64) then return false, "Invalid tutorial reward configuration" end
			local knife = deps.Knives[terms.Knife]
			if type(knife) ~= "table" or not boundedText(knife.Rarity, 200)
				or type(knife.Image) ~= "string" or #knife.Image > 200 then return false, "Tutorial reward knife missing from catalog" end
			local receipt = {Id = "tutorial:" .. sessionId, SessionId = sessionId, Version = version, CompletedAt = now(),
				XP = terms.XP, Gold = terms.Gold, Knife = terms.Knife, KnifeRarity = knife.Rarity,
				KnifeImage = knife.Image, KnifeTradeable = terms.Knife ~= "Bowie"}
			if not validReceipt(receipt) then return false, "Invalid tutorial receipt" end
			-- No yields between the final ownership check and marking entitlement.
			if not authority(player, profile) then return false, "Profile unavailable" end
			profile.Data.Tutorial = {Version = version, Completed = true, PendingReward = receipt}
			local saved, reason = confirm(player, profile, receipt, false, config)
			return saved, saved and table.clone(receipt) or reason
		end)
	end

	function engine.Commit(player, profile, sessionId, config)
		if not authority(player, profile) then return false, "Profile unavailable" end
		return run(player, function()
			local status = stateOf(profile)
			if status == "Invalid" then return false, "Invalid tutorial record" end
			if status == "Eligible" then return false, "No earned tutorial reward" end
			local receipt = Rewards.ReadReceipt(profile)
			if sessionId ~= nil and receipt.SessionId ~= sessionId then return false, "Tutorial session mismatch" end
			if status == "Granted" then
				local saved, reason = confirm(player, profile, receipt, true, config)
				return saved, saved and receipt or reason
			end
			-- Recovery grants only an acknowledged entitlement. An ambiguous write
			-- is retried as the same receipt rather than applying a second delta.
			local earned, earnedReason = confirm(player, profile, receipt, false, config)
			if not earned then return false, earnedReason end
			if not authority(player, profile) then return false, "Profile unavailable" end
			if player:GetAttribute("InventoryLocked") == true then return false, "Inventory recovery pending" end
			if type(deps.Knives[receipt.Knife]) ~= "table" then return false, "Tutorial reward knife missing from catalog" end
			deps.Snapshot(player)
			if not authority(player, profile) then return false, "Profile unavailable" end
			local data = profile.Data
			if not integer(data.XP, 0, MAX - receipt.XP) or not integer(data.Cash, 0, MAX - receipt.Gold)
				or type(data.Inventory) ~= "table" then return false, "Reward would exceed profile limits" end
			local inventory, found, names = {}, false, {}
			for _, row in ipairs(data.Inventory) do
				if type(row) ~= "table" or not boundedText(row.Name, 64) or names[row.Name]
					or not integer(row.Quantity, 1, MAX) then return false, "Invalid inventory for tutorial reward" end
				names[row.Name] = true
				local clean = table.clone(row)
				if clean.Name == receipt.Knife then
					if clean.Quantity >= MAX then return false, "Reward would exceed inventory limits" end
					clean.Quantity += 1
					found = true
				end
				table.insert(inventory, clean)
			end
			if not found then
				if #inventory >= 2048 then return false, "Inventory row limit exceeded" end
				table.insert(inventory, {Name = receipt.Knife, Quantity = 1, Rarity = receipt.KnifeRarity,
					Image = receipt.KnifeImage, Tradeable = receipt.KnifeTradeable})
			end
			local oldXP, oldCash, oldInventory, oldTutorial = data.XP, data.Cash, data.Inventory, data.Tutorial
			player:SetAttribute("InventoryLocked", true)
			-- OnSave must preserve canonical data if publication/rollback fails
			-- after changing only part of the replicated currency/inventory.
			player:SetAttribute("TutorialRewardPublishing", true)
			-- The marker and all three grants are mutated without yielding.
			data.XP, data.Cash, data.Inventory = oldXP + receipt.XP, oldCash + receipt.Gold, inventory
			data.Tutorial = {Version = receipt.Version, Completed = true, AppliedReceipt = table.clone(receipt)}
			local published, publishError = pcall(deps.Publish, player, data)
			if not published then
				data.XP, data.Cash, data.Inventory, data.Tutorial = oldXP, oldCash, oldInventory, oldTutorial
				local restored = pcall(deps.Publish, player, data)
				-- Keep the writer lock if rollback publication itself fails.
				if restored then
					player:SetAttribute("TutorialRewardPublishing", false)
					player:SetAttribute("InventoryLocked", false)
				end
				return false, "Reward publication failed: " .. tostring(publishError)
			end
			player:SetAttribute("TutorialRewardPublishing", false)
			local saved, reason = confirm(player, profile, receipt, true, config)
			-- Published Values now match the profile, including on save timeout.
			-- Keep AppliedReceipt in memory: the next retry saves, never regrants.
			player:SetAttribute("InventoryLocked", false)
			return saved, saved and receipt or reason
		end)
	end
	function engine.Recover(player, profile, config)
		local status = stateOf(profile)
		if status == "Eligible" then return true, nil end
		return engine.Commit(player, profile, nil, config)
	end
	engine.Assess, engine.ReadReceipt = Rewards.Assess, Rewards.ReadReceipt
	return engine
end

local runtime
local function getRuntime()
	if runtime then return runtime end
	local Players = game:GetService("Players")
	local modules = game:GetService("ReplicatedStorage").Modules
	local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
	local Inventory = require(script.Parent.Parent.DataStore.ProfileInventory)
	runtime = Rewards.New({Profile = Profiles.GetProfile, Snapshot = Profiles.SyncProfile, Save = Profiles.ConfirmSave,
		Knives = require(modules.KnivesInfo), Present = function(player) return player.Parent == Players end,
		Publish = function(player, data)
			local stats = player:FindFirstChild("leaderstats")
			assert(stats and stats:FindFirstChild("XP") and stats.XP:IsA("IntValue")
				and stats:FindFirstChild("Cash") and stats.Cash:IsA("IntValue")
				and stats:FindFirstChild("Inventory") and stats.Inventory:IsA("Folder"), "Reward replication is unavailable")
			stats.XP.Value, stats.Cash.Value = data.XP, data.Cash
			Inventory.Publish(player, data)
		end})
	return runtime
end
function Rewards.MarkEarned(player, profile, sessionId, config)
	return getRuntime().MarkEarned(player, profile, sessionId, config)
end
function Rewards.Commit(player, profile, sessionId, config)
	return getRuntime().Commit(player, profile, sessionId, config)
end
function Rewards.Recover(player, profile, config)
	return getRuntime().Recover(player, profile, config)
end
return Rewards
