local MainGame = {}
local RoundHandlerModule = require(script.Parent.RoundHandler)
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RoundResultsFolder = RemotesFolder:WaitForChild("RoundResults")
local GetRoundResultsRemote = RoundResultsFolder:WaitForChild("GetRoundResults")

local TimeToMinutesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))


-- Remotes to client

local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")
MainGame.GameActive = false
MainGame.PlayersInGame = {}
MainGame.RoundTime = 3 * 60
MainGame.CurrentMap = nil

local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")


local GameRewardModule = require(script.Parent:WaitForChild("GameReward"))
local SpawnMapModule = require(script.Parent:WaitForChild("SpawnMap"))

MainGame.TestMode = false



local Players = game:GetService("Players")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerStats_v2BETA111TEST1_")

MainGame.RoundStats = nil
-- Track elimination order for professional placement
local eliminationOrder = {}

local function CountPlayersInGame()
	local n = 0
	for _ in pairs(MainGame.PlayersInGame) do
		n += 1
	end
	return n
end

local function InitRoundStats()
	local startCount = 0
	local playersStats = {}

	for userId in pairs(MainGame.PlayersInGame) do
		startCount += 1
		playersStats[userId] = {
			kills = 0,
			placement = nil,
			rewardGold = 0,
			rewardXp = 0,
		}
	end

	MainGame.RoundStats = {
		startCount = startCount,
		players = playersStats,
	}
end

function MainGame.AddRoundKill(player: Player)
	if not player then return end
	local stats = MainGame.RoundStats
	if not stats then return end
	local data = stats.players[player.UserId]
	if not data then
		data = { kills = 0, placement = nil }
		stats.players[player.UserId] = data
	end
	data.kills += 1
end

function MainGame.RecordElimination(player: Player, remainingAfterRemoval: number?)
	if not player then return end
	local stats = MainGame.RoundStats
	if not stats then return end
	local data = stats.players[player.UserId]
	   if not data or data.placement ~= nil then return end
	   table.insert(eliminationOrder, player.UserId)
	   -- Placement will be assigned at round end
end

local RoundHistoryMax = 10

local function SaveLastRound(player: Player, opponents: number, kills: number, placement: number)
	local success, err = pcall(function()
		PlayerDataStore:UpdateAsync(player.UserId, function(oldData)
			if type(oldData) ~= "table" then
				oldData = {}
			end

			local lastRoundEntry = {
				Opponents = opponents,
				Kills = kills,
				Placement = placement,
				Timestamp = os.time(),
			}

			oldData.LastRound = lastRoundEntry
			oldData.RoundHistory = oldData.RoundHistory or {}
			table.insert(oldData.RoundHistory, 1, lastRoundEntry)
			while #oldData.RoundHistory > RoundHistoryMax do
				table.remove(oldData.RoundHistory)
			end

			return oldData
		end)
	end)

	if not success then
		warn("Failed to save LastRound data for", player.Name, err)
	end
end

local function FinalizeRoundStats()
	local stats = MainGame.RoundStats
	if not stats then return end

	-- Assign placements with strict survivor/eliminated separation and validation
	local totalPlayers = stats.startCount or 0
	local survivors = {}
	local eliminatedSet = {}
	-- Build survivors and eliminated sets
	for userId, data in pairs(stats.players) do
		eliminatedSet[userId] = false
	end
	for _, userId in ipairs(eliminationOrder) do
		eliminatedSet[userId] = true
	end
	for userId, data in pairs(stats.players) do
		if not eliminatedSet[userId] then
			table.insert(survivors, {userId = userId, kills = data.kills or 0})
		end
	end
	-- Sort survivors by kills desc, then random
	table.sort(survivors, function(a, b)
		if a.kills == b.kills then
			return math.random() < 0.5
		end
		return a.kills > b.kills
	end)
	-- Assign 1st, 2nd, ... to survivors
	local placementMap = {}
	for i, entry in ipairs(survivors) do
		local data = stats.players[entry.userId]
		data.placement = i
		placementMap[entry.userId] = i
	end
	-- Assign next placements to eliminated players in reverse elimination order
	local place = #survivors + 1
	for i = #eliminationOrder, 1, -1 do
		local userId = eliminationOrder[i]
		local data = stats.players[userId]
		if data then
			data.placement = place
			placementMap[userId] = place
			place = place + 1
		end
	end
	-- Validation: ensure all placements are unique and in range
	local seen = {}
	for userId, placement in pairs(placementMap) do
		if seen[placement] then
			warn("Duplicate placement detected for userId:", userId, "placement:", placement)
		end
		seen[placement] = true
		if placement < 1 or placement > totalPlayers then
			warn("Invalid placement for userId:", userId, "placement:", placement, "total:", totalPlayers)
		end
	end
	-- Reset elimination order for next round
	eliminationOrder = {}

	local opponents = math.max(stats.startCount - 1, 0)
	for userId, data in pairs(stats.players) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local kills = data.kills or 0
			local placement = data.placement or 0
			local rewardGold = data.rewardGold or 0
			local rewardXp = data.rewardXp or 0
			player:SetAttribute("LastRoundOpponents", opponents)
			player:SetAttribute("LastRoundKills", kills)
			player:SetAttribute("LastRoundPlacement", placement)
			player:SetAttribute("LastRoundGold", rewardGold)
			player:SetAttribute("LastRoundXP", rewardXp)
			SaveLastRound(player, opponents, kills, placement)
		end
	end
