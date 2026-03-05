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
local CancelCallbacks = {}

function TradeManager.RegisterCancelCallback(callback: (any, string?) -> ())
	table.insert(CancelCallbacks, callback)
end

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
			TradeManager.CancelTrade(session, "TIMEOUT")
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
	
	-- Auto-clear stale trades (other player left, or session extremely old)
	local staleSender = ActiveTrades[sender.UserId]
	if staleSender then
		local otherPlayer = staleSender:GetOtherPlayer(sender)
		if not otherPlayer or not otherPlayer.Parent or (os.clock() - staleSender.LastActivity) > staleSender.Timeout then
			TradeManager.CancelTrade(staleSender, "STALE")
		else
			return false, "You're already in a trade"
		end
	end
	
	local staleTarget = ActiveTrades[target.UserId]
	if staleTarget then
		local otherPlayer = staleTarget:GetOtherPlayer(target)
		if not otherPlayer or not otherPlayer.Parent or (os.clock() - staleTarget.LastActivity) > staleTarget.Timeout then
			TradeManager.CancelTrade(staleTarget, "STALE")
		else
			return false, target.Name .. " is already in a trade"
		end
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
	print("Trade session created between", sender.Name, "and", target.Name)
	
	ActiveTrades[sender.UserId] = session
	ActiveTrades[target.UserId] = session
	
	PendingRequests[target.UserId] = nil
	
	return true, session
end

function TradeManager.DeclineRequest(target: Player)
	if PendingRequests[target.UserId] then
		print(target.Name, "declined trade request from", PendingRequests[target.UserId].sender.Name)
		PendingRequests[target.UserId] = nil
		return true
	end

	print("No pending request to decline for", target.Name)
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

function TradeManager.RemoveItemFromTrade(player: Player, itemName: string, quantity: number?)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end
	
	if not session:IsActive() then
		return false, "Trade not active"
	end
	
	return session:RemoveItem(player, itemName, quantity)
end

function TradeManager.SetLockStatus(player: Player, locked: boolean)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end
	
	session:SetLock(player, locked)
	
	return true
end

function TradeManager.SetAcceptStatus(player: Player, accepted: boolean)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return false, "Not in a trade"
	end

	if session.State ~= "LOCKED" and accepted == true then
		return false, "Trade is not ready for accept"
	end

	local success, err = session:SetAccepted(player, accepted)
	if not success then
		return false, err
	end

	if session:BothPlayersAccepted() then
		return TradeManager.ExecuteTrade(session)
	end

	return true
end

function TradeManager.ExecuteTrade(session: any)
	-- Final validation
	local valid, err = TradeValidator.ValidateTrade(session)
	if not valid then
		TradeManager.CancelTrade(session, "VALIDATION_FAILED")
		return false, "Trade validation failed: " .. err
	end
	
	-- Execute atomically
	local ok, executeResult = pcall(function()
		return TradeValidator.ExecuteTrade(session)
	end)
	
	if not ok then
		warn("Trade execution error:", executeResult)
		TradeManager.CancelTrade(session, "EXECUTION_FAILED")
		return false, "Trade failed to execute"
	end
	
	if not executeResult then
		warn("Trade execution returned false")
		TradeManager.CancelTrade(session, "EXECUTION_FAILED")
		return false, "Trade failed to execute"
	end
	
	session:Complete()
	
	-- Clean up
	ActiveTrades[session.Player1.UserId] = nil
	ActiveTrades[session.Player2.UserId] = nil
	
	return true
end

function TradeManager.CancelTrade(session: any, reason: string?)
	if not session then return end

	for _, callback in ipairs(CancelCallbacks) do
		task.spawn(callback, session, reason)
	end
	
	session:Cancel()
	
	ActiveTrades[session.Player1.UserId] = nil
	ActiveTrades[session.Player2.UserId] = nil
end

function TradeManager.CancelTradeForPlayer(player: Player)
	local session = TradeManager.GetTradeSession(player)
	if session then
		TradeManager.CancelTrade(session, "PLAYER_LEFT")
	end
	
	-- Clear pending requests
	if PendingRequests[player.UserId] then
		PendingRequests[player.UserId] = nil
	end
end

return TradeManager
