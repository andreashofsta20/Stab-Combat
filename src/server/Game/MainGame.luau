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
local MapConfig = require(ReplicatedStorage.Modules.MapConfig)
local Ragdolls = require(script.Parent.Parent.CharacterDeath.RagdollService)

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

-- Kill cam: server tells ONLY the victim whom to watch. Created here if it doesn't exist yet.
local KillCamRemote = RemotesFolder:FindFirstChild("KillCam")
if not KillCamRemote then
    KillCamRemote = Instance.new("RemoteEvent")
    KillCamRemote.Name = "KillCam"
    KillCamRemote.Parent = RemotesFolder
end
local FFA_KILLCAM_SECONDS = 2   -- how long an FFA victim watches their killer before respawning
MainGame.RoundStats = nil
MainGame.RoundId = 0

local eliminationOrder = {}
local pendingKills = {}
local deathLocks = {}
local roundStartForceFields = {}

local function ClearRoundStartProtection()
    for forceField in pairs(roundStartForceFields) do forceField:Destroy() end
    table.clear(roundStartForceFields)
end

local function ProtectRoundStart()
    local seconds = MapConfig.RoundStartProtectionSeconds
    if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 or seconds == math.huge then return end
    for userId in pairs(MainGame.PlayersInGame) do
        local player = Players:GetPlayerByUserId(userId)
        local character = player and player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not player or player.Parent ~= Players or not humanoid or humanoid.Health <= 0 then continue end
        local forceField = Instance.new("ForceField")
        forceField.Name, forceField.Visible, forceField.Parent = "RoundStartProtection", true, character
        roundStartForceFields[forceField] = true
        -- Capture this exact field, never look up a player's later character
        -- or remove a newer round's protection from a delayed callback.
        task.delay(seconds, function()
            if not roundStartForceFields[forceField] then return end
            roundStartForceFields[forceField] = nil
            forceField:Destroy()
        end)
    end
end

local function CountPlayersInGame()
    local n = 0
    for _ in pairs(MainGame.PlayersInGame) do
        n += 1
    end
    return n
end

local function RespawnAtLobby(player: Player, roundId: number?, previousCharacter: Model?)
    if not player or player.Parent ~= Players then return end
    if roundId and MainGame.RoundId ~= roundId then return end
    if previousCharacter and player.Character ~= previousCharacter then return end

    player:LoadCharacter()
    if player.Parent ~= Players or (roundId and MainGame.RoundId ~= roundId) then return end
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):FindFirstChild(tostring(math.random(1, 4)))
    if hrp and spawnPoint then
        hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
        player:SetAttribute("ServerTeleportPosition", hrp.Position)
        player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
    end
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

function MainGame.RegisterPendingKill(killer: Player, victimUserId: number, weapon: string?)
    local stats = MainGame.RoundStats
    if not MainGame.GameActive or not stats or not killer or not victimUserId then
        return
    end

    if not stats.players[killer.UserId]
        or not stats.players[victimUserId]
        or not MainGame.PlayersInGame[killer.UserId]
        or not MainGame.PlayersInGame[victimUserId] then
        return
    end

    if killer.UserId ~= victimUserId and not pendingKills[victimUserId] then
        local victim = Players:GetPlayerByUserId(victimUserId)
        pendingKills[victimUserId] = {killer = killer, character = victim and victim.Character, roundId = MainGame.RoundId, weapon = weapon}
    end
end

