local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local QuestsRemotesFolder = RemotesFolder:WaitForChild("Quests")
local UpdateQuestsRemote = QuestsRemotesFolder:WaitForChild("RequestQuests")
local ClaimQuestRemote = QuestsRemotesFolder:WaitForChild("ClaimQuestReward")
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

local QUESTS_DATASTORE = DataStoreService:GetDataStore("DailyQuestsProgress_v1_TESTING")

local DAILY_QUEST_POOL = {
    {
        Id = "WIN_2_ROUNDS",
        Title = "Win 2 Rounds",
        Target = 2,
        RewardGold = 150,
        Type = "WINS",
        ProgressLabel = "WINS",
    },
    {
        Id = "PLAY_20_MIN",
        Title = "Play 20 Minutes",
        Target = 20 * 60,
        RewardGold = 200,
        Type = "PLAY_TIME_SECONDS",
        ProgressLabel = "MIN",
    },
    {
        Id = "KILL_5_PLAYERS",
        Title = "Kill 5 Players",
        Target = 5,
        RewardGold = 200,
        Type = "KILLS",
        ProgressLabel = "KILLS",
    },
    {
        Id = "PLAY_3_ROUNDS",
        Title = "Play 3 Rounds",
        Target = 3,
        RewardGold = 175,
        Type = "ROUNDS_PLAYED",
        ProgressLabel = "ROUNDS",
    },
    {
        Id = "TOP3_2_TIMES",
        Title = "Finish Top 3 Twice",
        Target = 2,
        RewardGold = 225,
        Type = "TOP3_FINISHES",
        ProgressLabel = "TOP 3",
    },
    {
        Id = "EARN_500_MATCH_GOLD",
        Title = "Earn 500 Match Gold",
        Target = 500,
        RewardGold = 250,
        Type = "MATCH_GOLD_EARNED",
        ProgressLabel = "GOLD",
    },
    {
        Id = "CLAIM_1_DAILY_REWARD",
        Title = "Claim 1 Daily Reward",
        Target = 1,
        RewardGold = 150,
        Type = "DAILY_REWARD_CLAIMS",
        ProgressLabel = "CLAIMS",
    },
}

local ACTIVE_QUESTS_PER_DAY = 3
local PLAYTIME_TICK_SECONDS = 5
local AUTOSAVE_SECONDS = 120
local playerQuestState: {[number]: any} = {}
local pendingSaveJobs: {[number]: boolean} = {}

local Quests = {}

local function getUtcDayKey(nowTimestamp: number?): string
    local now = nowTimestamp or os.time()
    local dateTable = os.date("!*t", now)
    return string.format("%04d-%02d-%02d", dateTable.year, dateTable.month, dateTable.day)
end

local function getDaySeed(dayKey: string): number
    local numeric = tonumber(dayKey:gsub("-", "")) or 1
    return (numeric % 2147483647)
end

local function deterministicShuffle(input, rng)
    local output = table.clone(input)
    for i = #output, 2, -1 do
        local j = rng:NextInteger(1, i)
        output[i], output[j] = output[j], output[i]
    end
    return output
end

