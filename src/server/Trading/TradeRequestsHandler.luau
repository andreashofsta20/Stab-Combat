local TradeRequestsHandler = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeManager = require(script.Parent.TradeManager)
local CalculateLevel = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))
local ACTION_COOLDOWNS = {
    SEND_REQUEST = 0.6,
    ACCEPT_REQUEST = 0.4,
    DECLINE_REQUEST = 0.4,
    ADD_ITEM = 0.15,
    REMOVE_ITEM = 0.15,
    LOCK_TRADE = 0.1,
    ACCEPT_TRADE = 0.1,
    CANCEL_TRADE = 0.25,
}
local lastActionAt: {[number]: {[string]: number}} = {}

-- Remotes
local RemotesFolder
local TradeUpdateRemote

function TradeRequestsHandler.Init()
    RemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
    TradeUpdateRemote = RemotesFolder:WaitForChild("TradeUpdate")
    
    TradeManager.RegisterCancelCallback(function(session, reason)
        TradeRequestsHandler.NotifyTrade(session, "TRADE_CANCELLED", {reason = reason})
    end)

    -- Connect single remote handler
    TradeUpdateRemote.OnServerEvent:Connect(TradeRequestsHandler.OnTradeAction)
end

-- Notify players about trade updates
function TradeRequestsHandler.NotifyTrade(session: any, updateType: string, data: any?)
    local tradeData = session:GetTradeData()
    tradeData.UpdateType = updateType
    tradeData.ExtraData = data
    
    TradeUpdateRemote:FireClient(session.Player1, "TRADE_EVENT", tradeData)
    TradeUpdateRemote:FireClient(session.Player2, "TRADE_EVENT", tradeData)
end

function TradeRequestsHandler.FireResult(player: Player, action: string, success: boolean, err: string?, extra: any?)
    TradeUpdateRemote:FireClient(player, "ACTION_RESULT", {
        action = action,
        success = success,
        error = err,
        extra = extra
    })
end

function TradeRequestsHandler.OnTradeAction(player: Player, action: string, ...)
    if type(action) ~= "string" then
        return
    end

    local now = os.clock()
    local userMap = lastActionAt[player.UserId]
    if not userMap then
        userMap = {}
        lastActionAt[player.UserId] = userMap
    end
    local minGap = ACTION_COOLDOWNS[action]
    if minGap then
        local lastAt = userMap[action]
        if lastAt and (now - lastAt) < minGap then
            return
        end
        userMap[action] = now
    end

    if action == "SEND_REQUEST" then
        TradeRequestsHandler.OnSendRequest(player, ...)
        return
    end

    if action == "ACCEPT_REQUEST" then
        TradeRequestsHandler.OnAcceptRequest(player)
        return
    end

    if action == "DECLINE_REQUEST" then
        TradeRequestsHandler.OnDeclineRequest(player)
        return
    end

    if action == "ADD_ITEM" then
        TradeRequestsHandler.OnAddItem(player, ...)
        return
    end

    if action == "REMOVE_ITEM" then
        TradeRequestsHandler.OnRemoveItem(player, ...)
        return
    end

    if action == "LOCK_TRADE" then
        TradeRequestsHandler.OnLockTrade(player, ...)
        return
    end

    if action == "ACCEPT_TRADE" then
        TradeRequestsHandler.OnAcceptTrade(player, ...)
        return
    end

    if action == "CANCEL_TRADE" then
        TradeRequestsHandler.OnCancelTrade(player)
        return
    end

    TradeRequestsHandler.FireResult(player, action, false, "Unknown trade action")
end

function TradeRequestsHandler.OnSendRequest(sender: Player, targetUserId: number)
    if typeof(targetUserId) ~= "number" then
        return TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", false, "Invalid target")
    end
    targetUserId = math.floor(targetUserId)
    if targetUserId <= 0 or targetUserId == sender.UserId then
        return TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", false, "Invalid target")
    end

    local target = Players:GetPlayerByUserId(targetUserId)
    if not target then
        return TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", false, "Player not found")
    end

    -- AUTO-ACCEPT: If target already requested sender, match intent!
    local pendingForSender = TradeManager.GetPendingRequest(sender.UserId)
    if pendingForSender and pendingForSender.sender == target then
        return TradeRequestsHandler.OnAcceptRequest(sender)
    end

    local senderStats = sender:FindFirstChild("leaderstats")
    local targetStats = target:FindFirstChild("leaderstats")
    local senderXp = senderStats and senderStats:FindFirstChild("XP")
    local targetXp = targetStats and targetStats:FindFirstChild("XP")
    if not senderXp or not targetXp then
        return TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", false, "Missing XP data")
    end

    local senderLevel = CalculateLevel.GetLevel(senderXp.Value)
    local targetLevel = CalculateLevel.GetLevel(targetXp.Value)
    if senderLevel < 10 or targetLevel < 10 then
        return TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", false, "Both players must be level 10+")
    end
    
    local success, sessionOrErr = TradeManager.SendRequest(sender, target)
    
    if success then
        -- Notify target player
        TradeUpdateRemote:FireClient(target, "TRADE_EVENT", {
            UpdateType = "REQUEST_RECEIVED",
            Sender = {UserId = sender.UserId, Name = sender.Name}
        })

        -- 15 Second Expiry check
        task.delay(15, function()
            local pending = TradeManager.GetPendingRequest(target.UserId)
            if pending and pending.sender == sender then
                TradeManager.ClearPendingRequest(target.UserId)
                TradeUpdateRemote:FireClient(target, "TRADE_EVENT", {
                    UpdateType = "REQUEST_EXPIRED",
                    Sender = {UserId = sender.UserId, Name = sender.Name}
                })
            end
        end)
    end
    
    TradeRequestsHandler.FireResult(sender, "SEND_REQUEST", success, not success and sessionOrErr or nil, { targetUserId = targetUserId })
