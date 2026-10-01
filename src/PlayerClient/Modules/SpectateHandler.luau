local SpectateHandler = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

-- Modules
local TimeToMinutes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))
local KnivesInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))

-- Local Player & Camera
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Variables & State
local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")
local RoundStatusValue = ReplicatedStorage:WaitForChild("Timer")
local spectateConnection = nil
local spectateUIThread = nil
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
local CurrentlySpectatingText2 = BottomFrame:WaitForChild("CurrentlySpectating")

local MiddleFrame = BottomFrame:WaitForChild("MiddleFrame")
local SpectatingUserKillsText = MiddleFrame:WaitForChild("Kills"):WaitForChild("KillsText")
local SpectatingUserKnifeCurrentlyUsingImage = MiddleFrame:WaitForChild("Inventory"):WaitForChild("KnifeEquippedFrame"):WaitForChild("Slot"):WaitForChild("KnifeImage")

local ArrowLeftButton = BottomFrame:WaitForChild("ArrowLeft")
local ArrowRightButton = BottomFrame:WaitForChild("ArrowRight")

local MatchStatText = MatchStats:WaitForChild("StatsText")
local ButtonVisibleWhenGameActive = MainGui:WaitForChild("Top"):WaitForChild("Buttons"):WaitForChild("Spectate")
local RandomTextLabel = MainGui:WaitForChild("SystemTexts"):WaitForChild("Status")
local RandomFrame = MainGui:WaitForChild("Bottom")


-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================

local function UpdateSpectateButtonVisibility()
    local isGameActive = GameActiveBoolean.Value
    local isInRound = player:GetAttribute("InRound") == true
    ButtonVisibleWhenGameActive.Visible = isGameActive and not isInRound
end

local function AnimateButton(button, visualTarget)
    visualTarget = visualTarget or button
    local uiScale = visualTarget:FindFirstChildOfClass("UIScale")
    
    if not uiScale then return end -- Safety check

    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    -- Pre-create tweens to prevent memory garbage collection spikes
    local hoverTween = TweenService:Create(uiScale, tweenInfo, {Scale = 1.08})
    local idleTween = TweenService:Create(uiScale, tweenInfo, {Scale = 1})
    local clickTween = TweenService:Create(uiScale, tweenInfo, {Scale = 0.92})

    button.MouseEnter:Connect(function() hoverTween:Play() end)
    button.MouseLeave:Connect(function() idleTween:Play() end)
    button.MouseButton1Down:Connect(function() clickTween:Play() end)
    button.MouseButton1Up:Connect(function() hoverTween:Play() end)
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

local function RefreshTargetUI()
    if not currentSpectateTarget then return end
    
    -- 1. Update Match Stats (Time & Alive Count)
    local alivePlayers = GetAlivePlayers()
    local timeStr = "00:00"
    if RoundStatusValue then
        timeStr = TimeToMinutes.MakeTimeMinute(RoundStatusValue.Value or 0)
    end
    
    MatchStatText.Text = string.format(
        '<font color="#ffffff">%s</font>  |  <font color="#ffffff">Players Alive: </font><font color="#6ed378">%d</font><font color="#ffffff"> / Time Left: </font><font color="#ffe941">%s</font>',
        player:GetAttribute("CurrentRoundMode") or "Free For All",
        #alivePlayers,
        timeStr
    )

    -- 2. Update Spectator Target Kills (Read locally from attribute)
    local kills = currentSpectateTarget:GetAttribute("CurrentRoundKills") or 0
    SpectatingUserKillsText.Text = tostring(kills)

    -- 3. Update Spectator Target Knife (Read locally from leaderstats)
    local leaderstats = currentSpectateTarget:FindFirstChild("leaderstats")
    if leaderstats then
        local equippedKnife = leaderstats:FindFirstChild("EquippedKnife")
        if equippedKnife and equippedKnife.Value then
            local knifeInfo = KnivesInfoModule[equippedKnife.Value]
            if knifeInfo and knifeInfo.Image and knifeInfo.Image ~= "" then
                SpectatingUserKnifeCurrentlyUsingImage.Image = knifeInfo.Image
            end
        end
    end
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

    if currentSpectateTarget then
        CurrentlySpectatingText.Text = currentSpectateTarget.DisplayName
        CurrentlySpectatingText2.Text = currentSpectateTarget.DisplayName         
        
        if currentSpectateTarget.Character then
            local humanoid = currentSpectateTarget.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                camera.CameraSubject = humanoid
            end
        end
        
        RefreshTargetUI()
    end
end


-- ==========================================
-- SPECTATE LOGIC
-- ==========================================

