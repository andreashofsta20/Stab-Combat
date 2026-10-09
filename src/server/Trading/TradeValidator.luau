local TradeValidator = {}

local VALID_ITEM_TYPES = {
	Inventory = true,
	Emotes = true,
}

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
		and value % 1 == 0
end

local function countKnifeSlots(items: {any})
	local count = 0
	for _, item in ipairs(items or {}) do
		if item.Type == "Inventory" then
			count += 1
		end
	end
	return count
end

function TradeValidator.ValidatePlayerItems(player: Player, items: {any})
	if player:GetAttribute("DataReady") ~= true then return false, "Player data is still loading" end
	if player:GetAttribute("TutorialTravelPending")==true or player:GetAttribute("TutorialActive")==true then return false,"Player is entering training" end
	if type(items) ~= "table" or #items > 32 then
		return false, "Invalid trade items"
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "Player leaderstats not found"
	end
	
	local totals: {[string]: number} = {}
	for _, item in ipairs(items) do
		if type(item) ~= "table"
			or type(item.Type) ~= "string"
			or type(item.Name) ~= "string"
			or #item.Name < 1
			or #item.Name > 64
			or not VALID_ITEM_TYPES[item.Type]
			or not isPositiveInteger(item.Quantity) then
			return false, "Invalid item payload"
		end

		local itemKey = item.Type .. "\0" .. item.Name
		totals[itemKey] = (totals[itemKey] or 0) + item.Quantity
		if totals[itemKey] > 2147483647 then
			return false, "Item quantity is too large"
		end

		local folder = leaderstats:FindFirstChild(item.Type)
		if not folder then
			return false, "Invalid item type: " .. item.Type
		end
		
		local itemInstance = folder:FindFirstChild(item.Name)
		if not itemInstance then
			return false, "Item not found: " .. item.Name
		end

		local tradeableValue = itemInstance:FindFirstChild("Tradeable")
		if tradeableValue and tradeableValue:IsA("BoolValue") and tradeableValue.Value == false then
			return false, "Item is not tradeable: " .. item.Name
		end
		
		local quantityValue = itemInstance:FindFirstChild("Quantity")
		if quantityValue and not quantityValue:IsA("IntValue") then return false, "Invalid inventory quantity" end
		local ownedQuantity = quantityValue and quantityValue.Value or 1
		
		if totals[itemKey] > ownedQuantity then
			return false, "Not enough of item: " .. item.Name
		end
	end
	
	return true
end

-- Validate the entire trade
function TradeValidator.ValidateTrade(session: any)

	if not session.Player1.Parent or not session.Player2.Parent then
		return false, "A player left the game"
	end
	
	local valid1, err1 = TradeValidator.ValidatePlayerItems(session.Player1, session.Player1Items)
	if not valid1 then
		return false, "Player1 validation failed: " .. err1
	end
	
	local valid2, err2 = TradeValidator.ValidatePlayerItems(session.Player2, session.Player2Items)
	if not valid2 then
		return false, "Player2 validation failed: " .. err2
	end

	if countKnifeSlots(session.Player1Items) > 4 or countKnifeSlots(session.Player2Items) > 4 then
		return false, "You can only offer 4 knives"
	end
	
	-- Check both players locked
	if not session:BothPlayersLocked() then
		return false, "Both players must lock in"
	end
	
	return true
end

-- Prepare both final inventories before publishing either side. Detached
-- originals are retained until both commits succeed, allowing full rollback.
local function preparePlayer(player, outgoing, incoming, replacements)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return false, "Player inventory unavailable" end
	local entries = {}
	local function entry(item)
		local key = item.Type .. "\0" .. item.Name
		if entries[key] then return entries[key] end
		local folder = stats:FindFirstChild(item.Type)
		if not folder then return nil end
		local original = folder:FindFirstChild(item.Name)
		if original and not original:IsA("StringValue") then return nil end
		local quantity = original and original:FindFirstChild("Quantity")
		if quantity and not quantity:IsA("IntValue") then return nil end
		local owned = original and (quantity and quantity.Value or 1) or 0
		if owned < 0 or owned % 1 ~= 0 or owned > 2147483647 then return nil end
		local result = {folder = folder, original = original, owned = owned, outgoing = 0, incoming = 0, metadata = item}
		entries[key] = result
		return result
	end
	for _, item in ipairs(outgoing) do
		local record = entry(item)
		if not record then return false, "Invalid offered inventory" end
		record.outgoing += item.Quantity
	end
	for _, item in ipairs(incoming) do
		local record = entry(item)
		if not record then return false, "Invalid receiving inventory" end
		record.incoming += item.Quantity
	end
	for _, record in pairs(entries) do
		local final = record.owned - record.outgoing + record.incoming
		if record.outgoing > record.owned or final < 0 or final > 2147483647 then return false, "Invalid resulting quantity" end
		table.insert(replacements, record)
		if final > 0 then
			local item = record.original and record.original:Clone() or Instance.new("StringValue")
			record.replacement = item
			item.Name = record.metadata.Name
			if not record.original then
				local metadata = record.metadata
				item.Value = metadata.Type == "Emotes" and (metadata.EmoteId or "") or ""
				local rarity = Instance.new("StringValue")
				rarity.Name, rarity.Value, rarity.Parent = "Rarity", metadata.Rarity or "Common", item
				if metadata.Type == "Inventory" then
					local image = Instance.new("StringValue")
					image.Name, image.Value, image.Parent = "Image", metadata.Image or "", item
					local tradeable = Instance.new("BoolValue")
					tradeable.Name, tradeable.Value, tradeable.Parent = "Tradeable", metadata.Tradeable ~= false, item
				end
			end
			local quantity = item:FindFirstChild("Quantity") or Instance.new("IntValue")
			quantity.Name, quantity.Value, quantity.Parent = "Quantity", final, item
		end
	end
	return true
end

function TradeValidator.ExecuteTrade(session: any)
	if not session or session.ExecutionStarted or session.State ~= "LOCKED" then
		return false, "Trade is not ready for execution"
	end
	session.ExecutionStarted = true
	local valid, reason = TradeValidator.ValidateTrade(session)
	if not valid then session.ExecutionStarted = false; return false, reason end

	local replacements = {}
	local function discard()
		for _, record in ipairs(replacements) do
			if record.replacement then record.replacement:Destroy() end
		end
	end
	local prepared, result, err = pcall(function()
		local ok, why = preparePlayer(session.Player1, session.Player1Items, session.Player2Items, replacements)
		if not ok then return false, why end
		return preparePlayer(session.Player2, session.Player2Items, session.Player1Items, replacements)
	end)
	if not prepared or not result then
		discard()
		return false, prepared and err or "Trade preparation failed"
	end

	-- No yields between validation, preparation, and committing both players.
	local committed = pcall(function()
		for _, record in ipairs(replacements) do
			if record.original then record.original.Parent = nil end
			if record.replacement then record.replacement.Parent = record.folder end
		end
	end)
	if not committed then
		for _, record in ipairs(replacements) do
			if record.replacement then record.replacement.Parent = nil end
			if record.original then record.original.Parent = record.folder end
		end
		discard()
		return false, "Trade commit failed; original inventories restored"
	end
	for _, record in ipairs(replacements) do
		if record.original then record.original:Destroy() end
	end
	return true
end

return TradeValidator
