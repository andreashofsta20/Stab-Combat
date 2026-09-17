local MainGame = {}
local RoundHandlerModule = require(script.Parent.RoundHandler)
local ZoneHandler = require(script.Parent.GameZone)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RoundResultsFolder = RemotesFolder:WaitForChild("RoundResults")
local GetRoundResultsRemote = RoundResultsFolder:WaitForChild("GetRoundResults")
local KnivesInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))

local TimeToMinutesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))
local GameModes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameModes"))

local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")

local RoundCountdownRemote = RemotesFolder:FindFirstChild("RoundCountdown")

MainGame.GameActive = false
MainGame.PlayersInGame = {}
MainGame.RoundTime = 3 * 60
MainGame.CurrentMode = GameModes.FFA
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


local PlayerGotKilledRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("PlayerGotKilledRemote")
MainGame.RoundStats = nil

local eliminationOrder = {}
local pendingKills = {}
local deathLocks = {}

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
        mode = MainGame.CurrentMode,
        rewardsApplied = false,
    }
end

function MainGame.RegisterPendingKill(killer: Player, victimUserId: number)
    local stats = MainGame.RoundStats
    if not stats or not killer or not victimUserId then
        return
    end

    if not stats.players[killer.UserId]
        or not stats.players[victimUserId]
        or not MainGame.PlayersInGame[killer.UserId]
        or not MainGame.PlayersInGame[victimUserId] then
        return
    end

    if killer.UserId ~= victimUserId and not pendingKills[victimUserId] then
        pendingKills[victimUserId] = killer
    end
end

function MainGame.ClearPendingKill(victimUserId: number)
    if type(victimUserId) == "number" then
        pendingKills[victimUserId] = nil
    end
end

-- ==========================================
-- UPDATED KILL LOGIC (FOR SPECTATING)
-- ==========================================
function MainGame.AddRoundKill(killer: Player)
    if not killer then return end
    local stats = MainGame.RoundStats
    if not stats then return end
    local data = stats.players[killer.UserId]
    if not data then return end
    
    data.kills += 1
    
    -- NEW: Update attribute so spectating clients see it instantly
    killer:SetAttribute("CurrentRoundKills", data.kills)
    
    PlayerGotKilledRemote:FireClient(killer, "Kill")
end

function MainGame.RecordElimination(player: Player)
    if not player then return end
    local stats = MainGame.RoundStats
    if not stats then return end
    local data = stats.players[player.UserId]
    if not data or data.placement ~= nil then return end

    for _, existingId in ipairs(eliminationOrder) do
        if existingId == player.UserId then return end
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

    local survivors = {}
    for userId, data in pairs(stats.players) do
        if not eliminatedSet[userId] then
            table.insert(survivors, { userId = userId, kills = data.kills or 0 })
        end
    end

    table.sort(survivors, function(a, b)
        if a.kills == b.kills then
            return a.userId < b.userId
        end
        return a.kills > b.kills
    end)

    for i, entry in ipairs(survivors) do
        stats.players[entry.userId].placement = i
    end

    local place = #survivors + 1
    for i = #eliminationOrder, 1, -1 do
        local userId = eliminationOrder[i]
        local data = stats.players[userId]
        if data and data.placement == nil then
            data.placement = place
            place += 1
        end
    end

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
    if not stats or stats.rewardsApplied then return end
    stats.rewardsApplied = true

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
            if isWinner and policy.CanReceiveWinCredit then
                local leaderstats = player:FindFirstChild("leaderstats")
                local wins = leaderstats and leaderstats:FindFirstChild("Wins")
                local winStreak = leaderstats and leaderstats:FindFirstChild("WinStreak")
                if wins then wins.Value += 1 end
                if winStreak then winStreak.Value += 1 end
                QuestsHandler.AddProgress(player, "WINS", 1)
            end
            QuestsHandler.AddProgress(player, "MATCH_GOLD_EARNED", data.rewardGold or 0)

            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local killsStat = leaderstats:FindFirstChild("Kills")
                if killsStat then killsStat.Value += data.kills or 0 end
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
        if a.Placement == b.Placement then return a.Kills > b.Kills end
        return a.Placement < b.Placement
    end)

    local winners = {}
    for _, entry in ipairs(playerResults) do
        if entry.IsWinner then table.insert(winners, entry) end
    end

    local MapsModule = require(script.Parent:WaitForChild("Maps"))
    local resultsImage = MainGame.CurrentMap and MapsModule[MainGame.CurrentMap] and MapsModule[MainGame.CurrentMap].ResultsImage or nil

    local gameResults = {
        Map = MainGame.CurrentMap,
        Mode = MainGame.CurrentMode.DisplayName,
        TotalPlayers = stats.startCount,
        Winners = winners,
        MapImage = resultsImage,
    }

    return gameResults, playerResults
