-- Version 1 policy: never invent/sum stock; preserve questionable rows in a
-- bounded, JSON-safe quarantine. Currency and dedup/recovery corruption stop
-- hydration rather than silently erase authoritative values.
local Schema = {}
local MAX = 2147483647
local function integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum and value <= maximum and value % 1 == 0
end
local function text(value, fallback, limit)
	return type(value) == "string" and #value <= (limit or 200) and value or fallback
end
local function safe(value, depth)
	if type(value) == "number" then return value == value and math.abs(value) < math.huge and value or tostring(value) end
	if type(value) == "string" then return value:sub(1, 300) end
	if type(value) == "boolean" then return value end
	if type(value) ~= "table" or depth >= 4 then return tostring(value) end
	local result, count = {}, 0
	for key, item in pairs(value) do
		count += 1; if count > 64 then result.Truncated = true; break end
		result[tostring(key):sub(1, 100)] = safe(item, depth + 1)
	end
	return result
end
-- Tutorial receipts are authoritative deduplication/entitlement data. Refuse
-- corruption rather than erase a marker and accidentally grant a second reward.
local function tutorialReceipt(source)
	if type(source) ~= "table" or type(source.SessionId) ~= "string" or #source.SessionId == 0 or #source.SessionId > 128
		or source.Id ~= "tutorial:" .. source.SessionId or not integer(source.Version, 1, MAX)
		or not integer(source.CompletedAt, 0, 9007199254740991) or not integer(source.XP, 0, MAX)
		or not integer(source.Gold, 0, MAX) or type(source.Knife) ~= "string" or #source.Knife == 0 or #source.Knife > 64
		or type(source.KnifeRarity) ~= "string" or #source.KnifeRarity == 0 or #source.KnifeRarity > 200
		or type(source.KnifeImage) ~= "string" or #source.KnifeImage > 200 or type(source.KnifeTradeable) ~= "boolean" then return nil end
	local clean = {}
	for _, field in ipairs({"Id", "SessionId", "Version", "CompletedAt", "XP", "Gold", "Knife", "KnifeRarity", "KnifeImage", "KnifeTradeable"}) do
		clean[field] = source[field]
	end
	return clean
end
local function tutorialState(source, knives)
	if source == nil then return {Version = 1, Completed = false} end
	if type(source) ~= "table" or not integer(source.Version, 1, MAX) or type(source.Completed) ~= "boolean"
		or (source.PendingReward ~= nil and source.AppliedReceipt ~= nil) then return nil end
	local clean = {Version = source.Version, Completed = source.Completed}
	for _, field in ipairs({"PendingReward", "AppliedReceipt"}) do
		if source[field] ~= nil then
			local receipt = tutorialReceipt(source[field])
			if not receipt or not source.Completed then return nil end
			-- Pending rewards must still name an available item. Applied receipts
			-- stay valid after a retired item is removed from the live catalog.
			if field == "PendingReward" and type(knives[receipt.Knife]) ~= "table" then return nil end
			clean[field] = receipt
		end
	end
	if source.Completed and clean.PendingReward == nil and clean.AppliedReceipt == nil then return nil end
	return clean
