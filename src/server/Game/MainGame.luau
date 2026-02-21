local MainGame = {}
local RoundHandlerModule = require(script.Parent.RoundHandler)
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RoundResultsFolder = RemotesFolder:WaitForChild("RoundResults")
local GetRoundResultsRemote = RoundResultsFolder:WaitForChild("GetRoundResults")

local TimeToMinutesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))

local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")

MainGame.GameActive = false
MainGame.PlayersInGame = {}
MainGame.RoundTime = 3 * 60
MainGame.CurrentMap = nil
MainGame.TestMode = false

local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")
local GameRewardModule = require(script.Parent:WaitForChild("GameReward"))
local SpawnMapModule = require(script.Parent:WaitForChild("SpawnMap"))

local Players = game:GetService("Players")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerStats_v2BETA111TEST111_")

MainGame.RoundStats = nil

-- Tracks the order players were eliminated (first eliminated = last place)
local eliminationOrder = {}

-- FIX: Tracks pending kills (victimUserId -> killerPlayer)
local pendingKills = {}

local function CountPlayersInGame()
	local n = 0
	for _ in pairs(MainGame.PlayersInGame) do
		n += 1
	end
	return n
end

local function InitRoundStats()
	local playersStats = {}
	for userId in pairs(MainGame.PlayersInGame) do
		playersStats[userId] = {
			kills = 0,
			placement = nil,
			rewardGold = 0,
			rewardXp = 0,
		}
	end

	MainGame.RoundStats = {
		startCount = CountPlayersInGame(),
		players = playersStats,
	}
end

-- FIX: Register a pending kill - called by knife modules BEFORE damage
function MainGame.RegisterPendingKill(killer: Player, victimUserId: number)
	if killer and victimUserId then
		pendingKills[victimUserId] = killer
	end
end

-- Credit kill to the killer
function MainGame.AddRoundKill(killer: Player)
	if not killer then return end
	local stats = MainGame.RoundStats
	if not stats then return end
	local data = stats.players[killer.UserId]
	if not data then return end
	data.kills += 1
end

function MainGame.RecordElimination(player: Player)
	if not player then return end
	local stats = MainGame.RoundStats
	if not stats then return end
	local data = stats.players[player.UserId]
	if not data or data.placement ~= nil then return end

	-- FIX: Prevent duplicate entries in eliminationOrder
	for _, existingId in ipairs(eliminationOrder) do
		if existingId == player.UserId then
			return -- Already recorded
		end
	end

	table.insert(eliminationOrder, player.UserId)
end

local RoundHistoryMax = 10