end

local function BuildRoundResults()
	local stats = MainGame.RoundStats
	if not stats then
		return nil, nil
	end

	local playerResults = {}
	   for userId, data in pairs(stats.players) do
		   local player = Players:GetPlayerByUserId(userId)
		   local name = player and player.Name or tostring(userId)
		   local placement = data.placement
		   if not placement or placement < 1 then
			   placement = stats.startCount or 1
		   end
		   table.insert(playerResults, {
			   UserId = userId,
			   Name = name,
			   Kills = data.kills or 0,
			   Placement = placement,
			   IsWinner = (placement == 1),
		   })
	   end

	table.sort(playerResults, function(a, b)
		if a.Placement == b.Placement then
			return a.Kills > b.Kills
		end
		return a.Placement < b.Placement
	end)

	local winners = {}
	for _, entry in ipairs(playerResults) do
		if entry.IsWinner then
			table.insert(winners, entry)
		end
	end

	local gameResults = {
		Map = MainGame.CurrentMap,
		TotalPlayers = stats.startCount,
		Winners = winners,
	}

	return gameResults, playerResults
end

local function ApplyRoundRewards(totalPlayers: number)
	local stats = MainGame.RoundStats
	if not stats then return end

	for userId, data in pairs(stats.players) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local isWinner = data.placement == 1
			if (data.rewardXp or 0) == 0 and (data.rewardGold or 0) == 0 then
				if isWinner then
					data.rewardXp = GameRewardModule.XpReward(player, "win", totalPlayers) or 0
					data.rewardGold = GameRewardModule.CashReward(player, "win", totalPlayers) or 0
				else
					data.rewardXp = GameRewardModule.XpReward(player, "lose", totalPlayers) or 0
					data.rewardGold = GameRewardModule.CashReward(player, "lose", totalPlayers) or 0
				end
			end

			player:SetAttribute("LastRoundGold", data.rewardGold or 0)
			player:SetAttribute("LastRoundXP", data.rewardXp or 0)
		end
	end
end


function MainGame.OnDeath(player: Player)
	print("1")
	if not player then return end
	print("2")

	local userId = player.UserId
	if MainGame.PlayersInGame[userId] then
		local remainingAfterRemoval = CountPlayersInGame() - 1
		MainGame.RecordElimination(player, remainingAfterRemoval)
		MainGame.PlayersInGame[userId] = nil

		   local character = player.Character
		   if character then
			   local hrp = character:FindFirstChild("HumanoidRootPart")
			   if hrp then
				   -- Teleport to intermission lobby spawn
				   local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):FindFirstChild(tostring(math.random(1,4)))
				   if spawnPoint then
					   hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
				   end
			   end
		   end


		local leaderstatsDeaths = player:WaitForChild("leaderstats"):WaitForChild("Deaths")
		local leaderstatsWinStreak = player:WaitForChild("leaderstats"):FindFirstChild("WinStreak")

		if leaderstatsDeaths then
			leaderstatsDeaths.Value += 1
		end
		if leaderstatsWinStreak then
			leaderstatsWinStreak.Value = 0
		end
	else
		print("player isnt in Table PlayersInGame")
	end



end

local function HealAllPlayers()
	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end
end

function MainGame.WipeTools()
	WipeTools:FireAllClients()
end