end

function MainGame.OnDeath(player: Player)
    if not player then return end

    local userId = player.UserId
    if not MainGame.PlayersInGame[userId] then return end
    if deathLocks[userId] then return end
    deathLocks[userId] = true

    local killer = pendingKills[userId]
    local stats = MainGame.RoundStats
    if killer and killer ~= player and stats
        and stats.players[killer.UserId]
        and stats.players[userId]
        and MainGame.PlayersInGame[killer.UserId] then
        local roundParticipants = stats.startCount
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
    end

    pendingKills[userId] = nil
    local leaderstats = player:FindFirstChild("leaderstats")
    local deathsStat = leaderstats and leaderstats:FindFirstChild("Deaths")
    if deathsStat then
        deathsStat.Value += 1
    end

    local mode = MainGame.CurrentMode
    if mode.Respawns then
        player:SetAttribute("InRound", true)
        task.delay(1.5, function()
            deathLocks[userId] = nil
            if MainGame.GameActive and MainGame.PlayersInGame[userId] and player.Parent then
                player:LoadCharacter()
                SpawnMapModule.RespawnPlayer(player, MainGame.CurrentMap)
            end
        end)
        return
    end

    MainGame.RecordElimination(player)
    MainGame.PlayersInGame[userId] = nil
    player:SetAttribute("InRound", false)
    ZoneHandler.NotifyPlayer(player, false)
    
    local character = player.Character
    if character then
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):FindFirstChild(tostring(math.random(1, 4)))
            if spawnPoint then
                task.wait(2)
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
            if humanoid then humanoid.Health = humanoid.MaxHealth end
        end
    end
end

function MainGame.WipeTools()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            for _, child in ipairs(character:GetChildren()) do
                if child:IsA("Tool") then
                    child:Destroy()
                end
            end
        end

        local backpack = player:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    child:Destroy()
                end
            end
        end
    end

    WipeTools:FireAllClients()
end

function MainGame.IsLobbyModeLocked()
    return MainGame.LobbyModeLock == true
end

