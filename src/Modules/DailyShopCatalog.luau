-- Pure deterministic rotation logic, shared by production and security tests.
local Catalog = {}
local ALLOWED_TYPES = {Knife = true, Revolver = true}
local ALLOWED_RARITIES = {Common = true, Rare = true, Epic = true, Legendary = true}
local STARTERS = {}

local function integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum
		and value <= maximum and value % 1 == 0
end

function Catalog.Build(config, definitions, available)
	assert(integer(config.Version, 1, 1000000), "Daily shop Version must be a positive integer")
	assert(integer(config.ResetSeconds, 60, 604800), "Daily shop ResetSeconds must be 60..604800")
	assert(integer(config.ResetOffsetSeconds, 0, config.ResetSeconds - 1), "Invalid daily shop reset offset")
	assert(integer(config.Seed, 1, 2147483646), "Invalid daily shop seed")
	assert(#config.Slots > 0 and #config.Slots <= 12, "Daily shop supports 1..12 slots")
	local entries, issues = {}, {}
	for kind, items in pairs(config.Items) do
		for name, override in pairs(items) do
			if type(override) == "table" and override.Enabled == false then continue end
			local info = ALLOWED_TYPES[kind] and definitions[kind] and definitions[kind][name]
			local defaults = info and config.RarityDefaults[kind] and config.RarityDefaults[kind][info.Rarity]
			local price = type(override) == "table" and (override.Price or defaults and defaults.Price)
			local level = type(override) == "table" and (override.MinLevel or defaults and defaults.MinLevel)
			if type(name) ~= "string" or #name < 1 or #name > 64 or not info
				or not ALLOWED_RARITIES[info.Rarity] or STARTERS[name] or info.tradeable == false
				or not integer(price, 1, 2147483647) or not integer(level, 0, 100)
				or type(info.Image) ~= "string" or (available and not available(kind, name)) then
				table.insert(issues, tostring(kind) .. " / " .. tostring(name))
				continue
			end
			table.insert(entries, {Id = kind .. ":" .. name, ItemType = kind, Name = name,
				ProductName = kind .. " - " .. name, Rarity = info.Rarity, Image = info.Image,
				Price = price, MinLevel = level})
		end
	end
	table.sort(entries, function(a, b) return a.Id < b.Id end)
	return entries, issues
end

function Catalog.Window(config, now)
	local day = math.floor((now - config.ResetOffsetSeconds) / config.ResetSeconds)
	return tostring(config.Version) .. ":" .. tostring(day), day,
		(day + 1) * config.ResetSeconds + config.ResetOffsetSeconds
end

function Catalog.Rotate(config, entries, now)
	local id, day, resetsAt = Catalog.Window(config, now)
	-- Park-Miller: bounded integer arithmetic stays exact in Luau doubles.
	-- Unlike unordered pairs() + math.random(), this is stable across servers.
	local seed = (config.Seed + day * 97 + config.Version * 193) % 2147483646 + 1
	local offers, used = {}, {}
	if config.Enabled then
		for slotIndex, slot in ipairs(config.Slots) do
			assert(ALLOWED_TYPES[slot.ItemType], "Daily shop slots only support Knife/Revolver")
			local candidates = {}
			for _, item in ipairs(entries) do
				if item.ItemType == slot.ItemType and table.find(slot.Rarities, item.Rarity) and not used[item.Id] then
					table.insert(candidates, item)
				end
			end
			seed = seed * 48271 % 2147483647
			if #candidates > 0 then
				local item = candidates[seed % #candidates + 1]
				used[item.Id] = true
				local offer = table.clone(item)
				offer.Slot = slotIndex
				table.insert(offers, offer)
			end
		end
	end
	return {RotationId = id, ResetsAt = resetsAt, Offers = offers, Enabled = config.Enabled == true}
end

function Catalog.Owned(inventory, name)
	local item = inventory and inventory:FindFirstChild(name)
	if not item then return false end
	local quantity = item:FindFirstChild("Quantity")
	return quantity == nil or not quantity:IsA("IntValue") or quantity.Value > 0
end

function Catalog.PurchaseState(offer, owned, purchased, level, cash)
	if purchased then return "Purchased" end
	if owned then return "Owned" end
	if level < offer.MinLevel then return "LevelLocked" end
	if cash < offer.Price then return "InsufficientGold" end
	return "Available"
end

return Catalog