function MainGame.StartGame(map)
	MainGame.CurrentMap = map


	local configuredRoundTime = MainGame.RoundTime
	local RoundTime = configuredRoundTime
	local PlayerTotal = CountPlayersInGame()


	task.wait(0.5)
	RecieveTools:FireAllClients()

	task.wait(0.5)
	RoundHandlerModule.ChangeStatus("Loading Map")

	SpawnMapModule.Spawn(map)
	RoundHandlerModule.ChangeStatus("Map Loaded")

	task.wait(3)

	-- Short start countdown after teleport
	for i = 3, 1, -1 do
		RoundHandlerModule.ChangeStatus("Starting in " .. i .. "...")
		task.wait(1)
	end

	if CountPlayersInGame() == 0 then
		for _, player in pairs(Players:GetPlayers()) do
			local settings = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Settings")
			local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
			if lobbyMode and lobbyMode.Value == false then
				MainGame.PlayersInGame[player.UserId] = true
			end
		end
	end

	if CountPlayersInGame() == 0 then
		MainGame.GameActive = false
		GameActiveBoolean.Value = false
		return
	end

	InitRoundStats()

	MainGame.GameActive = true
	GameActiveBoolean.Value = true


	while RoundTime > 0 do
		task.wait(1)

		local currentRoundTime = MainGame.RoundTime
		if currentRoundTime ~= configuredRoundTime then
			configuredRoundTime = currentRoundTime
			RoundTime = configuredRoundTime
		end

		if not MainGame.TestMode then
			if CountPlayersInGame() < 2 then 
				local winnerUserId
				for userId in pairs(MainGame.PlayersInGame) do
					winnerUserId = userId
					break
				end

				local Winner = game.Players:GetPlayerByUserId(winnerUserId)
				if Winner then
					RoundHandlerModule.ChangeStatus(tostring(Winner.Name) .. " won")
					local xpAwarded = GameRewardModule.XpReward(Winner, "win", PlayerTotal)
					local cashAwarded = GameRewardModule.CashReward(Winner, "win", PlayerTotal)
					if MainGame.RoundStats and MainGame.RoundStats.players[winnerUserId] then
						MainGame.RoundStats.players[winnerUserId].rewardXp = xpAwarded or 0
						MainGame.RoundStats.players[winnerUserId].rewardGold = cashAwarded or 0
					end

					local leaderstatsWins = Winner:WaitForChild("leaderstats"):WaitForChild("Wins")
					local leaderstatsWinStreak = Winner:WaitForChild("leaderstats"):FindFirstChild("WinStreak")

					if leaderstatsWins then
						leaderstatsWins.Value += 1
					end
					if leaderstatsWinStreak then
						leaderstatsWinStreak.Value += 1
					end
				end
				task.wait(4)
				break
			end
		end

		if CountPlayersInGame() == 0 then
			break
		end

		RoundTime -= 1
		local RoundTimeClean = TimeToMinutesModule.MakeTimeMinute(RoundTime)
		RoundHandlerModule.ChangeStatus(RoundTimeClean)
	end

	RoundHandlerModule.ChangeStatus("Game ended")
	FinalizeRoundStats()
	ApplyRoundRewards(PlayerTotal)

	   local gameResults, playerResults = BuildRoundResults()
	   if gameResults and playerResults then
		   GetRoundResultsRemote:FireAllClients(gameResults, playerResults)
	   end

	   -- Reset WinStreak for all non-winners
	   local winners = {}
	   if gameResults and gameResults.Winners then
		   for _, entry in ipairs(gameResults.Winners) do
			   winners[entry.UserId] = true
		   end
	   end
	   for userId, _ in pairs(MainGame.RoundStats and MainGame.RoundStats.players or {}) do
		   if not winners[userId] then
			   local player = Players:GetPlayerByUserId(userId)
			   if player then
				   local leaderstatsWinStreak = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("WinStreak")
				   if leaderstatsWinStreak then
					   leaderstatsWinStreak.Value = 0
				   end
			   end
		   end
	   end

	task.wait(2)
	for i , v in pairs(MainGame.PlayersInGame) do

		local player = Players:GetPlayerByUserId(i)
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and not player:FindFirstChild("leaderstats"):WaitForChild("Settings"):FindFirstChild("LobbyMode").Value then
				local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):WaitForChild(tostring(math.random(1,4)))
				hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0) 
			end
		end
	end

	task.wait(0.5)
	HealAllPlayers()


	print(MainGame.PlayersInGame)
	MainGame.WipeTools()
	MainGame.GameActive = false
	GameActiveBoolean.Value = false
	table.clear(MainGame.PlayersInGame)
	MainGame.RoundStats = nil


end













return MainGame