end

function TradeRequestsHandler.OnAcceptRequest(target: Player)
    local success, sessionOrErr = TradeManager.AcceptRequest(target)
    
    if success then
        local session = sessionOrErr
        TradeRequestsHandler.NotifyTrade(session, "TRADE_STARTED")
    end
    
    TradeRequestsHandler.FireResult(target, "ACCEPT_REQUEST", success, not success and sessionOrErr or nil)
end

function TradeRequestsHandler.OnDeclineRequest(target: Player)
    local success, err = TradeManager.DeclineRequest(target)
    TradeRequestsHandler.FireResult(target, "DECLINE_REQUEST", success, err)
end

function TradeRequestsHandler.OnAddItem(player: Player, itemType: string, itemName: string, quantity: number)
    if type(itemType) ~= "string" or type(itemName) ~= "string" or typeof(quantity) ~= "number" then
        return TradeRequestsHandler.FireResult(player, "ADD_ITEM", false, "Invalid item payload")
    end
    quantity = math.floor(quantity)
    if quantity <= 0 then
        return TradeRequestsHandler.FireResult(player, "ADD_ITEM", false, "Invalid quantity")
    end

    local success, err = TradeManager.AddItemToTrade(player, itemType, itemName, quantity)
    
    if success then
        local session = TradeManager.GetTradeSession(player)
        if session then
            TradeRequestsHandler.NotifyTrade(session, "ITEM_ADDED", {player = player.UserId, item = itemName})
        end
    end
    
    TradeRequestsHandler.FireResult(player, "ADD_ITEM", success, err)
end

function TradeRequestsHandler.OnRemoveItem(player: Player, itemName: string, quantity: number?)
    if type(itemName) ~= "string" then
        return TradeRequestsHandler.FireResult(player, "REMOVE_ITEM", false, "Invalid item")
    end
    if quantity ~= nil then
        if typeof(quantity) ~= "number" then
            return TradeRequestsHandler.FireResult(player, "REMOVE_ITEM", false, "Invalid quantity")
        end
        quantity = math.floor(quantity)
        if quantity <= 0 then
            return TradeRequestsHandler.FireResult(player, "REMOVE_ITEM", false, "Invalid quantity")
        end
    end

    local success, err = TradeManager.RemoveItemFromTrade(player, itemName, quantity)
    
    if success then
        local session = TradeManager.GetTradeSession(player)
        if session then
            TradeRequestsHandler.NotifyTrade(session, "ITEM_REMOVED", {player = player.UserId, item = itemName})
        end
    end
    
    TradeRequestsHandler.FireResult(player, "REMOVE_ITEM", success, err)
end

function TradeRequestsHandler.OnLockTrade(player: Player, locked: boolean)
    if typeof(locked) ~= "boolean" then
        return TradeRequestsHandler.FireResult(player, "LOCK_TRADE", false, "Invalid lock state")
    end

    local session = TradeManager.GetTradeSession(player)
    if not session then
        return TradeRequestsHandler.FireResult(player, "LOCK_TRADE", false, "Not in trade")
    end
    
    local success, err = TradeManager.SetLockStatus(player, locked)
    
    if success then
        TradeRequestsHandler.NotifyTrade(session, "LOCK_STATUS", {player = player.UserId, locked = locked})
    end
    
    TradeRequestsHandler.FireResult(player, "LOCK_TRADE", success, err)
end

function TradeRequestsHandler.OnAcceptTrade(player: Player, accepted: boolean)
    if accepted ~= nil and typeof(accepted) ~= "boolean" then
        return TradeRequestsHandler.FireResult(player, "ACCEPT_TRADE", false, "Invalid accept state")
    end

    local session = TradeManager.GetTradeSession(player)
    if not session then
        return TradeRequestsHandler.FireResult(player, "ACCEPT_TRADE", false, "Not in trade")
    end

    local shouldAccept = accepted == true
    local success, err = TradeManager.SetAcceptStatus(player, shouldAccept)

    if success then
        TradeRequestsHandler.NotifyTrade(session, "ACCEPT_STATUS", {player = player.UserId, accepted = shouldAccept})

        if session.State == "COMPLETED" then
            TradeRequestsHandler.NotifyTrade(session, "TRADE_COMPLETED")
        end
    else
        if session.State == "CANCELLED" then
            TradeRequestsHandler.NotifyTrade(session, "TRADE_FAILED", {error = err})
        else
            TradeRequestsHandler.FireResult(player, "ACCEPT_TRADE", false, err)
            return
        end
    end

    TradeRequestsHandler.FireResult(player, "ACCEPT_TRADE", success, err)
end

function TradeRequestsHandler.OnCancelTrade(player: Player)
    local session = TradeManager.GetTradeSession(player)
    if session then
        TradeRequestsHandler.NotifyTrade(session, "TRADE_CANCELLED", {player = player.UserId})
        TradeManager.CancelTrade(session)
    end
    
    TradeRequestsHandler.FireResult(player, "CANCEL_TRADE", true)
end

Players.PlayerRemoving:Connect(function(player)
    lastActionAt[player.UserId] = nil
end)

return TradeRequestsHandler