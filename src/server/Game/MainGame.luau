local MainGame = {}
local RoundHandlerModule = require(script.Parent.RoundHandler)
local ZoneHandler = require(script.Parent.GameZone)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RoundResultsFolder = RemotesFolder:WaitForChild("RoundResults")
local GetRoundResultsRemote = RoundResultsFolder:WaitForChild("GetRoundResults")
local KnivesInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))

-- Spectating Remotes setup
local SpectatingRemotesFolder = RemotesFolder:WaitForChild("Spectating")
local ReceiveInfoRemote = SpectatingRemotesFolder:WaitForChild("Receive")

local TimeToMinutesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))

local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")

local RoundCountdownRemote = RemotesFolder:FindFirstChild("RoundCountdown")

MainGame.GameActive = false
MainGame.PlayersInGame = {}
MainGame.RoundTime = 3 * 60
MainGame.CurrentMap = nil
MainGame.TestMode = false
MainGame.LobbyModeLock = false

local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")
local GameRewardModule = require(script.Parent:WaitForChild("GameReward"))
local AntiFarmModule = require(script.Parent:WaitForChild("AntiFarm"))
local SpawnMapModule = require(script.Parent:WaitForChild("SpawnMap"))
local QuestsHandler = require(script.Parent.Parent:WaitForChild("ServicesHandler"):WaitForChild("QuestsHandler"))

local Players = game:GetService("Players")
local ProfileManager = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("ProfileManager"))

MainGame.RoundStats = nil

-- Tracks the order players were eliminated (first eliminated = last place)
local eliminationOrder = {}

-- Tracks pending kills (victimUserId -> killerPlayer)
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

-- Register a pending kill - called by knife modules BEFORE damage
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

    -- Prevent duplicate entries in eliminationOrder
    for _, existingId in ipairs(eliminationOrder) do
        if existingId == player.UserId then
            return -- Already recorded
        end
    end

    table.insert(eliminationOrder, player.UserId)
end

local RoundHistoryMax = 10

local function SaveLastRound(player: Player, opponents: number, kills: number, placement: number)
    local profile = ProfileManager.GetProfile(player)
    if not profile or not profile:IsActive() then return end

    local data = profile.Data
    local entryTimestamp = os.time()
    local entryId = string.format("%d_%d_%d", entryTimestamp, player.UserId, math.random(100000, 999999))

    local lastRoundEntry = {
        Opponents = opponents,
        Kills = kills,
        Placement = placement,
        Timestamp = entryTimestamp,
        EntryId = entryId,
    }

    data.LastRound = lastRoundEntry
    data.RoundHistory = data.RoundHistory or {}

    local top = data.RoundHistory[1]
    local isDuplicateTop = type(top) == "table" and tostring(top.EntryId) == entryId
    if not isDuplicateTop then
        table.insert(data.RoundHistory, 1, lastRoundEntry)
    else
        data.RoundHistory[1] = lastRoundEntry
    end
    while #data.RoundHistory > RoundHistoryMax do
        table.remove(data.RoundHistory)
    end

    player:SetAttribute("LastRoundOpponents", opponents)
    player:SetAttribute("LastRoundKills", kills)
    player:SetAttribute("LastRoundPlacement", placement)
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
    local place = #survivors + 1
    for i = #eliminationOrder, 1, -1 do
        local userId = eliminationOrder[i]
        local data = stats.players[userId]
        if data and data.placement == nil then
            data.placement = place
            place += 1
        end
    end

    -- Safety fallback
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

    eliminationOrder = {}
end