-- Weapon handlers share one authoritative damage/credit path. A corpse,
-- replacement character or ForceField cannot produce damage feedback/credit.
function MainGame.DamagePlayer(killer: Player, victim: Player, humanoid: Humanoid, amount: number, impact: any?): number
    if not MainGame.GameActive or not killer or not victim or killer == victim
        or not MainGame.PlayersInGame[killer.UserId] or not MainGame.PlayersInGame[victim.UserId]
        or killer:GetAttribute("DataReady") ~= true or victim:GetAttribute("DataReady") ~= true
        or killer:GetAttribute("InventoryLocked") == true or killer:GetAttribute("MovementAdmitted") == false
        or killer.Parent ~= Players or victim.Parent ~= Players
        or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then return 0 end
    local attackerHumanoid = killer.Character and killer.Character:FindFirstChildOfClass("Humanoid")
    if not attackerHumanoid or attackerHumanoid.Health <= 0 or not humanoid
        or humanoid.Parent ~= victim.Character or humanoid.Health <= 0
        or victim.Character:FindFirstChildOfClass("ForceField") then return 0 end
    local before, character = humanoid.Health, victim.Character
    Ragdolls.Prepare(character)
    if before <= amount then
        MainGame.RegisterPendingKill(killer, victim.UserId, type(impact) == "table" and impact.Kind or nil)
        if type(impact) == "table" then Ragdolls.SetImpact(character, impact.Kind, impact.Direction) end
    end
    humanoid:TakeDamage(amount)
    local dealt = math.max(0, before - humanoid.Health)
    if type(impact) == "table" and dealt > 0 then
        local metrics = script.Parent.Parent.CombatHandler:FindFirstChild("CompetitiveStats")
        if metrics then require(metrics).Hit(killer, impact.Kind, dealt) end
    end
    if humanoid.Health <= 0 then
        MainGame.OnDeath(victim, character) -- commit now, even with deferred Died signals
    elseif before <= amount then
        MainGame.ClearPendingKill(victim.UserId)
        Ragdolls.ClearImpact(character)
    end
    return dealt
end

function MainGame.ClearPendingKill(victimUserId: number)
    if type(victimUserId) == "number" then
        pendingKills[victimUserId] = nil
    end
end

function MainGame.OnCharacterAdded(player: Player)
    pendingKills[player.UserId] = nil
    deathLocks[player.UserId] = nil
end

-- ==========================================
-- UPDATED KILL LOGIC (FOR SPECTATING)
-- ==========================================
function MainGame.AddRoundKill(killer: Player, victim: Player?)
    if not killer then return end
    local stats = MainGame.RoundStats
    if not stats then return end
    local data = stats.players[killer.UserId]
    if not data then return end
    
    data.kills += 1
    local leaderstats = killer:FindFirstChild("leaderstats")
    local lifetimeKills = leaderstats and leaderstats:FindFirstChild("Kills")
    if lifetimeKills then lifetimeKills.Value += 1 end -- survives leaving before results
    
    -- NEW: Update attribute so spectating clients see it instantly
    killer:SetAttribute("CurrentRoundKills", data.kills)
    
    local killId = string.format("%d:%d:%d", MainGame.RoundId, killer.UserId, data.kills)
    PlayerGotKilledRemote:FireClient(killer, "Kill", victim and {
        KillId = killId,
        VictimUserId = victim.UserId,
        VictimUsername = victim.Name,
    } or nil)
    return killId
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
    local modeName = "FFA"
    if MainGame.CurrentMode then
        if MainGame.CurrentMode.Id == "BattleRoyale" then
            modeName = "BR"
        elseif MainGame.CurrentMode.Id == "FFA" then
            modeName = "FFA"
        else
            modeName = MainGame.CurrentMode.Id or "FFA"
        end
    end

    local lastRoundEntry = {
        Opponents = opponents,
        Kills = kills,
        Placement = placement,
        GameMode = modeName,
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
    local modeName = "FFA"
    if MainGame.CurrentMode then
        if MainGame.CurrentMode.Id == "BattleRoyale" then
            modeName = "BR"
        elseif MainGame.CurrentMode.Id == "FFA" then
            modeName = "FFA"
        else
            modeName = MainGame.CurrentMode.Id or "FFA"
        end
    end
    player:SetAttribute("LastRoundGameMode", modeName)
end

local function FinalizeRoundStats()
    local stats = MainGame.RoundStats
    if not stats then return end

    local totalPlayers = stats.startCount
    stats.draw = MainGame.CurrentMode.EliminationEndsRound and CountPlayersInGame() == 0
    local eliminatedSet = {}
    for _, userId in ipairs(eliminationOrder) do
        eliminatedSet[userId] = true
    end

    local survivors = {}
    for userId, data in pairs(stats.players) do
        if not eliminatedSet[userId] and not data.forfeited then
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
            local metrics = script.Parent.Parent.CombatHandler:FindFirstChild("CompetitiveStats")
            if metrics then require(metrics).Round(player,MainGame.CurrentMode.Id,not stats.draw and data.placement == 1,data.forfeited == true) end
            player:SetAttribute("LastRoundKills", data.kills or 0)
            player:SetAttribute("LastRoundPlacement", data.placement or 0)
            local modeName = "FFA"
            if MainGame.CurrentMode then
                if MainGame.CurrentMode.Id == "BattleRoyale" then
                    modeName = "BR"
                elseif MainGame.CurrentMode.Id == "FFA" then
                    modeName = "FFA"
                else
                    modeName = MainGame.CurrentMode.Id or "FFA"
                end
            end
            player:SetAttribute("LastRoundGameMode", modeName)
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

            local isWinner = data.placement == 1 and not stats.draw
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
            local modeName = "FFA"
            if MainGame.CurrentMode then
                if MainGame.CurrentMode.Id == "BattleRoyale" then
                    modeName = "BR"
                elseif MainGame.CurrentMode.Id == "FFA" then
                    modeName = "FFA"
                else
                    modeName = MainGame.CurrentMode.Id or "FFA"
                end
            end
            player:SetAttribute("LastRoundGameMode", modeName)

            -- Placement zero represents a forfeit, never a podium finish.
            local placement = data.placement
            if not data.forfeited and placement and placement >= 1 and placement <= 3 then
                QuestsHandler.AddProgress(player, "TOP3_FINISHES", 1)
            end
            if isWinner and policy.CanReceiveWinCredit then
                local leaderstats = player:FindFirstChild("leaderstats")
                local wins = leaderstats and leaderstats:FindFirstChild("Wins")
                local winStreak = leaderstats and leaderstats:FindFirstChild("WinStreak")
                if wins then wins.Value += 1 end
                if winStreak then winStreak.Value += 1 end
                QuestsHandler.AddProgress(player, "WINS", 1)
            elseif not isWinner then
                local leaderstats = player:FindFirstChild("leaderstats")
                local winStreak = leaderstats and leaderstats:FindFirstChild("WinStreak")
                if winStreak then winStreak.Value = 0 end
            end
            QuestsHandler.AddProgress(player, "MATCH_GOLD_EARNED", data.rewardGold or 0)

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
            IsWinner = (placement == 1 and not stats.draw),
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
        Draw = stats.draw == true,
        Winners = winners,
        MapImage = resultsImage,
    }

    return gameResults, playerResults
