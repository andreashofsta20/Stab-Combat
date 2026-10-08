-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketPlaceService = game:GetService("MarketplaceService")

-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ProfileHandlerFolder = RemotesFolder:WaitForChild("ProfileHandler")
local RecieveProfileRequest = ProfileHandlerFolder:WaitForChild("RequestViewProfile")
local ViewProfileCliend = ProfileHandlerFolder:WaitForChild("ViewProfileClient")

-- // MODULES // --
local GetPlayerInfo = require(script.Parent:WaitForChild("GetPlayerInfo"))
local RoundHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHandler"))



-- // MODULES // --
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))



local profileCooldowns: {[number]: number} = {}
local PROFILE_VIEW_COOLDOWN = 1.0
local viewing = {}
local offlineCache, offlineReads = {}, {}
local cacheOrder = {}
local CACHE_LIMIT, CACHE_SECONDS = 64, 30
local activeOffline, tokens, lastRefill = 0, 4, os.clock()

RecieveProfileRequest.OnServerEvent:Connect(function(player : Player, TargetID)
	if not player or player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return end
	if typeof(TargetID) ~= "number" then return end
	if TargetID ~= TargetID or math.abs(TargetID) == math.huge or TargetID > 9007199254740991 then return end
	if TargetID % 1 ~= 0 then return end
	if TargetID <= 0 then return end
	if viewing[player] then return end -- an offline read can yield beyond the cooldown

	local now = os.clock()
	if profileCooldowns[player.UserId] and (now - profileCooldowns[player.UserId]) < PROFILE_VIEW_COOLDOWN then return end
	profileCooldowns[player.UserId] = now
	local offline = Players:GetPlayerByUserId(TargetID) == nil
	local cached = offline and offlineCache[TargetID]
	if cached and now < cached.expires then
		ViewProfileCliend:FireClient(player, cached.info, cached.inventory)
		return
	end
	if offline then
		tokens = math.min(4, tokens + math.max(0, now - lastRefill))
		lastRefill = now
		-- Random offline IDs must not turn each connected player into a backend
		-- read worker. Never queue spam or duplicate an already-running target.
		if activeOffline >= 2 or offlineReads[TargetID] or tokens < 1 then return end
		tokens -= 1; activeOffline += 1; offlineReads[TargetID] = true
	end
	
	viewing[player] = true
	local ok, info, inventory = pcall(function()
		return GetPlayerInfo.AllInfo(TargetID)
	end)
	viewing[player] = nil
	if offline then
		activeOffline -= 1; offlineReads[TargetID] = nil
		if ok and info and not info.Unavailable and not info.Loading then
			if not offlineCache[TargetID] then table.insert(cacheOrder, TargetID) end
			offlineCache[TargetID] = {info = info, inventory = inventory, expires = os.clock() + CACHE_SECONDS}
			while #cacheOrder > CACHE_LIMIT do offlineCache[table.remove(cacheOrder, 1)] = nil end
		end
	end
	if ok and player.Parent == Players then ViewProfileCliend:FireClient(player, info, inventory) end
end)

Players.PlayerRemoving:Connect(function(player)
	profileCooldowns[player.UserId] = nil
	viewing[player] = nil
end)

return {}