local function ApplyRoundRewards()
    local stats = MainGame.RoundStats
    if not stats then return end

    local totalPlayers = stats.startCount
    local serverPlayerCount = #Players:GetPlayers()

    for userId, data in pairs(stats.players) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            local policy = AntiFarmModule.GetRewardPolicy(player, totalPlayers, serverPlayerCount)
            QuestsHandler.AddProgress(player, "ROUNDS_PLAYED", 1)

            local isWinner = data.placement == 1
            if (data.rewardXp or 0) == 0 and (data.rewardGold or 0) == 0 then
                if isWinner then
                    data.rewardXp = GameRewardModule.XpReward(player, "win", serverPlayerCount, policy.RewardMultiplier) or 0
                    data.rewardGold = GameRewardModule.CashReward(player, "win", serverPlayerCount, policy.RewardMultiplier) or 0
                else
                    data.rewardXp = GameRewardModule.XpReward(player, "lose", serverPlayerCount, policy.RewardMultiplier) or 0
                    data.rewardGold = GameRewardModule.CashReward(player, "lose", serverPlayerCount, policy.RewardMultiplier) or 0
                end
            end

            player:SetAttribute("LastRoundGold", data.rewardGold or 0)
            player:SetAttribute("LastRoundXP", data.rewardXp or 0)
            player:SetAttribute("LastRoundOpponents", totalPlayers - 1)
            player:SetAttribute("LastRoundKills", data.kills or 0)
            player:SetAttribute("LastRoundPlacement", data.placement or 0)

            if (data.placement or 999) <= 3 then
                QuestsHandler.AddProgress(player, "TOP3_FINISHES", 1)
            end
            QuestsHandler.AddProgress(player, "MATCH_GOLD_EARNED", data.rewardGold or 0)

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
            ProfileManager.SaveProfile(player)
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

    local MapsModule = require(script.Parent:WaitForChild("Maps"))
    local mapInfo = nil
    if MainGame.CurrentMap and MapsModule[MainGame.CurrentMap] then
        mapInfo = MapsModule[MainGame.CurrentMap]
    end
    local resultsImage = mapInfo and mapInfo.ResultsImage or nil

    local gameResults = {
        Map = MainGame.CurrentMap,
        TotalPlayers = stats.startCount,
        Winners = winners,
        MapImage = resultsImage,
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

    local killer = pendingKills[userId]
    if killer and killer ~= player then
        local roundParticipants = (MainGame.RoundStats and MainGame.RoundStats.startCount) or 0
        local serverPlayerCount = #Players:GetPlayers()
        local killerPolicy = AntiFarmModule.GetRewardPolicy(killer, roundParticipants, serverPlayerCount)
        local victimPolicy = AntiFarmModule.GetRewardPolicy(player, roundParticipants, serverPlayerCount)

        MainGame.AddRoundKill(killer)
        GameRewardModule.XpReward(killer, "kill", serverPlayerCount, killerPolicy.RewardMultiplier)
        GameRewardModule.CashReward(killer, "kill", serverPlayerCount, killerPolicy.RewardMultiplier)
        GameRewardModule.XpReward(player, "lose", serverPlayerCount, victimPolicy.RewardMultiplier)
        GameRewardModule.CashReward(player, "lose", serverPlayerCount, victimPolicy.RewardMultiplier)
        if killerPolicy.RewardMultiplier > 0 then
            QuestsHandler.AddProgress(killer, "KILLS", 1)
        end
        pendingKills[userId] = nil
    end

    MainGame.RecordElimination(player)
    MainGame.PlayersInGame[userId] = nil
    player:SetAttribute("InRound", false)

    ZoneHandler.NotifyPlayer(player, false) 
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

function MainGame.IsLobbyModeLocked()
    return MainGame.LobbyModeLock == true
end

function MainGame.StartGame(map)
    MainGame.LobbyModeLock = true
    MainGame.CurrentMap = map

    for _, player in pairs(Players:GetPlayers()) do
        player:SetAttribute("LastRoundKills", 0)
        player:SetAttribute("LastRoundPlacement", 0)
        player:SetAttribute("LastRoundOpponents", 0)
        player:SetAttribute("LastRoundGold", 0)
        player:SetAttribute("LastRoundXP", 0)
        player:SetAttribute("InRound", false)
    end

    local configuredRoundTime = MainGame.RoundTime
    local RoundTime = configuredRoundTime

    task.wait(0.5)
    RecieveTools:FireAllClients()

    local COUNTDOWN_SECONDS = 10
    local FADE_AT = 6
    RoundCountdownRemote:FireAllClients("pre", COUNTDOWN_SECONDS, FADE_AT)
    RoundHandlerModule.ChangeStatus("")

    task.wait(COUNTDOWN_SECONDS - FADE_AT + 0.5)

    SpawnMapModule.Spawn(map)
    task.wait(2)

    RoundCountdownRemote:FireAllClients("fight")
    task.wait(3.5)

    if CountPlayersInGame() == 0 then
        for _, player in pairs(Players:GetPlayers()) do
            local leaderstats = player:FindFirstChild("leaderstats")
            local settings = leaderstats and leaderstats:FindFirstChild("Settings")
            local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
            if lobbyMode and lobbyMode.Value == false then
                MainGame.PlayersInGame[player.UserId] = true
                player:SetAttribute("InRound", true)
            end
        end
    end

    if CountPlayersInGame() == 0 then
        MainGame.GameActive = false
        GameActiveBoolean.Value = false
        MainGame.LobbyModeLock = false
        return
    end

    InitRoundStats()
    local PlayerTotal = MainGame.RoundStats.startCount

    MainGame.GameActive = true
    GameActiveBoolean.Value = true
    
    task.spawn(function()
        ZoneHandler.SpawnZone()
        task.wait(1)
        ZoneHandler.StartZone()
    end)


    while RoundTime > 0 do
        task.wait(1)

        local currentRoundTime = MainGame.RoundTime
        if currentRoundTime ~= configuredRoundTime then
            configuredRoundTime = currentRoundTime
            RoundTime = configuredRoundTime
        end

        ReplicatedStorage:WaitForChild("Timer").Value = RoundTime

        if not MainGame.TestMode then
            if CountPlayersInGame() <= 1 then
                local winnerUserId
                for odUserId in pairs(MainGame.PlayersInGame) do
                    winnerUserId = odUserId
                    break
                end

                if not winnerUserId then
                    RoundHandlerModule.ChangeStatus("Draw!")
                    task.wait(0.5)
                    break
                end

                local winner = Players:GetPlayerByUserId(winnerUserId)
                if winner then
                    local serverPlayerCount = #Players:GetPlayers()
                    local winnerPolicy = AntiFarmModule.GetRewardPolicy(winner, PlayerTotal, serverPlayerCount)

                    if MainGame.RoundStats and MainGame.RoundStats.players[winnerUserId] then
                        local xpAwarded = GameRewardModule.XpReward(winner, "win", serverPlayerCount, winnerPolicy.RewardMultiplier) or 0
                        local cashAwarded = GameRewardModule.CashReward(winner, "win", serverPlayerCount, winnerPolicy.RewardMultiplier) or 0
                        MainGame.RoundStats.players[winnerUserId].rewardXp = xpAwarded
                        MainGame.RoundStats.players[winnerUserId].rewardGold = cashAwarded
                    end

                    local leaderstats = winner:WaitForChild("leaderstats")
                    local wins = leaderstats:FindFirstChild("Wins")
                    local winStreak = leaderstats:FindFirstChild("WinStreak")
                    if winnerPolicy.CanReceiveWinCredit then
                        if wins then wins.Value += 1 end
                        if winStreak then winStreak.Value += 1 end
                        QuestsHandler.AddProgress(winner, "WINS", 1)
                    end
                end

                task.wait(0.5)
                break
            end
        end

        if CountPlayersInGame() == 0 then
            break
        end

        RoundTime -= 1
        RoundHandlerModule.ChangeStatus(TimeToMinutesModule.MakeTimeMinute(RoundTime))
    end

    RoundCountdownRemote:FireAllClients("roundover")
    ZoneHandler._zoneActive = false
    ZoneHandler.StopZone()

    FinalizeRoundStats()
    local gameResults, playerResults = BuildRoundResults()

    task.spawn(function()
        ApplyRoundRewards()
    end)

    if gameResults and playerResults then
        task.wait(1.9) 
        GetRoundResultsRemote:FireAllClients(gameResults, playerResults)
    end

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

    -- FIXED: Teleports all survivors back to lobby, even if they toggled LobbyMode on mid-match
    for odUserId in pairs(MainGame.PlayersInGame) do
        local player = Players:GetPlayerByUserId(odUserId)
        if player and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
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
    MainGame.LobbyModeLock = false
    table.clear(MainGame.PlayersInGame)
    table.clear(pendingKills)
    MainGame.RoundStats = nil

    for _, p in pairs(Players:GetPlayers()) do
        p:SetAttribute("InRound", false)
    end
end

-- ==========================================
-- BACKEND LISTENER FOR SPECTATOR DATA
-- ==========================================
ReceiveInfoRemote.OnServerEvent:Connect(function(requestingPlayer, action, targetPlayer)
    if action == "RequestInfo" and targetPlayer then
        local kills = 0
        
        if MainGame.RoundStats and MainGame.RoundStats.players[targetPlayer.UserId] then
            kills = MainGame.RoundStats.players[targetPlayer.UserId].kills or 0
        end

        local knifeImageId = ""
        if targetPlayer:FindFirstChild("leaderstats"):FindFirstChild("EquippedKnife") then
            local equippedKnifeValue = targetPlayer.leaderstats.EquippedKnife.Value
            local knifeInfo = KnivesInfoModule[equippedKnifeValue].Image
            if knifeInfo then
                knifeImageId = knifeInfo
            end
        end

        ReceiveInfoRemote:FireClient(requestingPlayer, kills, knifeImageId)
    end
end)

return MainGame