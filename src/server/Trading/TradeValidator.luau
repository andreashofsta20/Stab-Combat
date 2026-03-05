local TradeValidator = {}

local Players = game:GetService("Players")

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
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "Player leaderstats not found"
	end
	
	for _, item in ipairs(items) do
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
		local ownedQuantity = quantityValue and quantityValue.Value or 1
		
		if item.Quantity > ownedQuantity then
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

-- Remove items from a player's inventory
local function RemoveItems(player: Player, items: {any})
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	for _, item in ipairs(items) do
		local folder = leaderstats:FindFirstChild(item.Type)
		if folder then
			local itemInstance = folder:FindFirstChild(item.Name)
			if itemInstance then
				local quantityValue = itemInstance:FindFirstChild("Quantity")
				if quantityValue then
					quantityValue.Value -= item.Quantity
					
					-- Remove if quantity is 0
					if quantityValue.Value <= 0 then
						itemInstance:Destroy()
					end
				else
					-- No quantity value, just remove the item
					itemInstance:Destroy()
				end
			end
		end
	end
	
	return true
end

-- Add items to a player's inventory
local function GiveItems(player: Player, items: {any})
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	for _, item in ipairs(items) do
		local folder = leaderstats:FindFirstChild(item.Type)
		if folder then
			local existingItem = folder:FindFirstChild(item.Name)
			
			if existingItem then
				-- Item exists, add to quantity
				local quantityValue = existingItem:FindFirstChild("Quantity")
				if quantityValue then
					quantityValue.Value += item.Quantity
				end
			else
				-- Create new item
				local newItem = Instance.new("StringValue")
				newItem.Name = item.Name
				newItem.Parent = folder
				
				local quantity = Instance.new("IntValue")
				quantity.Name = "Quantity"
				quantity.Value = item.Quantity
				quantity.Parent = newItem
				
				local rarity = Instance.new("StringValue")
				rarity.Name = "Rarity"
				rarity.Value = item.Rarity or "Common"
				rarity.Parent = newItem
				
				-- Add image if it's inventory type
				if item.Type == "Inventory" then
					local image = Instance.new("StringValue")
					image.Name = "Image"
					image.Value = item.Image or "1"
					image.Parent = newItem

					local tradeable = Instance.new("BoolValue")
					tradeable.Name = "Tradeable"
					tradeable.Value = item.Tradeable ~= false
					tradeable.Parent = newItem
				end
			end
		end
	end
	
	return true
end

-- Execute the trade atomically with rollback safety
function TradeValidator.ExecuteTrade(session: any)
	-- Re-validate ownership right before execution (TOCTOU protection)
	local valid1, err1 = TradeValidator.ValidatePlayerItems(session.Player1, session.Player1Items)
	if not valid1 then
		return false, "Trade failed: " .. err1
	end
	local valid2, err2 = TradeValidator.ValidatePlayerItems(session.Player2, session.Player2Items)
	if not valid2 then
		return false, "Trade failed: " .. err2
	end

	-- Remove items from both players
	local removed1 = RemoveItems(session.Player1, session.Player1Items)
	local removed2 = RemoveItems(session.Player2, session.Player2Items)
	
	if not removed1 or not removed2 then
		-- Rollback: give back any items that were removed
		if removed1 then
			GiveItems(session.Player1, session.Player1Items)
		end
		if removed2 then
			GiveItems(session.Player2, session.Player2Items)
		end
		return false, "Failed to remove items — trade rolled back"
	end
	
	-- Give items to both players
	local given1 = GiveItems(session.Player1, session.Player2Items)
	local given2 = GiveItems(session.Player2, session.Player1Items)
	
	if not given1 or not given2 then
		-- Critical failure — items removed but can't give. Attempt rollback.
		if not given1 then
			GiveItems(session.Player1, session.Player1Items)
		end
		if not given2 then
			GiveItems(session.Player2, session.Player2Items)
		end
		return false, "Failed to give items — trade rolled back"
	end
	
	return true
end

return TradeValidator
