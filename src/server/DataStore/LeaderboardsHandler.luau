local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local LeaderboardsRemotesFolder = RemotesFolder:WaitForChild("Leaderboards")
local RequestLeaderboardsRemote = LeaderboardsRemotesFolder:WaitForChild("RequestLeaderboards")

local Leaderboards = {}

local CalculateLevelModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))
-- Require ProfileManager to get the 100% accurate save data directly from the source
local ProfileManager = require(script.Parent:WaitForChild("ProfileManager"))

local LevelsStore = DataStoreService:GetOrderedDataStore("Leaderboard_Levels_Datastore1.0")
local KillsStore = DataStoreService:GetOrderedDataStore("Leaderboard_Kills_Datastore1.0")
local GoldStore = DataStoreService:GetOrderedDataStore("Leaderboard_Gold_Datastore1.0")

local NAME_CACHE = {}
local UPDATE_COOLDOWN_SECONDS = 60
local DEFAULT_TOP_COUNT = 50

-- Store the latest fetched leaderboards to prevent throttling and instant-load for clients
local CachedLeaderboards = {
    Levels = {},
    Kills = {},
    Gold = {}
}

local function getPlayerName(userId: number)
    if NAME_CACHE[userId] then return NAME_CACHE[userId] end
    
    local success, name = pcall(function() 
        return Players:GetNameFromUserIdAsync(userId) 
    end)
    
    if success and name then
        NAME_CACHE[userId] = name
        return name
    end

    return "Unknown"
end

local function updateOrderedStores(player: Player)
    local userId = player.UserId

    -- Fetch exact data directly from the save profile, ignoring UI delays
    local profileData = ProfileManager.GetProfileData(player)
    local kills, cash, xp = 0, 0, 0
    
    if profileData then
        kills = profileData.Kills or 0
        cash = profileData.Cash or 0
        xp = profileData.XP or 0
    else
        -- Fallback to leaderstats if profile isn't fully loaded yet
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            kills = leaderstats:FindFirstChild("Kills") and leaderstats.Kills.Value or 0
            cash = leaderstats:FindFirstChild("Cash") and leaderstats.Cash.Value or 0
            xp = leaderstats:FindFirstChild("XP") and leaderstats.XP.Value or 0
        else
            return -- No data available at all yet
        end
    end

    local level = CalculateLevelModule.GetLevel(xp)

    -- Push to OrderedDataStores safely
    pcall(function() KillsStore:SetAsync(userId, kills) end)
    pcall(function() GoldStore:SetAsync(userId, cash) end)
    pcall(function() LevelsStore:SetAsync(userId, level) end)
end

local function getLeaderboardData(orderedStore: OrderedDataStore, count: number)
    local success, pages = pcall(function()
        return orderedStore:GetSortedAsync(false, count)
    end)
    if not success or not pages then return {} end

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

function Leaderboards.Broadcast()
    RequestLeaderboardsRemote:FireAllClients(CachedLeaderboards)
end

-- Allow other modules to force a fresh write
function Leaderboards.UpdatePlayer(player: Player)
    task.spawn(function()
        updateOrderedStores(player)
    end)
end

-- Save right as they leave to capture final stats
Players.PlayerRemoving:Connect(function(player)
    updateOrderedStores(player)
end)

-- When a client loads in or hits refresh, instantly give them the cache
RequestLeaderboardsRemote.OnServerEvent:Connect(function(player)
    RequestLeaderboardsRemote:FireClient(player, CachedLeaderboards)
end)

task.spawn(function()
    CachedLeaderboards = {
        Levels = getLeaderboardData(LevelsStore, DEFAULT_TOP_COUNT),
        Kills = getLeaderboardData(KillsStore, DEFAULT_TOP_COUNT),
        Gold = getLeaderboardData(GoldStore, DEFAULT_TOP_COUNT),
    }

    while true do
        for _, player in ipairs(Players:GetPlayers()) do
            task.spawn(function()
                updateOrderedStores(player)
            end)
            task.wait(0.2) 
        end

        task.wait(5)

        CachedLeaderboards = {
            Levels = getLeaderboardData(LevelsStore, DEFAULT_TOP_COUNT),
            Kills = getLeaderboardData(KillsStore, DEFAULT_TOP_COUNT),
            Gold = getLeaderboardData(GoldStore, DEFAULT_TOP_COUNT),
        }

        Leaderboards.Broadcast()

        task.wait(UPDATE_COOLDOWN_SECONDS - 5)
    end
end)

return Leaderboards