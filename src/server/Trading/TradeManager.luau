local TradeManager = {}

local Players = game:GetService("Players")
local TradeSession = require(script.Parent.TradeSession)
local TradeValidator = require(script.Parent.TradeValidator)

-- Active trades
local ActiveTrades = {} -- [player.UserId] = TradeSession
local PendingRequests = {} -- [targetUserId] = {sender = Player, timestamp = number}

-- Rate limiting
local RequestCooldowns = {} -- [userId] = lastRequestTime
local REQUEST_COOLDOWN = 5 -- seconds

function TradeManager.Init()
	-- Handle player leaving mid-trade
	Players.PlayerRemoving:Connect(function(player)
		TradeManager.CancelTradeForPlayer(player)
	end)
	
	-- Timeout checker
	task.spawn(function()
		while true do
			task.wait(5)
			TradeManager.CheckTimeouts()
		end
	end)
end

function TradeManager.CheckTimeouts()
	for userId, session in pairs(ActiveTrades) do
		if session:IsTimedOut() then
			warn("Trade timed out:", session.TradeId)
			TradeManager.CancelTrade(session)
		end
	end
end

function TradeManager.CanSendRequest(player: Player)
	local lastRequest = RequestCooldowns[player.UserId]
	if lastRequest and (os.clock() - lastRequest) < REQUEST_COOLDOWN then
		return false, "Please wait before sending another request"
	end
	return true
end

function TradeManager.SendRequest(sender: Player, target: Player)
	-- Validate
	if sender == target then
		return false, "Cannot trade with yourself"
	end
	
	local canSend, err = TradeManager.CanSendRequest(sender)
	if not canSend then
		return false, err
	end
	
	if ActiveTrades[sender.UserId] then
		return false, "You're already in a trade"
	end
	
	if ActiveTrades[target.UserId] then
		return false, target.Name .. " is already in a trade"
	end
	
	if PendingRequests[target.UserId] then
		return false, target.Name .. " already has a pending request"
	end
	
	-- Set cooldown
	RequestCooldowns[sender.UserId] = os.clock()
	
	-- Store request
	PendingRequests[target.UserId] = {
		sender = sender,
		timestamp = os.clock()
	}
	
	-- Auto-expire after 30 seconds
	task.delay(30, function()
		if PendingRequests[target.UserId] and PendingRequests[target.UserId].sender == sender then
			PendingRequests[target.UserId] = nil
		end
	end)
	
	return true
end

function TradeManager.AcceptRequest(target: Player)
	local request = PendingRequests[target.UserId]
	if not request then
		return false, "No pending request"
	end
	
	local sender = request.sender
	
	-- Check sender still in game
	if not sender or not sender.Parent then
		PendingRequests[target.UserId] = nil
		return false, "Request expired"
	end
	
	-- Check neither is in a trade
	if ActiveTrades[sender.UserId] or ActiveTrades[target.UserId] then
		PendingRequests[target.UserId] = nil
		return false, "One of you is already in a trade"
	end
	
	-- Create trade session
	local session = TradeSession.new(sender, target)
	session.State = "ACTIVE"
	
	ActiveTrades[sender.UserId] = session
	ActiveTrades[target.UserId] = session
	
	PendingRequests[target.UserId] = nil
	
	return true, session
end

function TradeManager.DeclineRequest(target: Player)
	if PendingRequests[target.UserId] then
		PendingRequests[target.UserId] = nil
		return true
	end
	return false, "No pending request"
end

function TradeManager.GetTradeSession(player: Player)
	return ActiveTrades[player.UserId]
end

function TradeManager.AddItemToTrade(player: Player, itemType: string, itemName: string, quantity: number)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end
	
	if not session:IsActive() then
		return false, "Trade not active"
	end
	
	return session:AddItem(player, itemType, itemName, quantity)
end

function TradeManager.RemoveItemFromTrade(player: Player, itemName: string)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end
	
	if not session:IsActive() then
		return false, "Trade not active"
	end
	
	return session:RemoveItem(player, itemName)
end

function TradeManager.SetLockStatus(player: Player, locked: boolean)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end
	
	session:SetLock(player, locked)
	
	-- If both locked, execute trade
	if session:BothPlayersLocked() then
		return TradeManager.ExecuteTrade(session)
	end
	
	return true
end

function TradeManager.ExecuteTrade(session: any)
	-- Final validation
	local valid, err = TradeValidator.ValidateTrade(session)
	if not valid then
		TradeManager.CancelTrade(session)
		return false, "Trade validation failed: " .. err
	end
	
	-- Execute atomically
	local success, executeErr = pcall(function()
		TradeValidator.ExecuteTrade(session)
	end)
	
	if not success then
		warn("Trade execution failed:", executeErr)
		TradeManager.CancelTrade(session)
		return false, "Trade failed to execute"
	end
	
	session:Complete()
	
	-- Clean up
	ActiveTrades[session.Player1.UserId] = nil
	ActiveTrades[session.Player2.UserId] = nil
	
	return true
end

function TradeManager.CancelTrade(session: any)
	if not session then return end
	
	session:Cancel()
	
	ActiveTrades[session.Player1.UserId] = nil
	ActiveTrades[session.Player2.UserId] = nil
end

function TradeManager.CancelTradeForPlayer(player: Player)
	local session = TradeManager.GetTradeSession(player)
	if session then
		TradeManager.CancelTrade(session)
	end
	
	-- Clear pending requests
	if PendingRequests[player.UserId] then
		PendingRequests[player.UserId] = nil
	end
end

return TradeManager
