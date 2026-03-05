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
local levelRequirementFrame = nil
local noPlayersFrame = nil
local MIN_TRADE_LEVEL = 10

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

local function ClearPlayerEntries()
    for userId, entry in pairs(playerEntries) do
        if entry.connections then
            for _, conn in ipairs(entry.connections) do
                conn:Disconnect()
            end
        end
        if entry.frame then
            entry.frame:Destroy()
        end
        playerEntries[userId] = nil
    end
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

    if level < MIN_TRADE_LEVEL then
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
    if not hasRequiredTradeLevel() then
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
    template.SendTrade.MouseButton1Click:Connect(function()
        TradeRemote:FireServer("SEND_REQUEST", plr.UserId)
    end)
end

local function RemovePlayer(player: Player)
    local entry = playerEntries[player.UserId]
    if entry then
        if entry.connections then
            for _, conn in ipairs(entry.connections) do
                conn:Disconnect()
            end
        end
        if entry.frame then
            entry.frame:Destroy()
        end
        playerEntries[player.UserId] = nil
    end
end

local function RefreshPlayerList()
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
            if entry.conn then
                entry.conn:Disconnect()
            end
            if entry.frame then
                entry.frame:Destroy()
            end
            playerEntries[userId] = nil
        elseif entry.frame then
            updateEntryState(entry.frame, player)
        end
    end
end

local function ApplyTradeLevelGate()
    RefreshPlayerList()
end

local function StartAutoRefresh()
    task.spawn(function()
        while true do
            task.wait(30)
            RefreshPlayerList()
        end
    end)
end











Players.PlayerAdded:Connect(function(player)
	AddPlayer(player)
	updateNoPlayersMessage()
end)

Players.PlayerRemoving:Connect(function(player)
	RemovePlayer(player)
	updateNoPlayersMessage()
end)

local localLeaderstats = plr:WaitForChild("leaderstats")
local localXP = localLeaderstats:WaitForChild("XP")
localXP:GetPropertyChangedSignal("Value"):Connect(function()
    ApplyTradeLevelGate()
end)

ApplyTradeLevelGate()
StartAutoRefresh()

ExitButton.MouseButton1Click:Connect(function()
    local Lighting = game:GetService("Lighting")
    Lighting.Blur.Enabled = false
    TradePlayerList.Visible = false
end)

return {}