local function SaveLastRound(player: Player, opponents: number, kills: number, placement: number)
	local success, err = pcall(function()
		PlayerDataStore:UpdateAsync(tostring(player.UserId), function(oldData)
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

	local totalPlayers = stats.startCount
	local eliminatedSet = {}
	for _, userId in ipairs(eliminationOrder) do
		eliminatedSet[userId] = true
	end

	-- Survivors = players still in PlayersInGame table (not eliminated)
	local survivors = {}
	for userId, data in pairs(stats.players) do
		if not eliminatedSet[userId] then
			table.insert(survivors, { userId = userId, kills = data.kills or 0 })
		end
	end

	-- Sort survivors by kills descending for tiebreaking
	table.sort(survivors, function(a, b)
		return a.kills > b.kills
	end)

	-- Assign placements 1, 2, 3... to survivors
	for i, entry in ipairs(survivors) do
		stats.players[entry.userId].placement = i
	end

	-- Assign remaining placements to eliminated players in reverse order
	-- (last eliminated = best placement among eliminated)
	local place = #survivors + 1
	for i = #eliminationOrder, 1, -1 do
		local userId = eliminationOrder[i]
		local data = stats.players[userId]
		if data and data.placement == nil then
			data.placement = place
			place += 1
		end
	end

	-- Safety fallback: anyone still missing a placement gets last
	for userId, data in pairs(stats.players) do
		if not data.placement then
			warn("Placement fallback triggered for userId:", userId)
			data.placement = totalPlayers
		end
	end

	-- Set attributes for display
	for userId, data in pairs(stats.players) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("LastRoundOpponents", totalPlayers - 1)
			player:SetAttribute("LastRoundKills", data.kills or 0)
			player:SetAttribute("LastRoundPlacement", data.placement or 0)
		end
	end

	-- Reset elimination order for next round
	eliminationOrder = {}
end

local function ApplyRoundRewards()
	local stats = MainGame.RoundStats
	if not stats then return end

	local totalPlayers = stats.startCount
	local OnJoined = require(script.Parent.Parent.DataStore.OnJoined)

	for userId, data in pairs(stats.players) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local isWinner = data.placement == 1
			-- Only compute rewards if not already set (winner reward may have been set early)
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
			player:SetAttribute("LastRoundOpponents", totalPlayers - 1)
			player:SetAttribute("LastRoundKills", data.kills or 0)
			player:SetAttribute("LastRoundPlacement", data.placement or 0)

			-- Update persistent leaderstats Kills/Deaths at round end
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				local killsStat = leaderstats:FindFirstChild("Kills")
				local deathsStat = leaderstats:FindFirstChild("Deaths")
				if killsStat then
					killsStat.Value += data.kills or 0
				end
				if deathsStat and data.placement ~= 1 then
					deathsStat.Value += 1
				end
			end

			SaveLastRound(player, totalPlayers - 1, data.kills or 0, data.placement or 0)
			OnJoined.SavePlayerData(player)
		end
	end
end

local function BuildRoundResults()
	local stats = MainGame.RoundStats
	if not stats then return nil, nil end

	local playerResults = {}
	for userId, data in pairs(stats.players) do
		local player = Players:GetPlayerByUserId(userId)
		local name = player and player.Name or tostring(userId)
		local placement = data.placement or stats.startCount
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

function MainGame.OnDeath(player: Player)
	if not player then return end

	local userId = player.UserId
	if not MainGame.PlayersInGame[userId] then
		print("OnDeath: player not in PlayersInGame, ignoring:", player.Name)
		return
	end

	-- FIX: Credit the kill to the killer if there's a pending kill
	local killer = pendingKills[userId]
	if killer then
		MainGame.AddRoundKill(killer)
		pendingKills[userId] = nil
	end

	-- Record elimination BEFORE removing from PlayersInGame
	MainGame.RecordElimination(player)
	MainGame.PlayersInGame[userId] = nil

	-- Teleport to lobby
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local spawnPoint = workspace:WaitForChild("IntermissionMap")
				:WaitForChild("Lobby")
				:WaitForChild("Spawns")
				:FindFirstChild(tostring(math.random(1, 4)))
			if spawnPoint then
				hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
			end
		end
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

	-- Reset per-player attributes
	for _, player in pairs(Players:GetPlayers()) do
		player:SetAttribute("LastRoundKills", 0)
		player:SetAttribute("LastRoundPlacement", 0)
		player:SetAttribute("LastRoundOpponents", 0)
		player:SetAttribute("LastRoundGold", 0)
		player:SetAttribute("LastRoundXP", 0)
	end

	local configuredRoundTime = MainGame.RoundTime
	local RoundTime = configuredRoundTime

	task.wait(0.5)
	RecieveTools:FireAllClients()

	task.wait(0.5)
	RoundHandlerModule.ChangeStatus("Loading Map")
	SpawnMapModule.Spawn(map)
	RoundHandlerModule.ChangeStatus("Map Loaded")

	task.wait(3)

	for i = 3, 1, -1 do
		RoundHandlerModule.ChangeStatus("Starting in " .. i .. "...")
		task.wait(1)
	end

	-- Populate PlayersInGame BEFORE InitRoundStats so startCount is correct
	if CountPlayersInGame() == 0 then
		for _, player in pairs(Players:GetPlayers()) do
			local leaderstats = player:FindFirstChild("leaderstats")
			local settings = leaderstats and leaderstats:FindFirstChild("Settings")
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

	-- Snapshot player count and init stats NOW that PlayersInGame is final
	InitRoundStats()
	local PlayerTotal = MainGame.RoundStats.startCount

	MainGame.GameActive = true
	GameActiveBoolean.Value = true

	while RoundTime > 0 do
		task.wait(1)

		-- Allow dynamic round time changes
		local currentRoundTime = MainGame.RoundTime
		if currentRoundTime ~= configuredRoundTime then
			configuredRoundTime = currentRoundTime
			RoundTime = configuredRoundTime
		end

		if not MainGame.TestMode then
			if CountPlayersInGame() <= 1 then
				-- Find the last remaining player (the winner)
				local winnerUserId
				for odUserId in pairs(MainGame.PlayersInGame) do
					winnerUserId = odUserId
					break
				end

				local winner = Players:GetPlayerByUserId(winnerUserId)
				if winner then
					RoundHandlerModule.ChangeStatus(winner.Name .. " won!")

					-- Store winner rewards in stats (ApplyRoundRewards will use them)
					if MainGame.RoundStats and MainGame.RoundStats.players[winnerUserId] then
						local xpAwarded = GameRewardModule.XpReward(winner, "win", PlayerTotal) or 0
						local cashAwarded = GameRewardModule.CashReward(winner, "win", PlayerTotal) or 0
						MainGame.RoundStats.players[winnerUserId].rewardXp = xpAwarded
						MainGame.RoundStats.players[winnerUserId].rewardGold = cashAwarded
					end

					local leaderstats = winner:WaitForChild("leaderstats")
					local wins = leaderstats:FindFirstChild("Wins")
					local winStreak = leaderstats:FindFirstChild("WinStreak")
					if wins then wins.Value += 1 end
					if winStreak then winStreak.Value += 1 end
				end

				task.wait(4)
				break
			end
		end

		if CountPlayersInGame() == 0 then
			break
		end

		RoundTime -= 1
		RoundHandlerModule.ChangeStatus(TimeToMinutesModule.MakeTimeMinute(RoundTime))
	end

	RoundHandlerModule.ChangeStatus("Game ended")

	FinalizeRoundStats()
	ApplyRoundRewards()

	local gameResults, playerResults = BuildRoundResults()
	if gameResults and playerResults then
		GetRoundResultsRemote:FireAllClients(gameResults, playerResults)
	end

	-- Reset WinStreak for all non-winners here (single place, after winner is determined)
	local winnerIds = {}
	if gameResults and gameResults.Winners then
		for _, entry in ipairs(gameResults.Winners) do
			winnerIds[entry.UserId] = true
		end
	end
	for odUserId in pairs(MainGame.RoundStats and MainGame.RoundStats.players or {}) do
		if not winnerIds[odUserId] then
			local player = Players:GetPlayerByUserId(odUserId)
			if player then
				local leaderstats = player:FindFirstChild("leaderstats")
				local winStreak = leaderstats and leaderstats:FindFirstChild("WinStreak")
				if winStreak then
					winStreak.Value = 0
				end
			end
		end
	end

	task.wait(2)

	-- Teleport surviving players back to lobby
	for odUserId in pairs(MainGame.PlayersInGame) do
		local player = Players:GetPlayerByUserId(odUserId)
		if player and player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			local leaderstats = player:FindFirstChild("leaderstats")
			local settings = leaderstats and leaderstats:FindFirstChild("Settings")
			local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
			if hrp and lobbyMode and not lobbyMode.Value then
				local spawnPoint = workspace:WaitForChild("IntermissionMap")
					:WaitForChild("Lobby")
					:WaitForChild("Spawns")
					:WaitForChild(tostring(math.random(1, 4)))
				hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
			end
		end
	end

	task.wait(0.5)
	HealAllPlayers()
	MainGame.WipeTools()

	MainGame.GameActive = false
	GameActiveBoolean.Value = false
	table.clear(MainGame.PlayersInGame)
	table.clear(pendingKills) -- FIX: Clear pending kills for next round
	MainGame.RoundStats = nil
end

return MainGame
