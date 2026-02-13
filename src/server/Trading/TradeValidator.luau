local TradeValidator = {}

local Players = game:GetService("Players")

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
				end
			end
		end
	end
	
	return true
end

-- Execute the trade atomically
function TradeValidator.ExecuteTrade(session: any)
	-- Remove items from both players
	local removed1 = RemoveItems(session.Player1, session.Player1Items)
	local removed2 = RemoveItems(session.Player2, session.Player2Items)
	
	if not removed1 or not removed2 then
		error("Failed to remove items")
	end
	
	-- Give items to both players
	local given1 = GiveItems(session.Player1, session.Player2Items)
	local given2 = GiveItems(session.Player2, session.Player1Items)
	
	if not given1 or not given2 then
		error("Failed to give items")
	end
	
	return true
end

return TradeValidator
