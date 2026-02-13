local TradeSession = {}
TradeSession.__index = TradeSession

local Players = game:GetService("Players")

-- Trade session states
local TradeState = {
	PENDING = "PENDING",
	ACTIVE = "ACTIVE",
	LOCKED = "LOCKED",
	COMPLETED = "COMPLETED",
	CANCELLED = "CANCELLED"
}

function TradeSession.new(player1: Player, player2: Player)
	local self = setmetatable({}, TradeSession)
	
	self.TradeId = game:GetService("HttpService"):GenerateGUID(false)
	self.Player1 = player1
	self.Player2 = player2
	self.State = TradeState.PENDING
	self.CreatedAt = os.clock()
	self.LastActivity = os.clock()
	self.Timeout = 120 -- 2 minutes
	
	-- Items being traded
	self.Player1Items = {}
	self.Player2Items = {}
	
	-- Lock status
	self.Player1Locked = false
	self.Player2Locked = false
	
	-- Inventory locks (prevent adding same item twice)
	self.LockedInventory = {
		[player1.UserId] = {},
		[player2.UserId] = {}
	}
	
	return self
end

function TradeSession:GetOtherPlayer(player: Player)
	if player == self.Player1 then
		return self.Player2
	elseif player == self.Player2 then
		return self.Player1
	end
	return nil
end

function TradeSession:UpdateActivity()
	self.LastActivity = os.clock()
end

function TradeSession:IsTimedOut()
	return (os.clock() - self.LastActivity) > self.Timeout
end

function TradeSession:IsItemLocked(userId: number, itemName: string)
	return self.LockedInventory[userId] and self.LockedInventory[userId][itemName] == true
end

function TradeSession:LockItem(userId: number, itemName: string)
	if not self.LockedInventory[userId] then
		self.LockedInventory[userId] = {}
	end
	self.LockedInventory[userId][itemName] = true
end

function TradeSession:UnlockItem(userId: number, itemName: string)
	if self.LockedInventory[userId] then
		self.LockedInventory[userId][itemName] = nil
	end
end

function TradeSession:AddItem(player: Player, itemType: string, itemName: string, quantity: number)
	self:UpdateActivity()
	
	local userId = player.UserId
	if self:IsItemLocked(userId, itemName) then
		return false, "Item already in trade"
	end
	
	local items = player == self.Player1 and self.Player1Items or self.Player2Items
	
	-- Check if item exists and player owns it
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return false, "No leaderstats" end
	
	local inventory = leaderstats:FindFirstChild(itemType)
	if not inventory then return false, "Invalid item type" end
	
	local item = inventory:FindFirstChild(itemName)
	if not item then return false, "Item not found" end
	
	local quantityValue = item:FindFirstChild("Quantity")
	local ownedQuantity = quantityValue and quantityValue.Value or 1
	
	if quantity > ownedQuantity then
		return false, "Not enough quantity"
	end
	
	table.insert(items, {
		Type = itemType,
		Name = itemName,
		Quantity = quantity,
		Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common"
	})
	
	self:LockItem(userId, itemName)
	return true
end

function TradeSession:RemoveItem(player: Player, itemName: string)
	self:UpdateActivity()
	
	local items = player == self.Player1 and self.Player1Items or self.Player2Items
	
	for i, item in ipairs(items) do
		if item.Name == itemName then
			table.remove(items, i)
			self:UnlockItem(player.UserId, itemName)
			return true
		end
	end
	
	return false
end

function TradeSession:SetLock(player: Player, locked: boolean)
	self:UpdateActivity()
	
	if player == self.Player1 then
		self.Player1Locked = locked
	elseif player == self.Player2 then
		self.Player2Locked = locked
	end
	
	-- If both locked, transition to LOCKED state
	if self.Player1Locked and self.Player2Locked then
		self.State = TradeState.LOCKED
	else
		self.State = TradeState.ACTIVE
	end
end

function TradeSession:BothPlayersLocked()
	return self.Player1Locked and self.Player2Locked
end

function TradeSession:Cancel()
	self.State = TradeState.CANCELLED
	
	-- Clear all locks
	for userId, locks in pairs(self.LockedInventory) do
		table.clear(locks)
	end
end

function TradeSession:Complete()
	self.State = TradeState.COMPLETED
end

function TradeSession:IsActive()
	return self.State == TradeState.ACTIVE or self.State == TradeState.LOCKED
end

function TradeSession:GetTradeData()
	return {
		TradeId = self.TradeId,
		Player1 = {
			UserId = self.Player1.UserId,
			Name = self.Player1.Name,
			Items = self.Player1Items,
			Locked = self.Player1Locked
		},
		Player2 = {
			UserId = self.Player2.UserId,
			Name = self.Player2.Name,
			Items = self.Player2Items,
			Locked = self.Player2Locked
		},
		State = self.State
	}
end

return TradeSession
