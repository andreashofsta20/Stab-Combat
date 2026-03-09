local SpectateHandler = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

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
local lastSpectateUpdate = 0

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

local ButtonVisibleWhenGameActive = MainGui:WaitForChild("Top"):WaitForChild("Buttons"):WaitForChild("Spectate")
local RandomTextLabel = MainGui:WaitForChild("SystemTexts"):WaitForChild("Status")
local RandomFrame = MainGui:WaitForChild("Bottom")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local SpectatingRemotesFolder = RemotesFolder:WaitForChild("Spectating")
local ReceiveInfoRemote = SpectatingRemotesFolder:WaitForChild("Receive")

local RoundStatusValue = ReplicatedStorage:WaitForChild("Timer")

-- Helper function to update the button's visibility based on both conditions
local function UpdateSpectateButtonVisibility()
    local isGameActive = GameActiveBoolean.Value
    local isInRound = player:GetAttribute("InRound") == true
    
    -- Only show the button if the game is running AND the player is NOT in it
    ButtonVisibleWhenGameActive.Visible = isGameActive and not isInRound
end

-- Listen for when the game starts/ends
GameActiveBoolean.Changed:Connect(function(isActive)
    UpdateSpectateButtonVisibility()
    
    if not isActive and SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    end
end)

-- Listen for when the local player dies or joins a round
player:GetAttributeChangedSignal("InRound"):Connect(function()
    UpdateSpectateButtonVisibility()
    
    -- Safety check: if they somehow get put in a round while spectating, close the UI
    if player:GetAttribute("InRound") == true and SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    end
end)

-- Set initial state when the script first runs
UpdateSpectateButtonVisibility()


local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function AnimateButton(button, visualTarget)
    visualTarget = visualTarget or button
    local uiScale = visualTarget:FindFirstChildOfClass("UIScale")

    button.MouseEnter:Connect(function()
        TweenService:Create(uiScale, tweenInfo, {Scale = 1.08}):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(uiScale, tweenInfo, {Scale = 1}):Play()
    end)

    button.MouseButton1Down:Connect(function()
        TweenService:Create(uiScale, tweenInfo, {Scale = 0.92}):Play()
    end)

    button.MouseButton1Up:Connect(function()
        TweenService:Create(uiScale, tweenInfo, {Scale = 1.08}):Play()
    end)
end

local function GetAlivePlayers()
    local alive = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p:GetAttribute("InRound") == true then
            table.insert(alive, p)
        end
    end
    return alive
end

local function GetCurrentTargetIndex(alivePlayers)
    if not currentSpectateTarget then return 1 end
    for i, p in ipairs(alivePlayers) do
        if p == currentSpectateTarget then 
            return i 
        end
    end
    return 1 
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


function SpectateHandler.StartSpectating()
    if not GameActiveBoolean.Value then return end
    
    if not RoundStatusValue then
        RoundStatusValue = ReplicatedStorage:FindFirstChild("Timer")
    end
    
    RandomTextLabel.Visible = false
    RandomFrame.Visible = false
    
    SpectateFrame.Visible = true
    spectateIndex = 1
    SetSpectateTarget(spectateIndex)

    if not spectateConnection then
        spectateConnection = RunService.Heartbeat:Connect(function()
            local alivePlayers = GetAlivePlayers()
            
            local timeStr = "00:00"
            if RoundStatusValue and RoundStatusValue.Value then
                timeStr = TimeToMinutes.MakeTimeMinute(RoundStatusValue.Value)
            end
            
            UpdateMatchStatsText(#alivePlayers, timeStr)
            
            if not currentSpectateTarget or not currentSpectateTarget.Parent or currentSpectateTarget:GetAttribute("InRound") ~= true then
                SetSpectateTarget(spectateIndex)
            elseif currentSpectateTarget.Character then
                local currentHumanoid = currentSpectateTarget.Character:FindFirstChildOfClass("Humanoid")
                if currentHumanoid and camera.CameraSubject ~= currentHumanoid then
                    camera.CameraSubject = currentHumanoid
                end
                
                -- Live refresh data every 1 second
                if os.clock() - lastSpectateUpdate >= 1 then
                    lastSpectateUpdate = os.clock()
                    ReceiveInfoRemote:FireServer("RequestInfo", currentSpectateTarget)
                end
            end
        end)
    end
end

function SpectateHandler.StopSpectating()
    SpectateFrame.Visible = false
    
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
    local alivePlayers = GetAlivePlayers()
    local currentIndex = GetCurrentTargetIndex(alivePlayers)
    SetSpectateTarget(currentIndex - 1)
end)

ArrowRightButton.MouseButton1Click:Connect(function()
    local alivePlayers = GetAlivePlayers()
    local currentIndex = GetCurrentTargetIndex(alivePlayers)
    SetSpectateTarget(currentIndex + 1)
end)

ExitSpectateButton.MouseButton1Click:Connect(function()
    SpectateHandler.StopSpectating()
end)

AnimateButton(ArrowLeftButton)
AnimateButton(ArrowRightButton)
AnimateButton(ExitSpectateButton, ExitSpectateButton.Parent)


ReceiveInfoRemote.OnClientEvent:Connect(function(targetPlayer, kills, knifeImageId)
    if not SpectateFrame.Visible then return end

    if targetPlayer ~= currentSpectateTarget then return end 
    
    SpectatingUserKillsText.Text = tostring(kills or 0)
    if knifeImageId and knifeImageId ~= "" then
        SpectatingUserKnifeCurrentlyUsingImage.Image = knifeImageId
    end
end)


player.CharacterAdded:Connect(function(newCharacter)
    if SpectateFrame.Visible and currentSpectateTarget then
        
        local newHumanoid = newCharacter:WaitForChild("Humanoid", 3)
        
        task.wait(0.2) 
        
        if SpectateFrame.Visible and currentSpectateTarget and currentSpectateTarget.Character then
            local targetHumanoid = currentSpectateTarget.Character:FindFirstChildOfClass("Humanoid")
            if targetHumanoid then
                camera.CameraSubject = targetHumanoid
            end
        end
    end
end)

return SpectateHandler