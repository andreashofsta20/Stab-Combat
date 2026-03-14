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
    self.Timeout = 120 
    
    -- Items being traded
    self.Player1Items = {}
    self.Player2Items = {}
    
    -- Lock status
    self.Player1Locked = false
    self.Player2Locked = false
    self.Player1Accepted = false
    self.Player2Accepted = false
    self.AcceptReadyAt = 0
    
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

function TradeSession:IsPlayerLocked(player: Player)
    if player == self.Player1 then
        return self.Player1Locked == true
    elseif player == self.Player2 then
        return self.Player2Locked == true
    end
    return false
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

local VALID_TRADE_ITEM_TYPES = { Inventory = true, Emotes = true }

function TradeSession:AddItem(player: Player, itemType: string, itemName: string, quantity: number)
    self:UpdateActivity()

    if not VALID_TRADE_ITEM_TYPES[itemType] then
        return false, "Invalid item type"
    end

    if self:IsPlayerLocked(player) then
        return false, "Unconfirm before editing items"
    end
    
    local userId = player.UserId
    
    local items

    if player == self.Player1 then
        items = self.Player1Items
    elseif player == self.Player2 then
        items = self.Player2Items
    else
        return false, "Invalid player"
    end
    
    -- Check if item exists and player owns it
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return false, "No leaderstats" end
    
    local inventory = leaderstats:FindFirstChild(itemType)
    if not inventory then return false, "Invalid item type" end
    
    local item = inventory:FindFirstChild(itemName)
    if not item then return false, "Item not found" end

    local tradeableValue = item:FindFirstChild("Tradeable")
    if tradeableValue and tradeableValue:IsA("BoolValue") and tradeableValue.Value == false then
        return false, "Item is not tradeable"
    end
    
    local quantityValue = item:FindFirstChild("Quantity")
    local ownedQuantity = quantityValue and quantityValue.Value or 1

    if typeof(quantity) ~= "number" or quantity <= 0 or quantity % 1 ~= 0 then
        return false, "Invalid quantity"
    end

    local existingTradeItem = nil
    for _, offeredItem in ipairs(items) do
        if offeredItem.Name == itemName and offeredItem.Type == itemType then
            existingTradeItem = offeredItem
            break
        end
    end

    if itemType == "Inventory" and not existingTradeItem then
        local knifeSlots = 0
        for _, offeredItem in ipairs(items) do
            if offeredItem.Type == "Inventory" then
                knifeSlots += 1
            end
        end
        if knifeSlots >= 4 then
            return false, "You can only offer 4 knives"
        end
    end

    local alreadyOffered = existingTradeItem and existingTradeItem.Quantity or 0
    local newTotal = alreadyOffered + quantity
    if newTotal > ownedQuantity then
        return false, "Not enough quantity"
    end

    if existingTradeItem then
        existingTradeItem.Quantity = newTotal
    else
        if self:IsItemLocked(userId, itemName) then
            return false, "Item already in trade"
        end

        table.insert(items, {
            Type = itemType,
            Name = itemName,
            Quantity = quantity,
            Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
            Image = item:FindFirstChild("Image") and item.Image.Value or "",
            Tradeable = tradeableValue and tradeableValue.Value or true
        })

        self:LockItem(userId, itemName)
    end

    self.Player1Locked = false
    self.Player2Locked = false
    self.Player1Accepted = false
    self.Player2Accepted = false
    self.AcceptReadyAt = 0
    self.State = TradeState.ACTIVE
    return true
end

function TradeSession:RemoveItem(player: Player, itemName: string, quantity: number?)
    self:UpdateActivity()

    if self:IsPlayerLocked(player) then
        return false, "Unconfirm before editing items"
    end

    local removeQuantity = quantity or math.huge
    if removeQuantity ~= math.huge then
        if typeof(removeQuantity) ~= "number" or removeQuantity <= 0 or removeQuantity % 1 ~= 0 then
            return false, "Invalid quantity"
        end
    end
    

    local items

    if player == self.Player1 then
        items = self.Player1Items
    elseif player == self.Player2 then
        items = self.Player2Items
    else
     return false, "Invalid player"
    end
    
    for i, item in ipairs(items) do
        if item.Name == itemName then
            if removeQuantity >= item.Quantity then
                table.remove(items, i)
                self:UnlockItem(player.UserId, itemName)
            else
                item.Quantity -= removeQuantity
            end
            self.Player1Locked = false
            self.Player2Locked = false
            self.Player1Accepted = false
            self.Player2Accepted = false
            self.AcceptReadyAt = 0
            self.State = TradeState.ACTIVE
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

    self.Player1Accepted = false
    self.Player2Accepted = false
    
    -- If both locked, transition to LOCKED state
    if self.Player1Locked and self.Player2Locked then
        -- SWAPPED os.time() for os.clock()
        self.AcceptReadyAt = os.clock() + 5
        self.State = TradeState.LOCKED
    else
        self.AcceptReadyAt = 0
        self.State = TradeState.ACTIVE
    end
end

function TradeSession:BothPlayersLocked()
    return self.Player1Locked and self.Player2Locked
end

function TradeSession:SetAccepted(player: Player, accepted: boolean)
    self:UpdateActivity()

    if not self:BothPlayersLocked() then
        return false, "Both players must confirm first"
    end

    -- SWAPPED os.time() for os.clock()
    if accepted == true and os.clock() < self.AcceptReadyAt then
        return false, "Please wait before accepting"
    end

    if player == self.Player1 then
        self.Player1Accepted = accepted
    elseif player == self.Player2 then
        self.Player2Accepted = accepted
    else
        return false, "Invalid player"
    end

    return true
end

function TradeSession:BothPlayersAccepted()
    return self.Player1Accepted and self.Player2Accepted
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
            Locked = self.Player1Locked,
            Accepted = self.Player1Accepted
        },
        Player2 = {
            UserId = self.Player2.UserId,
            Name = self.Player2.Name,
            Items = self.Player2Items,
            Locked = self.Player2Locked,
            Accepted = self.Player2Accepted
        },
        State = self.State,
        AcceptReadyAt = self.AcceptReadyAt
    }
end

return TradeSession