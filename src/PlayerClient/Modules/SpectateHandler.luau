local SpectateHandler = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Modules
local TimeToMinutes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))

-- Local Player & Camera
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Variables & State
local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")
local spectateConnection = nil
local spectateIndex = 1
local currentSpectateTarget = nil

-- UIS
local PlayerGui = player:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("Main")
local SpectateFrame = MainGui:WaitForChild("SpectateFrame")
local BottomFrame = SpectateFrame:WaitForChild("Bottom")
local MatchStats = SpectateFrame:WaitForChild("MatchStats")
local ExitSpectateButton = BottomFrame:WaitForChild("ExitFrame"):WaitForChild("ExitSpectateButton")

local CurrentlySpectatingText = SpectateFrame:WaitForChild("CurrentlySpectatingUser")

local ArrowLeftButton = BottomFrame:WaitForChild("ArrowLeft")
local ArrowRightButton = BottomFrame:WaitForChild("ArrowRight")
local MiddleFrame = BottomFrame:WaitForChild("MiddleFrame")
local SpectatingUserKillsText = MiddleFrame:WaitForChild("Kills"):WaitForChild("KillsText")
local SpectatingUserKnifeCurrentlyUsingImage = MiddleFrame:WaitForChild("Inventory"):WaitForChild("KnifeEquippedFrame"):WaitForChild("Slot"):WaitForChild("KnifeImage")
local CurrentlySpectatingText2 = BottomFrame:WaitForChild("CurrentlySpectating")

local MatchStatText = MatchStats:WaitForChild("StatsText")

-- Your custom UI additions
local ButtonVisibleWhenGameActive = MainGui:WaitForChild("Top"):WaitForChild("Buttons"):WaitForChild("Spectate")
local RandomTextLabel = MainGui:WaitForChild("SystemTexts"):WaitForChild("Status")
local RandomFrame = MainGui:WaitForChild("Bottom")

-- Remotes
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local SpectatingRemotesFolder = RemotesFolder:WaitForChild("Spectating")
local ReceiveInfoRemote = SpectatingRemotesFolder:WaitForChild("Receive")

-- Timer Source
local RoundStatusValue = ReplicatedStorage:WaitForChild("Timer")

--=============================
-- Game Active / Button Visibility Logic
--=============================
-- FIXED: Use GameActiveBoolean to control the button, not the Timer value!
GameActiveBoolean.Changed:Connect(function(isActive)
    ButtonVisibleWhenGameActive.Visible = isActive
    
    -- Force stop spectating if the game ends
    if not isActive and SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    end
end)

-- Set initial state for the button
ButtonVisibleWhenGameActive.Visible = GameActiveBoolean.Value

--=============================
-- Helper Functions
--=============================

local function GetAlivePlayers()
    local alive = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p:GetAttribute("InRound") == true then
            table.insert(alive, p)
        end
    end
    return alive
end

local function UpdateMatchStatsText(aliveCount, timeLeftStr)
    MatchStatText.Text = string.format(
        '<font color="#ffffff">Players Alive: </font><font color="#6ed378">%d</font><font color="#ffffff"> / Time Left: </font><font color="#ffe941">%s</font>',
        aliveCount,
        timeLeftStr
    )
end

local function SetSpectateTarget(index)
    local alivePlayers = GetAlivePlayers()
    
    if #alivePlayers == 0 then
        SpectateHandler.StopSpectating()
        return
    end

    if index > #alivePlayers then
        index = 1
    elseif index < 1 then
        index = #alivePlayers
    end

    spectateIndex = index
    currentSpectateTarget = alivePlayers[spectateIndex]

    if currentSpectateTarget and currentSpectateTarget.Character then
        local humanoid = currentSpectateTarget.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            camera.CameraSubject = humanoid
            CurrentlySpectatingText.Text = currentSpectateTarget.DisplayName
            CurrentlySpectatingText2.Text = currentSpectateTarget.DisplayName
            
            ReceiveInfoRemote:FireServer("RequestInfo", currentSpectateTarget)
        end
    end
end

--=============================
-- Core Functionality
--=============================

function SpectateHandler.StartSpectating()
    if not GameActiveBoolean.Value then return end
    
    -- Double check timer exists just in case
    if not RoundStatusValue then
        RoundStatusValue = ReplicatedStorage:FindFirstChild("Timer")
    end
    
    -- Hide lobby UI elements
    RandomTextLabel.Visible = false
    RandomFrame.Visible = false
    
    SpectateFrame.Visible = true
    spectateIndex = 1
    SetSpectateTarget(spectateIndex)

    if not spectateConnection then
        spectateConnection = RunService.Heartbeat:Connect(function()
            local alivePlayers = GetAlivePlayers()
            
            -- Safely parse the timer to minutes
            local timeStr = "00:00"
            if RoundStatusValue and RoundStatusValue.Value then
                timeStr = TimeToMinutes.MakeTimeMinute(RoundStatusValue.Value)
            end
            
            UpdateMatchStatsText(#alivePlayers, timeStr)
            
            if not currentSpectateTarget or not currentSpectateTarget.Parent or currentSpectateTarget:GetAttribute("InRound") ~= true then
                SetSpectateTarget(spectateIndex)
            end
        end)
    end
end

function SpectateHandler.StopSpectating()
    SpectateFrame.Visible = false
    
    -- Restore lobby UI elements
    RandomTextLabel.Visible = true
    RandomFrame.Visible = true
    
    currentSpectateTarget = nil

    if spectateConnection then
        spectateConnection:Disconnect()
        spectateConnection = nil
    end

    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            camera.CameraSubject = humanoid
        end
    end
end

function SpectateHandler.ToogleFrame()
    if not GameActiveBoolean.Value then return end
    
    if player:GetAttribute("InRound") == true then
        return
    end

    if SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    else
        SpectateHandler.StartSpectating()
    end
end

SpectateHandler.ToggleFrame = SpectateHandler.ToogleFrame



ArrowLeftButton.MouseButton1Click:Connect(function()
    SetSpectateTarget(spectateIndex - 1)
end)

ArrowRightButton.MouseButton1Click:Connect(function()
    SetSpectateTarget(spectateIndex + 1)
end)

ExitSpectateButton.MouseButton1Click:Connect(function()
    SpectateHandler.StopSpectating()
end)




ReceiveInfoRemote.OnClientEvent:Connect(function(kills, knifeImageId)
    if not SpectateFrame.Visible then return end
    
    SpectatingUserKillsText.Text = tostring(kills or 0)
    if knifeImageId and knifeImageId ~= "" then
        SpectatingUserKnifeCurrentlyUsingImage.Image = knifeImageId
    end
end)

return SpectateHandler