local function getGlobalDailyQuestDefinitions(dayKey: string)
    local rng = Random.new(getDaySeed(dayKey))
    local shuffled = deterministicShuffle(DAILY_QUEST_POOL, rng)

    local selected = {}
    for i = 1, math.min(ACTIVE_QUESTS_PER_DAY, #shuffled) do
        table.insert(selected, shuffled[i])
    end
    return selected
end

local function deepCopyStateTable(tbl)
    if type(tbl) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local inner = {}
            for ik, iv in pairs(v) do
                inner[ik] = iv
            end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local function ensurePlayerStateForToday(player: Player)
    local userId = player.UserId
    local dayKey = getUtcDayKey()
    local state = playerQuestState[userId]
    if not state then
        state = {
            DayKey = dayKey,
            Progress = {},
            Claimed = {},
            Dirty = true,
        }
        playerQuestState[userId] = state
    end

    if state.DayKey ~= dayKey then
        state.DayKey = dayKey
        state.Progress = {}
        state.Claimed = {}
        state.Dirty = true
    end

    local dailyDefinitions = getGlobalDailyQuestDefinitions(state.DayKey)
    for _, quest in ipairs(dailyDefinitions) do
        if state.Progress[quest.Id] == nil then
            state.Progress[quest.Id] = 0
        end
        if state.Claimed[quest.Id] == nil then
            state.Claimed[quest.Id] = false
        end
    end

    return state, dailyDefinitions
end

local function getLeaderstatsCash(player: Player)
    local leaderstats = player:FindFirstChild("leaderstats")
    return leaderstats and leaderstats:FindFirstChild("Cash")
end

local function buildQuestPayload(player: Player)
    local state, dailyDefinitions = ensurePlayerStateForToday(player)
    local payload = {
        DayKey = state.DayKey,
        ServerTime = os.time(),
        Quests = {},
    }

    for _, quest in ipairs(dailyDefinitions) do
        local progress = tonumber(state.Progress[quest.Id]) or 0
        local target = tonumber(quest.Target) or 1
        local clampedProgress = math.clamp(progress, 0, target)
        local completed = clampedProgress >= target
        local claimed = state.Claimed[quest.Id] == true
        local status
        if claimed then
            status = "CLAIMED"
        elseif completed then
            status = "CLAIM"
        else
            local shownProgress = clampedProgress
            local shownTarget = target
            if quest.Type == "PLAY_TIME_SECONDS" then
                shownProgress = math.floor(clampedProgress / 60)
                shownTarget = math.floor(target / 60)
            end
            status = string.format("%d / %d %s", shownProgress, shownTarget, quest.ProgressLabel)
        end

        table.insert(payload.Quests, {
            Id = quest.Id,
            Title = quest.Title,
            RewardGold = quest.RewardGold,
            Progress = clampedProgress,
            Target = target,
            Claimed = claimed,
            Completed = completed,
            Status = status,
        })
    end

    return payload
end

local function pushQuestUpdate(player: Player)
    if not player or not player.Parent then
        return
    end
    UpdateQuestsRemote:FireClient(player, buildQuestPayload(player))
end

local function loadPlayerState(player: Player)
    local state = {
        DayKey = getUtcDayKey(),
        Progress = {},
        Claimed = {},
        Dirty = false,
    }

    local ok, data = pcall(function()
        return QUESTS_DATASTORE:GetAsync(tostring(player.UserId))
    end)

    if ok and type(data) == "table" then
        state.DayKey = type(data.DayKey) == "string" and data.DayKey or state.DayKey
        state.Progress = deepCopyStateTable(data.Progress)
        state.Claimed = deepCopyStateTable(data.Claimed)
    end

    playerQuestState[player.UserId] = state
    ensurePlayerStateForToday(player)
end

local function savePlayerState(player: Player, force: boolean?)
    local state = playerQuestState[player.UserId]
    if not state then
        return
    end

    if not state.Dirty and not force then
        return
    end

    state.Dirty = false
    local snapshot = {
        DayKey = state.DayKey,
        Progress = deepCopyStateTable(state.Progress),
        Claimed = deepCopyStateTable(state.Claimed),
        UpdatedAt = os.time(),
    }

    local ok, err = pcall(function()
        QUESTS_DATASTORE:UpdateAsync(tostring(player.UserId), function()
            return snapshot
        end)
    end)

    if not ok then
        state.Dirty = true
        warn("[Quests] Failed to save quests for", player.Name, err)
    end
end

local function queueSave(player: Player, delaySeconds: number?)
    if not player or not player.Parent then
        return
    end

    local userId = player.UserId
    if pendingSaveJobs[userId] then
        return
    end

    pendingSaveJobs[userId] = true
    task.delay(delaySeconds or 5, function()
        pendingSaveJobs[userId] = nil
        if player and player.Parent then
            savePlayerState(player)
        end
    end)
end

local function incrementQuestProgress(player: Player, questType: string, amount: number)
    if not player or not player.Parent then
        return
    end
    if type(amount) ~= "number" or amount <= 0 then
        return
    end

    local state, dailyDefinitions = ensurePlayerStateForToday(player)
    local changed = false

    for _, quest in ipairs(dailyDefinitions) do
        if quest.Type == questType then
            local current = tonumber(state.Progress[quest.Id]) or 0
            local target = tonumber(quest.Target) or current
            local nextValue = math.min(target, current + amount)
            if nextValue ~= current then
                state.Progress[quest.Id] = nextValue
                changed = true
            end
        end
    end

    if changed then
        state.Dirty = true
        pushQuestUpdate(player)
        if questType == "PLAY_TIME_SECONDS" then
            queueSave(player, 30)
        else
            queueSave(player, 3)
        end
    end
end

function Quests.AddProgress(player: Player, questType: string, amount: number)
    incrementQuestProgress(player, questType, amount)
end

local function claimQuest(player: Player, questId: string)
    if type(questId) ~= "string" then
        return false, "Invalid quest"
    end

    local state, dailyDefinitions = ensurePlayerStateForToday(player)
    local questDef = nil
    for _, quest in ipairs(dailyDefinitions) do
        if quest.Id == questId then
            questDef = quest
            break
        end
    end

    if not questDef then
        return false, "Quest unavailable"
    end

    if state.Claimed[questId] == true then
        return false, "Already claimed"
    end

    local progress = tonumber(state.Progress[questId]) or 0
    if progress < (questDef.Target or 0) then
        return false, "Quest not complete"
    end

    local cash = getLeaderstatsCash(player)
    if not cash then
        return false, "Cash stat missing"
    end

    cash.Value += questDef.RewardGold
    state.Claimed[questId] = true
    state.Dirty = true
    return true
end

local questRemoteCooldowns: {[number]: number} = {}
local QUEST_REMOTE_COOLDOWN = 2.0

UpdateQuestsRemote.OnServerEvent:Connect(function(player: Player)
    local now = os.clock()
    if questRemoteCooldowns[player.UserId] and (now - questRemoteCooldowns[player.UserId]) < QUEST_REMOTE_COOLDOWN then return end
    questRemoteCooldowns[player.UserId] = now
    pushQuestUpdate(player)
end)

ClaimQuestRemote.OnServerEvent:Connect(function(player: Player, questId: string)
    if type(questId) ~= "string" then return end
    local now = os.clock()
    if questRemoteCooldowns[player.UserId] and (now - questRemoteCooldowns[player.UserId]) < QUEST_REMOTE_COOLDOWN then return end
    questRemoteCooldowns[player.UserId] = now
    local ok, msg = claimQuest(player, questId)
    if ok then
        savePlayerState(player, true)
        NotificationHandler.SendNotification(player, "Quest reward claimed!", 3, "Success")
    else
        NotificationHandler.SendNotification(player, msg or "Could not claim quest", 3, "Error")
    end
    pushQuestUpdate(player)
end)

Players.PlayerAdded:Connect(function(player)
    loadPlayerState(player)
    pushQuestUpdate(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    loadPlayerState(player)
    pushQuestUpdate(player)
end

Players.PlayerRemoving:Connect(function(player)
    savePlayerState(player, true)
    pendingSaveJobs[player.UserId] = nil
    playerQuestState[player.UserId] = nil
    questRemoteCooldowns[player.UserId] = nil
end)

task.spawn(function()
    while true do
        task.wait(PLAYTIME_TICK_SECONDS)
        for _, player in ipairs(Players:GetPlayers()) do
            incrementQuestProgress(player, "PLAY_TIME_SECONDS", PLAYTIME_TICK_SECONDS)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(AUTOSAVE_SECONDS)
        for _, player in ipairs(Players:GetPlayers()) do
            savePlayerState(player)
        end
    end
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        savePlayerState(player)
    end
end)
return Quests