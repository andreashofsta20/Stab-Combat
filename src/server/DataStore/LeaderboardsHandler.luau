local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local LeaderboardsRemotesFolder = RemotesFolder:WaitForChild("Leaderboards")
local RequestLeaderboardsRemote = LeaderboardsRemotesFolder:WaitForChild("RequestLeaderboards")

local Leaderboards = {}

local CalculateLevelModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))

local LevelsStore = DataStoreService:GetOrderedDataStore("Leaderboard_Levels_v3_TESTING1")
local KillsStore = DataStoreService:GetOrderedDataStore("Leaderboard_Kills_TESTING1")
local GoldStore = DataStoreService:GetOrderedDataStore("Leaderboard_Gold_TESTING1")

local NAME_CACHE = {}
local LAST_UPDATE = {}
local UPDATE_COOLDOWN_SECONDS = 60
local DEFAULT_TOP_COUNT = 50

local function getPlayerName(userId: number)
	local cached = NAME_CACHE[userId]
	if cached then
		return cached
	end

	local success, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if success and name then
		NAME_CACHE[userId] = name
		return name
	end

	return "Unknown"
end

local function updateOrderedStores(player: Player, force: boolean?)
	local userId = player.UserId
	local now = os.clock()
	if not force and LAST_UPDATE[userId] and (now - LAST_UPDATE[userId]) < UPDATE_COOLDOWN_SECONDS then
		return
	end
	LAST_UPDATE[userId] = now

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local killsValue = leaderstats:FindFirstChild("Kills")
	local cashValue = leaderstats:FindFirstChild("Cash")
	local xpValue = leaderstats:FindFirstChild("XP")

	local level = 0
	if xpValue then
		level = CalculateLevelModule.GetLevel(xpValue.Value)
	end

	pcall(function()
		KillsStore:SetAsync(userId, killsValue and killsValue.Value or 0)
	end)

	pcall(function()
		GoldStore:SetAsync(userId, cashValue and cashValue.Value or 0)
	end)

	pcall(function()
		LevelsStore:SetAsync(userId, level)
	end)
end

local function getLeaderboardData(orderedStore: OrderedDataStore, count: number)
	local success, pages = pcall(function()
		return orderedStore:GetSortedAsync(false, count)
	end)
	if not success or not pages then
		return {}
	end

	local currentPage = pages:GetCurrentPage()
	local results = {}
	for rank, entry in ipairs(currentPage) do
		table.insert(results, {
			Rank = rank,
			UserId = entry.key,
			Name = getPlayerName(entry.key),
			Value = entry.value,
		})
	end

	return results
end

function Leaderboards.Broadcast(count: number?)
	local topCount = count or DEFAULT_TOP_COUNT
	local payload = {
		Levels = getLeaderboardData(LevelsStore, topCount),
		Kills = getLeaderboardData(KillsStore, topCount),
		Gold = getLeaderboardData(GoldStore, topCount),
	}

	RequestLeaderboardsRemote:FireAllClients(payload)
end

local function bindLeaderstats(player: Player)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		return
	end

	local killsValue = leaderstats:WaitForChild("Kills", 10)
	local cashValue = leaderstats:WaitForChild("Cash", 10)
	local xpValue = leaderstats:WaitForChild("XP", 10)

	local function onStatChanged()
		updateOrderedStores(player)
	end

	if killsValue then
		killsValue.Changed:Connect(onStatChanged)
	end
	if cashValue then
		cashValue.Changed:Connect(onStatChanged)
	end
	if xpValue then
		xpValue.Changed:Connect(onStatChanged)
	end

	updateOrderedStores(player, true)
end

Players.PlayerAdded:Connect(function(player)
	bindLeaderstats(player)
end)

local lastLeaderboardRequestAt: {[number]: number} = {}
local LEADERBOARD_REQUEST_COOLDOWN = 30

Players.PlayerRemoving:Connect(function(player)
	updateOrderedStores(player, true)
	LAST_UPDATE[player.UserId] = nil
	lastLeaderboardRequestAt[player.UserId] = nil
end)

RequestLeaderboardsRemote.OnServerEvent:Connect(function(player)
   local now = os.clock()
   if lastLeaderboardRequestAt[player.UserId] and (now - lastLeaderboardRequestAt[player.UserId]) < LEADERBOARD_REQUEST_COOLDOWN then
       return
   end
   lastLeaderboardRequestAt[player.UserId] = now

   -- Update player's stats in DataStore before sending leaderboard
   updateOrderedStores(player)
   local topCount = DEFAULT_TOP_COUNT
   local payload = {
	   Levels = getLeaderboardData(LevelsStore, topCount),
	   Kills = getLeaderboardData(KillsStore, topCount),
	   Gold = getLeaderboardData(GoldStore, topCount),
   }
   RequestLeaderboardsRemote:FireClient(player, payload)
end)


task.spawn(function()
	while true do
		task.wait(UPDATE_COOLDOWN_SECONDS)
		Leaderboards.Broadcast()
	end
end)

return Leaderboards