end

function MainGame.OnDeath(player: Player, character: Model?)
    if not player then return end
    character = character or player.Character
    if character ~= player.Character then return end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health > 0 then return end
    local ragdollOk, ragdollError = pcall(Ragdolls.OnDeath, character)
    if not ragdollOk then warn("[Death] Ragdoll failed: " .. tostring(ragdollError)) end
    if player:GetAttribute("TutorialActive")==true then
        if require(script.Parent.Parent.Tutorial.TutorialRuntime).OnDeath(player,character) then return end
    end

    local userId = player.UserId
    local roundId = MainGame.RoundId
    if not MainGame.GameActive or not MainGame.PlayersInGame[userId] then
        -- Eliminated players can die again after returning to the lobby. Their
        -- old round-stat entry must not disable manual lobby respawning.
        if not Players.CharacterAutoLoads and not deathLocks[userId] then
            deathLocks[userId] = true
            task.delay(Players.RespawnTime, function()
                if not MainGame.PlayersInGame[userId] then RespawnAtLobby(player, roundId, character) end
            end)
        end
        return
    end
    if deathLocks[userId] then return end
    deathLocks[userId] = true

    local pending = pendingKills[userId]
    pendingKills[userId] = nil
    local killer = pending and pending.roundId == roundId and pending.character == character and pending.killer or nil
    -- Who should the victim watch? Only a real, still-connected, different player.
    local killCamTarget = (killer and killer ~= player and killer.Parent == Players) and killer or nil
    local function creditDeath()
        local leaderstats = player:FindFirstChild("leaderstats")
        local deathsStat = leaderstats and leaderstats:FindFirstChild("Deaths")
        if deathsStat then deathsStat.Value += 1 end
        local metricsModule = script.Parent.Parent.CombatHandler:FindFirstChild("CompetitiveStats")
        local metrics = metricsModule and require(metricsModule)
        if metrics then metrics.Death(player,MainGame.CurrentMode.Id) end
        local stats = MainGame.RoundStats
        if killer and killer ~= player and stats
            and stats.players[killer.UserId]
            and stats.players[userId]
            and MainGame.PlayersInGame[killer.UserId] then
            local roundParticipants = stats.startCount
            local serverPlayerCount = #Players:GetPlayers()
            local killerPolicy = AntiFarmModule.GetRewardPolicy(killer, roundParticipants, serverPlayerCount)
            local victimPolicy = AntiFarmModule.GetRewardPolicy(player, roundParticipants, serverPlayerCount)

            local killId = MainGame.AddRoundKill(killer, player)
            if metrics then metrics.Kill(killer,MainGame.CurrentMode.Id,pending and pending.weapon) end
            if killerPolicy.RewardMultiplier > 0 then
                QuestsHandler.AddProgress(killer, "KILLS", 1)
            end
            -- XP pass ownership may yield. Defer rewards until death/membership and
            -- kill credit have been committed, so they cannot hold a round open.
            task.defer(function()
                local earnedXp = GameRewardModule.XpReward(killer, "kill", serverPlayerCount, killerPolicy.RewardMultiplier) or 0
                -- Same identity as the immediate card; never infer VIP/pass/anti-farm rewards on the client.
                if killId and killer.Parent == Players then
                    PlayerGotKilledRemote:FireClient(killer, "KillReward", {KillId = killId, XpEarned = earnedXp})
                end
                GameRewardModule.CashReward(killer, "kill", serverPlayerCount, killerPolicy.RewardMultiplier)
                GameRewardModule.XpReward(player, "lose", serverPlayerCount, victimPolicy.RewardMultiplier)
                GameRewardModule.CashReward(player, "lose", serverPlayerCount, victimPolicy.RewardMultiplier)
            end)
        end
    end
    local function finishDeathCredit()
        local ok, err = pcall(creditDeath)
        if not ok then warn("[Death] Credit failed after respawn was scheduled: " .. tostring(err)) end
    end

    local mode = MainGame.CurrentMode
    if mode.Respawns then
        player:SetAttribute("InRound", true)
        task.delay(FFA_KILLCAM_SECONDS, function()
            if MainGame.RoundId ~= roundId or player.Character ~= character then return end
            deathLocks[userId] = nil
            if MainGame.GameActive and MainGame.PlayersInGame[userId] and player.Parent then
                player:LoadCharacter()
                if MainGame.RoundId == roundId and MainGame.GameActive and MainGame.PlayersInGame[userId] then
                    if not SpawnMapModule.RespawnPlayer(player, MainGame.CurrentMap) then MainGame.LeaveRound(player) end
                end
            end
        end)
        if killCamTarget then
            KillCamRemote:FireClient(player, "Respawn", killCamTarget.UserId, FFA_KILLCAM_SECONDS, character)
        end
        finishDeathCredit()
        return
    end

    MainGame.RecordElimination(player)
    MainGame.PlayersInGame[userId] = nil
    player:SetAttribute("InRound", false)
    task.delay(1.5, function()
        RespawnAtLobby(player, roundId, character)
    end)
    -- Battle Royale: eliminated player spectates their killer (or anyone alive if no killer, e.g. zone).
    KillCamRemote:FireClient(player, "Spectate", killCamTarget and killCamTarget.UserId or 0, 0, character)
    finishDeathCredit()
    ZoneHandler.NotifyPlayer(player, false)