end
function Schema.Validate(source, catalogs)
	if type(source) ~= "table" then return nil, "Profile is not a table" end
	local data = table.clone(source)
	for _, field in ipairs({"Kills", "Deaths", "Wins", "WinStreak", "XP", "Cash"}) do
		if data[field] == nil then data[field] = field == "XP" and 150 or field == "Cash" and 250 or 0 end
		if not integer(data[field], 0, MAX) then return nil, "Invalid authoritative stat: " .. field end
	end
	for _, field in ipairs({"ProcessedPurchases", "TradeJournal"}) do
		if data[field] ~= nil and type(data[field]) ~= "table" then return nil, "Invalid " .. field end
	end
	for key, marker in pairs(data.ProcessedPurchases or {}) do
		if type(key) ~= "string" or #key > 200 or marker ~= true then return nil, "Invalid receipt marker" end
	end
	data.Tutorial = tutorialState(source.Tutorial, catalogs.Inventory)
	if data.Tutorial == nil then return nil, "Invalid tutorial entitlement or reward receipt" end
	local quarantine = {}
	for _, row in ipairs(type(data.InventoryQuarantine) == "table" and data.InventoryQuarantine or {}) do
		if #quarantine >= 128 then return nil, "Inventory quarantine requires review" end
		table.insert(quarantine, safe(row, 0))
	end
	for _, kind in ipairs({"Inventory", "RevolverInventory", "Emotes"}) do
		local original = data[kind] or {}
		if type(original) ~= "table" then return nil, "Invalid inventory container: " .. kind end
		local rows, seen, keys = {}, {}, {}
		for key in pairs(original) do table.insert(keys, key) end
		if #keys > 2048 then return nil, "Inventory row limit exceeded" end
		table.sort(keys, function(a, b)
			if type(a) == "number" and type(b) == "number" then return a < b end
			return type(a) .. tostring(a) < type(b) .. tostring(b)
		end)
		local catalog = catalogs[kind]
		for _, key in ipairs(keys) do
			local row = original[key]
			local name = type(row) == "table" and (row.Name or (type(key) == "string" and key))
			local info = type(name) == "string" and catalog[name]
			local quantity = type(row) == "table" and (row.Quantity == nil and 1 or row.Quantity)
			local reason = not info and "Unknown or invalid item" or not integer(quantity, 1, MAX) and "Invalid quantity"
				or seen[name] and "Duplicate item" or nil
			if reason then
				if #quarantine >= 128 then return nil, "Inventory quarantine requires review" end
				table.insert(quarantine, {Kind = kind, Reason = reason, Row = safe(row, 0)})
			else
				seen[name] = true
				local clean = {Name = name, Quantity = quantity, Rarity = text(info.Rarity, "Common"), Image = text(info.Image, "")}
				if kind == "Emotes" then clean.EmoteId = text(info.EmoteId, "") end
				clean.Tradeable = name ~= "Bowie" and name ~= "Normal Revolver" and row.Tradeable ~= false
				if kind == "RevolverInventory" then clean.Tradeable = clean.Tradeable and info.tradeable == true end
				table.insert(rows, clean)
			end
		end
		data[kind] = rows
	end
	data.InventoryQuarantine, data.DataSchemaVersion = quarantine, 1
	data.Settings = type(data.Settings) == "table" and table.clone(data.Settings) or {}
	for _, field in ipairs({"DaySetting", "LobbySetting", "Notifications", "Trades", "ReducedEffects", "HighContrastCrosshair"}) do
		if type(data.Settings[field]) ~= "boolean" then data.Settings[field] = field == "DaySetting" or field == "Notifications" or field == "Trades" end
	end
	data.DailyRewards = type(data.DailyRewards) == "table" and table.clone(data.DailyRewards) or {}
	for _, field in ipairs({"LastClaimTime", "Streak"}) do
		if not integer(data.DailyRewards[field], 0, 9007199254740991) then data.DailyRewards[field] = 0 end
	end
	for _, field in ipairs({"EquippedKnife", "EquippedGun", "Name", "DisplayName"}) do
		data[field] = text(data[field], field == "EquippedKnife" and "Bowie" or field == "EquippedGun" and "Normal Revolver" or "", 64)
	end
	data.RoundHistory = type(data.RoundHistory) == "table" and data.RoundHistory or {}
	local history = {}
	for _, row in ipairs(data.RoundHistory) do
		if #history >= 10 then break end
		if type(row) == "table" and integer(row.Kills or 0, 0, MAX) and integer(row.Placement or 0, 0, MAX)
			and integer(row.Opponents or 0, 0, MAX) then
			local clean = {Kills = row.Kills or 0, Placement = row.Placement or 0, Opponents = row.Opponents or 0,
				GameMode = text(row.GameMode, "FFA", 32), Timestamp = integer(row.Timestamp, 0, 9007199254740991) and row.Timestamp or 0,
				EntryId = text(row.EntryId, "", 100)}
			table.insert(history, clean)
		end
	end
	data.RoundHistory = history
	if type(data.LastRound) ~= "table" or not integer(data.LastRound.Placement or 0, 0, MAX)
		or not integer(data.LastRound.Kills or 0, 0, MAX) or not integer(data.LastRound.Opponents or 0, 0, MAX) then
		data.LastRound = nil
	elseif data.LastRound then
		data.LastRound = table.clone(data.LastRound); data.LastRound.GameMode = text(data.LastRound.GameMode, "FFA", 32)
	end
	return data
end
return Schema
