-- Services
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local CalculateLevelModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))

-- remotes
local TradeRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
local TradeRemote = TradeRemotesFolder:WaitForChild("TradeUpdate")

-- UI
local PlayerGui = plr:WaitForChild("PlayerGui")
local MainGUI = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGUI:WaitForChild("Frames")
local TradePlayerList = FramesFolder:WaitForChild("TradeRequesting")
local TradePlayerListContainer = TradePlayerList:WaitForChild("Container")
local ExitButton = TradePlayerList:WaitForChild("Exit")

-- UI Templates
local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local TradeTemplatesFolder = UITemplates:WaitForChild("TradeRequestTemplates")
local PlayerTemplate = TradeTemplatesFolder:WaitForChild("PlayerTemplate")
local SadLevelRequirementTemplate = TradeTemplatesFolder:WaitForChild("LevelRequirement")
local NoPlayersInGameTemplate = TradeTemplatesFolder:WaitForChild("NoPlayers")

local playerEntries = {}
local activeCooldowns = {}
local levelRequirementFrame = nil
local noPlayersFrame = nil
local MIN_TRADE_LEVEL = 10
local SEND_COOLDOWN_TIME = 15
local alive = true
local connections, cooldownTasks = {}, {}
local refreshTask

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function getLocalLevel()
    local leaderstats = plr:FindFirstChild("leaderstats")
    local xpValue = leaderstats and leaderstats:FindFirstChild("XP")
    local xp = xpValue and xpValue.Value or 0
    local level = CalculateLevelModule.GetLevel(xp)
    return level
end

local function hasRequiredTradeLevel()
    return getLocalLevel() >= MIN_TRADE_LEVEL
end

local function showLevelRequirementOnly()
    if not levelRequirementFrame then
        levelRequirementFrame = SadLevelRequirementTemplate:Clone()
        levelRequirementFrame.Name = "LevelRequirementOnly"
    end
    levelRequirementFrame.Parent = TradePlayerListContainer
end

local function hideLevelRequirementOnly()
    if levelRequirementFrame then
        levelRequirementFrame.Parent = nil
    end
end

local function getOtherPlayerCount()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr then
            count += 1
        end
    end
    return count
end

local function updateNoPlayersMessage()
    if not hasRequiredTradeLevel() then
        if noPlayersFrame then
            noPlayersFrame.Parent = nil
        end
        return
    end

    if getOtherPlayerCount() == 0 then
        if not noPlayersFrame then
            noPlayersFrame = NoPlayersInGameTemplate:Clone()
            noPlayersFrame.Name = "NoPlayersMessage"
        end
        noPlayersFrame.Parent = TradePlayerListContainer
    else
        if noPlayersFrame then
            noPlayersFrame.Parent = nil
        end
    end
end

local function RemoveEntry(userId)
    local entry = playerEntries[userId]
    if not entry then return end
    playerEntries[userId] = nil
    for _, conn in ipairs(entry.connections or {}) do conn:Disconnect() end
    if entry.frame then entry.frame:Destroy() end
end

local function ClearPlayerEntries()
    for userId in pairs(playerEntries) do RemoveEntry(userId) end
end

local function canReceiveTrades(player: Player)
    local leaderstats = player:FindFirstChild("leaderstats")
    local settings = leaderstats and leaderstats:FindFirstChild("Settings")
    local tradesSetting = settings and settings:FindFirstChild("Trades")
    if tradesSetting == nil then
        return true
    end
    return tradesSetting.Value == true
end

local function getPlayerLevel(player: Player)
    local leaderstats = player:FindFirstChild("leaderstats")
    local xpValue = leaderstats and leaderstats:FindFirstChild("XP")
    local xp = xpValue and xpValue.Value or 0
    return CalculateLevelModule.GetLevel(xp)
end

local function updateEntryState(frame: Frame, player: Player)
    local level = getPlayerLevel(player)
    
    local cooldownEnd = activeCooldowns[player.UserId] or 0
    local inCooldown = os.clock() < cooldownEnd

    if inCooldown then
        frame.SentOrNot.Visible = true
        frame.SendTrade.Header.Text = "SENT"
        frame.SendTrade.Interactable = false
    elseif level < MIN_TRADE_LEVEL then
        frame.SentOrNot.Visible = true
        frame.SendTrade.Header.Text = "UNDER LV. 10"
        frame.SendTrade.Interactable = false
    elseif not canReceiveTrades(player) then
        frame.SentOrNot.Visible = true
        frame.SendTrade.Header.Text = "TRADES OFF"
        frame.SendTrade.Interactable = false
    else
        frame.SentOrNot.Visible = false
        frame.SendTrade.Header.Text = "SEND TRADE"
        frame.SendTrade.Interactable = true
    end
end

