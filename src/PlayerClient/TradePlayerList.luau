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

local playerEntries = {}
local levelRequirementFrame = nil
local MIN_TRADE_LEVEL = 20

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

local function ClearPlayerEntries()
    for userId, entry in pairs(playerEntries) do
        if entry.conn then
            entry.conn:Disconnect()
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


local function updateEntryState(frame: Frame, player: Player)
    if canReceiveTrades(player) then
        frame.SentOrNot.Visible = false
        frame.SendTrade.Interactable = true
    else
        frame.SentOrNot.Visible = true
        frame.SendTrade.Header.Text = "TRADES OFF"
        frame.SendTrade.Interactable = false
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
    local tradesConn = nil
    local leaderstats = plr:FindFirstChild("leaderstats")
    local settings = leaderstats and leaderstats:FindFirstChild("Settings")
    local tradesSetting = settings and settings:FindFirstChild("Trades")
    if tradesSetting then
        tradesConn = tradesSetting:GetPropertyChangedSignal("Value"):Connect(function()
            updateEntryState(template, plr)
        end)
    end

    playerEntries[plr.UserId] = {
        frame = template,
        conn = tradesConn,
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
        if entry.conn then
            entry.conn:Disconnect()
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
end)

Players.PlayerRemoving:Connect(function(player)
	RemovePlayer(player)
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