end

function MainGame.LeaveRound(player: Player, disconnected: boolean?)
    if not player or not MainGame.GameActive or not MainGame.PlayersInGame[player.UserId] then
        return
    end

    MainGame.PlayersInGame[player.UserId] = nil
    if MainGame.RoundStats and MainGame.RoundStats.players[player.UserId] then
        MainGame.RoundStats.players[player.UserId].forfeited = true
        MainGame.RoundStats.players[player.UserId].placement = 0
    end
    pendingKills[player.UserId] = nil
    deathLocks[player.UserId] = nil
    player:SetAttribute("InRound", false)
    player:SetAttribute("CurrentRoundParticipant", false)
    ZoneHandler.NotifyPlayer(player, false)
    if disconnected then return end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        local roundId = MainGame.RoundId
        task.delay(1.5, function()
            if not MainGame.PlayersInGame[player.UserId] then RespawnAtLobby(player, roundId, character) end
        end)
        return
    end
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Lobby"):WaitForChild("Spawns"):FindFirstChild(tostring(math.random(1, 4)))
        if spawnPoint then
            hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
            player:SetAttribute("ServerTeleportPosition", hrp.Position)
            player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
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

function MainGame.CleanupRound(respawn: boolean?)
    MainGame.GameActive = false
    GameActiveBoolean.Value = false
    ClearRoundStartProtection()
    MainGame.RoundId += 1 -- invalidate every delayed callback from the previous round
    MainGame.LobbyModeLock = false
    ZoneHandler._zoneActive = false
    ZoneHandler.StopZone()
    MainGame.WipeTools()
    SpawnMapModule.ReleasePlacements()
    table.clear(MainGame.PlayersInGame)
    table.clear(pendingKills)
    table.clear(deathLocks)
    MainGame.RoundStats = nil
    MainGame.CurrentMap = nil
    Players.CharacterAutoLoads = true
    ReplicatedStorage:WaitForChild("Timer").Value = 0
    local roundId = MainGame.RoundId
    for _, player in ipairs(Players:GetPlayers()) do
        player:SetAttribute("InRound", false)
        player:SetAttribute("CurrentRoundParticipant", false)
        player:SetAttribute("CurrentRoundKills", 0)
        player:SetAttribute("CurrentRoundMode", nil)
        if respawn then task.spawn(RespawnAtLobby, player, roundId) end
    end