local function AddPlayer(plr : Player)
    if not alive or not hasRequiredTradeLevel() then
        return
    end

    local existing = playerEntries[plr.UserId]
    if existing then
        return
    end

    local template = PlayerTemplate:Clone()

    local PlayerImg = template:WaitForChild("PlayerImage")
    local PlayerName = template:WaitForChild("Username")
    updateEntryState(template, plr)

    PlayerImg.Image = "rbxthumb://type=AvatarHeadShot&id="..plr.UserId.."&w=420&h=420"
    PlayerName.Text = plr.Name
    template.Name = tostring(plr.UserId)
    template.Parent = TradePlayerListContainer
    local connections = {}
    local leaderstats = plr:FindFirstChild("leaderstats")
    local settings = leaderstats and leaderstats:FindFirstChild("Settings")
    local tradesSetting = settings and settings:FindFirstChild("Trades")
    if tradesSetting then
        table.insert(connections, tradesSetting:GetPropertyChangedSignal("Value"):Connect(function()
            updateEntryState(template, plr)
        end))
    end

    local xpValue = leaderstats and leaderstats:FindFirstChild("XP")
    if xpValue then
        table.insert(connections, xpValue:GetPropertyChangedSignal("Value"):Connect(function()
            updateEntryState(template, plr)
        end))
    end

    playerEntries[plr.UserId] = {
        frame = template,
        connections = connections,
    }

    if plr == Players.LocalPlayer then
        template.Visible = false
    end
    table.insert(connections, template.SendTrade.MouseButton1Click:Connect(function()
        TradeRemote:FireServer("SEND_REQUEST", plr.UserId)
    end))
end

local function RemovePlayer(player: Player)
    RemoveEntry(player.UserId)
    activeCooldowns[player.UserId] = nil
    if cooldownTasks[player.UserId] then
        task.cancel(cooldownTasks[player.UserId])
        cooldownTasks[player.UserId] = nil
    end
end

local function RefreshPlayerList()
    if not alive then return end
    if not hasRequiredTradeLevel() then
        ClearPlayerEntries()
        showLevelRequirementOnly()
        return
    end

    hideLevelRequirementOnly()
    updateNoPlayersMessage()

    for _, player in ipairs(Players:GetPlayers()) do
        AddPlayer(player)
    end
    for userId, entry in pairs(playerEntries) do
        local player = Players:GetPlayerByUserId(userId)
        if not player then
            RemoveEntry(userId)
            activeCooldowns[userId] = nil
        elseif entry.frame then
            updateEntryState(entry.frame, player)
        end
    end
end

local function ApplyTradeLevelGate()
    RefreshPlayerList()
end

local function StartAutoRefresh()
    refreshTask = task.spawn(function()
        while alive do
            task.wait(30)
            RefreshPlayerList()
        end
    end)
end

local function destroy()
    if not alive then return end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    if refreshTask then
        if refreshTask ~= coroutine.running() then task.cancel(refreshTask) end
        refreshTask = nil
    end
    for _, thread in pairs(cooldownTasks) do task.cancel(thread) end
    table.clear(cooldownTasks)
    table.clear(activeCooldowns)
    ClearPlayerEntries()
    if levelRequirementFrame then levelRequirementFrame:Destroy(); levelRequirementFrame = nil end
    if noPlayersFrame then noPlayersFrame:Destroy(); noPlayersFrame = nil end
end
connect(TradePlayerList.Destroying, destroy)

connect(Players.PlayerAdded, function(player)
    AddPlayer(player)
    updateNoPlayersMessage()
end)

connect(Players.PlayerRemoving, function(player)
    RemovePlayer(player)
    updateNoPlayersMessage()
end)

local localLeaderstats = plr:WaitForChild("leaderstats")
local localXP = localLeaderstats:WaitForChild("XP")
if not alive then return {Destroy = destroy} end
connect(localXP:GetPropertyChangedSignal("Value"), function()
    ApplyTradeLevelGate()
end)

ApplyTradeLevelGate()
StartAutoRefresh()

connect(TradeRemote.OnClientEvent, function(eventName, data)
    if eventName == "ACTION_RESULT" and data.action == "SEND_REQUEST" then
        if data.success and data.extra and data.extra.targetUserId then
            local targetId = data.extra.targetUserId
            activeCooldowns[targetId] = os.clock() + SEND_COOLDOWN_TIME
            
            local p = Players:GetPlayerByUserId(targetId)
            local entry = playerEntries[targetId]
            if p and entry and entry.frame then
                updateEntryState(entry.frame, p)
            end
            
            if cooldownTasks[targetId] then task.cancel(cooldownTasks[targetId]) end
            cooldownTasks[targetId] = task.delay(SEND_COOLDOWN_TIME, function()
                cooldownTasks[targetId] = nil
                if not alive then return end
                activeCooldowns[targetId] = nil
                local p2 = Players:GetPlayerByUserId(targetId)
                local entry2 = playerEntries[targetId]
                if p2 and entry2 and entry2.frame then
                    updateEntryState(entry2.frame, p2)
                end
            end)
        end
    end
end)

connect(ExitButton.MouseButton1Click, function()
    local Lighting = game:GetService("Lighting")
    Lighting.Blur.Enabled = false
    TradePlayerList.Visible = false
end)

return {Destroy = destroy}