function SpectateHandler.StartSpectating(preferredTarget: Player?)
    if not GameActiveBoolean.Value then return end
    
    RandomTextLabel.Visible = false
    RandomFrame.Visible = false
    SpectateFrame.Visible = true
    
    spectateIndex = 1
    if preferredTarget then
        for i, p in ipairs(GetAlivePlayers()) do
            if p == preferredTarget then
                spectateIndex = i
                break
            end
        end
    end
    SetSpectateTarget(spectateIndex)

    -- Heartbeat loop: STRICTLY for keeping the camera locked to the target's respawning humanoid
    if not spectateConnection then
        spectateConnection = RunService.Heartbeat:Connect(function()
            if not currentSpectateTarget or not currentSpectateTarget.Parent or currentSpectateTarget:GetAttribute("InRound") ~= true then
                SetSpectateTarget(spectateIndex)
            elseif currentSpectateTarget.Character then
                local currentHumanoid = currentSpectateTarget.Character:FindFirstChildOfClass("Humanoid")
                if currentHumanoid and camera.CameraSubject ~= currentHumanoid then
                    camera.CameraSubject = currentHumanoid
                end
            end
        end)
    end
    
    -- UI Loop: Runs twice a second to update timers and stats without overworking the engine
    if not spectateUIThread then
        spectateUIThread = task.spawn(function()
            while SpectateFrame.Visible do
                RefreshTargetUI()
                task.wait(0.5)
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
    
    if spectateUIThread then
        task.cancel(spectateUIThread)
        spectateUIThread = nil
    end

    -- Return camera to LocalPlayer safely
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            camera.CameraSubject = humanoid
            camera.CameraType = Enum.CameraType.Custom
        end
    end
end

function SpectateHandler.ToggleFrame()
    if not GameActiveBoolean.Value then return end
    if player:GetAttribute("InRound") == true then return end

    if SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    else
        SpectateHandler.StartSpectating()
    end
end


-- ==========================================
-- EVENTS & CONNECTIONS
-- ==========================================

GameActiveBoolean.Changed:Connect(function(isActive)
    UpdateSpectateButtonVisibility()
    if not isActive and SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    end
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
    UpdateSpectateButtonVisibility()
    if player:GetAttribute("InRound") == true and SpectateFrame.Visible then
        SpectateHandler.StopSpectating()
    end
end)

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

player.CharacterAdded:Connect(function(newCharacter)
    -- If the local player respawns while spectating, ensure the camera stays on the target
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




-- ==========================================
-- KILL CAM (server-driven)
-- ==========================================
local killCamToken = 0

local function CancelKillCam()
    killCamToken += 1
end

-- FFA: watch your killer for a moment, then the server respawns you.
local function RunFFAKillCam(killer: Player, duration: number)
    killCamToken += 1
    local token = killCamToken
    local endAt = os.clock() + duration

    task.spawn(function()
        while token == killCamToken and os.clock() < endAt and killer.Parent == Players do
            local humanoid = killer.Character and killer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and camera.CameraSubject ~= humanoid then
                camera.CameraSubject = humanoid
            end
            RunService.Heartbeat:Wait()
        end
        -- Do nothing on exit: the respawn (CharacterAdded) hands the camera back to us.
    end)
end

-- Battle Royale: once the server marks us eliminated, open the normal spectate UI on the killer.
local function RunBRSpectate(killer: Player?)
    task.spawn(function()
        local deadline = os.clock() + 5
        while player:GetAttribute("InRound") == true and os.clock() < deadline do
            task.wait(0.1)
        end
        if player:GetAttribute("InRound") == true or not GameActiveBoolean.Value then return end
        if SpectateFrame.Visible then return end
        SpectateHandler.StartSpectating(killer)
    end)
end

local KillCamRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillCam", 10)
if KillCamRemote then
    KillCamRemote.OnClientEvent:Connect(function(mode, killerUserId, duration)
        -- Server is trusted, but never trust the shape of the data.
        if type(mode) ~= "string" or type(killerUserId) ~= "number" then return end
        local killer = killerUserId > 0 and Players:GetPlayerByUserId(killerUserId) or nil
        if killer == player then return end

        if mode == "Respawn" then
            if not killer then return end
            local seconds = math.clamp(tonumber(duration) or 2, 0.5, 5)
            RunFFAKillCam(killer, seconds)
        elseif mode == "Spectate" then
            RunBRSpectate(killer)
        end
    end)
end

GameActiveBoolean.Changed:Connect(function(isActive)
    if not isActive then CancelKillCam() end
end)

player.CharacterAdded:Connect(function()
    CancelKillCam()
end)

-- Initialize
UpdateSpectateButtonVisibility()
AnimateButton(ArrowLeftButton)
AnimateButton(ArrowRightButton)
AnimateButton(ExitSpectateButton, ExitSpectateButton.Parent)

return SpectateHandler