function MainGame.StartGame(map, modeId: string?)
    MainGame.LobbyModeLock = true
    MainGame.CurrentMap = map
    MainGame.CurrentMode = GameModes.Get(modeId or GameModes.FFA.Id) or GameModes.FFA

    for _, player in pairs(Players:GetPlayers()) do
        player:SetAttribute("LastRoundKills", 0)
        player:SetAttribute("LastRoundPlacement", 0)
        player:SetAttribute("LastRoundOpponents", 0)
        player:SetAttribute("LastRoundGold", 0)
        player:SetAttribute("LastRoundXP", 0)
        player:SetAttribute("InRound", false)
        player:SetAttribute("CurrentRoundParticipant", false)
        
        -- NEW: Ensure spectate UI resets to 0 at the start of every game
        player:SetAttribute("CurrentRoundKills", 0)
        player:SetAttribute("CurrentRoundMode", MainGame.CurrentMode.DisplayName)
    end

    local configuredRoundTime = MainGame.CurrentMode.RoundDuration
    MainGame.RoundTime = configuredRoundTime
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
                player:SetAttribute("CurrentRoundParticipant", true)
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
    local roundPlayers = {}
    for userId in pairs(MainGame.PlayersInGame) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            table.insert(roundPlayers, player)
        end
    end
    local placedPlayers = SpawnMapModule.PlacePlayers(map, roundPlayers)
    if placedPlayers ~= #roundPlayers then
        warn(("MainGame: placed %d/%d round players"):format(placedPlayers, #roundPlayers))
    end
    -- Respawns are controlled by the round so FFA cannot also receive
    -- Roblox's automatic respawn before the delayed round respawn.
    Players.CharacterAutoLoads = false
    local PlayerTotal = MainGame.RoundStats.startCount

    MainGame.GameActive = true
    GameActiveBoolean.Value = true
    
    if MainGame.CurrentMode.ZoneRequired then
        task.spawn(function()
            ZoneHandler.SpawnZone()
            task.wait(1)
            ZoneHandler.StartZone()
        end)
    end


    while not MainGame.CurrentMode.HasTimer or RoundTime > 0 do
        task.wait(1)

        if MainGame.CurrentMode.HasTimer and MainGame.RoundTime ~= configuredRoundTime then
            configuredRoundTime = MainGame.RoundTime
            RoundTime = configuredRoundTime
        end

        ReplicatedStorage:WaitForChild("Timer").Value = MainGame.CurrentMode.HasTimer and RoundTime or 0

        if not MainGame.TestMode then
            if MainGame.CurrentMode.EliminationEndsRound and CountPlayersInGame() <= 1 then
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
                -- Rewards and win credit are applied once after placements are finalized.
                task.wait(0.5)
                break
            end
        end

        if CountPlayersInGame() == 0 then break end

        if MainGame.CurrentMode.HasTimer then
            RoundTime -= 1
            RoundHandlerModule.ChangeStatus(TimeToMinutesModule.MakeTimeMinute(RoundTime))
        else
            RoundHandlerModule.ChangeStatus("BATTLE ROYALE - LAST SURVIVOR")
        end
    end

    RoundCountdownRemote:FireAllClients("roundover")
    if MainGame.CurrentMode.ZoneRequired then
        ZoneHandler._zoneActive = false
        ZoneHandler.StopZone()
    end

    FinalizeRoundStats()
    local gameResults, playerResults = BuildRoundResults()

    ApplyRoundRewards()

    if gameResults and playerResults then
        task.wait(1.9) 
        GetRoundResultsRemote:FireAllClients(gameResults, playerResults)
    end

    local winnerIds = {}
    if gameResults and gameResults.Winners then
        for _, entry in ipairs(gameResults.Winners) do winnerIds[entry.UserId] = true end
    end
    for odUserId in pairs(MainGame.RoundStats and MainGame.RoundStats.players or {}) do
        if not winnerIds[odUserId] then
            local player = Players:GetPlayerByUserId(odUserId)
            if player then
                local winStreak = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("WinStreak")
                if winStreak then winStreak.Value = 0 end
            end
        end
    end

    for odUserId in pairs(MainGame.PlayersInGame) do
        local player = Players:GetPlayerByUserId(odUserId)
        if player and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):WaitForChild(tostring(math.random(1, 4)))
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
    table.clear(deathLocks)
    MainGame.RoundStats = nil

    Players.CharacterAutoLoads = true
    for _, p in pairs(Players:GetPlayers()) do
        local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            p:LoadCharacter()
        end
        p:SetAttribute("InRound", false)
        p:SetAttribute("CurrentRoundParticipant", false)
        p:SetAttribute("CurrentRoundKills", 0) -- Clear attribute for lobby
        p:SetAttribute("CurrentRoundMode", nil)
    end
end

-- NOTE: The "ReceiveInfoRemote" listener block was removed. 
-- Clients now get data via Attributes and leaderstats.

return MainGame