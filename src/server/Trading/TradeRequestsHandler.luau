local TradeRequestsHandler = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeManager = require(script.Parent.TradeManager)
local CalculateLevel = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))

-- Remotes (will be created in init.server.lua)
local RemotesFolder
local SendRequestRemote
local AcceptRequestRemote
local DeclineRequestRemote
local AddItemRemote
local RemoveItemRemote
local LockTradeRemote
local CancelTradeRemote
local TradeUpdateRemote

function TradeRequestsHandler.Init()
	RemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
	SendRequestRemote = RemotesFolder:WaitForChild("SendRequest")
	AcceptRequestRemote = RemotesFolder:WaitForChild("AcceptRequest")
	DeclineRequestRemote = RemotesFolder:WaitForChild("DeclineRequest")
	AddItemRemote = RemotesFolder:WaitForChild("AddItem")
	RemoveItemRemote = RemotesFolder:WaitForChild("RemoveItem")
	LockTradeRemote = RemotesFolder:WaitForChild("LockTrade")
	CancelTradeRemote = RemotesFolder:WaitForChild("CancelTrade")
	TradeUpdateRemote = RemotesFolder:WaitForChild("TradeUpdate")
	
	-- Connect handlers
	SendRequestRemote.OnServerEvent:Connect(TradeRequestsHandler.OnSendRequest)
	AcceptRequestRemote.OnServerEvent:Connect(TradeRequestsHandler.OnAcceptRequest)
	DeclineRequestRemote.OnServerEvent:Connect(TradeRequestsHandler.OnDeclineRequest)
	AddItemRemote.OnServerEvent:Connect(TradeRequestsHandler.OnAddItem)
	RemoveItemRemote.OnServerEvent:Connect(TradeRequestsHandler.OnRemoveItem)
	LockTradeRemote.OnServerEvent:Connect(TradeRequestsHandler.OnLockTrade)
	CancelTradeRemote.OnServerEvent:Connect(TradeRequestsHandler.OnCancelTrade)
end

-- Notify players about trade updates
function TradeRequestsHandler.NotifyTrade(session: any, updateType: string, data: any?)
	local tradeData = session:GetTradeData()
	tradeData.UpdateType = updateType
	tradeData.ExtraData = data
	
	TradeUpdateRemote:FireClient(session.Player1, tradeData)
	TradeUpdateRemote:FireClient(session.Player2, tradeData)
end

function TradeRequestsHandler.OnSendRequest(sender: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return SendRequestRemote:FireClient(sender, {success = false, error = "Player not found"})
	end

	local senderStats = sender:FindFirstChild("leaderstats")
	local targetStats = target:FindFirstChild("leaderstats")
	local senderXp = senderStats and senderStats:FindFirstChild("XP")
	local targetXp = targetStats and targetStats:FindFirstChild("XP")
	if not senderXp or not targetXp then
		return SendRequestRemote:FireClient(sender, {success = false, error = "Missing XP data"})
	end

	local senderLevel = CalculateLevel.GetLevel(senderXp.Value)
	local targetLevel = CalculateLevel.GetLevel(targetXp.Value)
	if senderLevel < 20 or targetLevel < 20 then
		return SendRequestRemote:FireClient(sender, {success = false, error = "Both players must be level 20+"})
	end
	
	local success, sessionOrErr = TradeManager.SendRequest(sender, target)
	
	if success then
		-- Notify target player
		TradeUpdateRemote:FireClient(target, {
			UpdateType = "REQUEST_RECEIVED",
			Sender = {UserId = sender.UserId, Name = sender.Name}
		})
	end
	
	SendRequestRemote:FireClient(sender, {success = success, error = sessionOrErr})
end

function TradeRequestsHandler.OnAcceptRequest(target: Player)
	local success, sessionOrErr = TradeManager.AcceptRequest(target)
	
	if success then
		local session = sessionOrErr
		TradeRequestsHandler.NotifyTrade(session, "TRADE_STARTED")
	end
	
	AcceptRequestRemote:FireClient(target, {success = success, error = not success and sessionOrErr or nil})
end

function TradeRequestsHandler.OnDeclineRequest(target: Player)
	local success, err = TradeManager.DeclineRequest(target)
	DeclineRequestRemote:FireClient(target, {success = success, error = err})
end

function TradeRequestsHandler.OnAddItem(player: Player, itemType: string, itemName: string, quantity: number)
	local success, err = TradeManager.AddItemToTrade(player, itemType, itemName, quantity)
	
	if success then
		local session = TradeManager.GetTradeSession(player)
		if session then
			TradeRequestsHandler.NotifyTrade(session, "ITEM_ADDED", {player = player.UserId, item = itemName})
		end
	end
	
	AddItemRemote:FireClient(player, {success = success, error = err})
end

function TradeRequestsHandler.OnRemoveItem(player: Player, itemName: string)
	local success, err = TradeManager.RemoveItemFromTrade(player, itemName)
	
	if success then
		local session = TradeManager.GetTradeSession(player)
		if session then
			TradeRequestsHandler.NotifyTrade(session, "ITEM_REMOVED", {player = player.UserId, item = itemName})
		end
	end
	
	RemoveItemRemote:FireClient(player, {success = success, error = err})
end

function TradeRequestsHandler.OnLockTrade(player: Player, locked: boolean)
	local session = TradeManager.GetTradeSession(player)
	if not session then
		return LockTradeRemote:FireClient(player, {success = false, error = "Not in trade"})
	end
	
	local success, err = TradeManager.SetLockStatus(player, locked)
	
	if success then
		TradeRequestsHandler.NotifyTrade(session, "LOCK_STATUS", {player = player.UserId, locked = locked})
		
		-- Check if trade completed
		if session.State == "COMPLETED" then
			TradeRequestsHandler.NotifyTrade(session, "TRADE_COMPLETED")
		end
	else
		-- Trade failed
		TradeRequestsHandler.NotifyTrade(session, "TRADE_FAILED", {error = err})
	end
	
	LockTradeRemote:FireClient(player, {success = success, error = err})
end

function TradeRequestsHandler.OnCancelTrade(player: Player)
	local session = TradeManager.GetTradeSession(player)
	if session then
		TradeRequestsHandler.NotifyTrade(session, "TRADE_CANCELLED", {player = player.UserId})
		TradeManager.CancelTrade(session)
	end
	
	CancelTradeRemote:FireClient(player, {success = true})
end

return TradeRequestsHandler