end

local function wantsRound(player)
    if player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return false end
    if player:GetAttribute("TutorialTravelPending")==true or player:GetAttribute("TutorialActive")==true then return false end
    local stats = player:FindFirstChild("leaderstats")
    local settings = stats and stats:FindFirstChild("Settings")
    local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
    return lobbyMode and lobbyMode.Value == false
end
local function eligible(player)
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    return wantsRound(player) and humanoid and humanoid.Health > 0
end

local function runGame(map, modeId: string?)
    MainGame.RoundId += 1
    table.clear(MainGame.PlayersInGame)
    table.clear(pendingKills)
    table.clear(deathLocks)
    MainGame.RoundStats = nil
    eliminationOrder = {}
    MainGame.LobbyModeLock = true
    MainGame.CurrentMap = map
    MainGame.CurrentMode = GameModes.Get(modeId or GameModes.FFA.Id) or GameModes.FFA

    for _, player in pairs(Players:GetPlayers()) do
        player:SetAttribute("LastRoundKills", 0)
        player:SetAttribute("LastRoundPlacement", 0)
        player:SetAttribute("LastRoundOpponents", 0)
        local modeName = "FFA"
        if MainGame.CurrentMode then
            if MainGame.CurrentMode.Id == "BattleRoyale" then
                modeName = "BR"
            elseif MainGame.CurrentMode.Id == "FFA" then
                modeName = "FFA"
            else
                modeName = MainGame.CurrentMode.Id or "FFA"
            end
        end
        player:SetAttribute("LastRoundGameMode", modeName)
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

    if not SpawnMapModule.Spawn(map) then
        warn("MainGame: unable to load round map:", map)
        RoundHandlerModule.ChangeStatus("MAP COULD NOT LOAD")
        MainGame.WipeTools()
        MainGame.GameActive = false
        GameActiveBoolean.Value = false
        MainGame.LobbyModeLock = false
        MainGame.CurrentMap = nil
        table.clear(MainGame.PlayersInGame)
        for _, player in ipairs(Players:GetPlayers()) do
            player:SetAttribute("InRound", false)
            player:SetAttribute("CurrentRoundParticipant", false)
        end
        return
    end
    task.wait(2)

    local roundPlayers = {}
    for _, player in ipairs(Players:GetPlayers()) do if wantsRound(player) then table.insert(roundPlayers, player) end end
    local placedPlayers, placedCharacters = SpawnMapModule.PlacePlayers(map, roundPlayers)
    if placedPlayers ~= #roundPlayers then
        warn(("MainGame: placed %d/%d round players"):format(placedPlayers, #roundPlayers))
        for _, player in ipairs(roundPlayers) do
            if wantsRound(player) and (not placedCharacters or placedCharacters[player.UserId] ~= player.Character) then
                RoundHandlerModule.ChangeStatus("PLAYER COULD NOT REACH MAP")
                return
            end
        end
    end
    for _, player in ipairs(roundPlayers) do
        if placedCharacters and placedCharacters[player.UserId] == player.Character and eligible(player) then
            MainGame.PlayersInGame[player.UserId] = true
            player:SetAttribute("CurrentRoundParticipant", true)
            player:SetAttribute("InRound", true)
        end
    end
    if CountPlayersInGame() < RoundHandlerModule.MinimumPlayers then
        RoundHandlerModule.ChangeStatus("NOT ENOUGH PLAYERS TO START")
        return
    end
    -- Players reach the map before the 3-2-1 countdown. Combat/music starts
    -- only after that countdown and a final membership/health check.
    RoundCountdownRemote:FireAllClients("fight")
    task.wait(3.5)
    local remainingPlayers = {}
    for _, player in ipairs(roundPlayers) do if wantsRound(player) then table.insert(remainingPlayers, player) end end
    local verifiedCount, verifiedCharacters = SpawnMapModule.VerifyPlayers(map, remainingPlayers)
    if verifiedCount ~= #remainingPlayers then
        RoundHandlerModule.ChangeStatus("PLAYER COULD NOT REACH MAP")
        return
    end
    for _, player in ipairs(roundPlayers) do
        if not eligible(player) or verifiedCharacters[player.UserId] ~= player.Character then
            MainGame.PlayersInGame[player.UserId] = nil
            player:SetAttribute("InRound", false)
            player:SetAttribute("CurrentRoundParticipant", false)
        end
    end
    if CountPlayersInGame() < RoundHandlerModule.MinimumPlayers then
        RoundHandlerModule.ChangeStatus("NOT ENOUGH PLAYERS TO START")
        return
    end
    InitRoundStats()
    -- Respawns are controlled by the round so FFA cannot also receive
    -- Roblox's automatic respawn before the delayed round respawn.
    Players.CharacterAutoLoads = false

    -- Apply to every participant before unfreezing/enabling combat. No yields
    -- separate these steps, so there is no unprotected opening damage window.
    ProtectRoundStart()
    SpawnMapModule.ReleasePlacements()
    MainGame.GameActive = true
    GameActiveBoolean.Value = true
    
    if MainGame.CurrentMode.ZoneRequired then
        local roundId = MainGame.RoundId
        if not ZoneHandler.SpawnZone() then error("Battle Royale zone could not load") end
        task.spawn(function()
            if MainGame.RoundId ~= roundId or not MainGame.GameActive then return end
            task.wait(1)
            if MainGame.RoundId == roundId and MainGame.GameActive then ZoneHandler.StartZone() end
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

	MainGame.GameActive = false
	GameActiveBoolean.Value = false
    FinalizeRoundStats()
    local gameResults, playerResults = BuildRoundResults()

    ApplyRoundRewards()

    if gameResults and playerResults then
        task.wait(1.9) 
        GetRoundResultsRemote:FireAllClients(gameResults, playerResults)
    end

    task.wait(0.5)
    HealAllPlayers()
    MainGame.WipeTools()

end

function MainGame.StartGame(map, modeId: string?)
    local ok, err = xpcall(function() runGame(map, modeId) end, debug.traceback)
    if not ok then
        warn("MainGame: round aborted:\n" .. tostring(err))
        RoundHandlerModule.ChangeStatus("ROUND COULD NOT CONTINUE")
    end
    -- Includes failed map loads, insufficient players, normal completion and
    -- runtime errors, so one bad round cannot terminate the game loop.
    MainGame.CleanupRound(true)
    return ok
end

-- NOTE: The "ReceiveInfoRemote" listener block was removed. 
-- Clients now get data via Attributes and leaderstats.

return MainGame
