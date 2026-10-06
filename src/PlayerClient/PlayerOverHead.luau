-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- // TEMPLATE // --
local Modules = ReplicatedStorage:WaitForChild("Modules")
local WinStreakImages = require(Modules:WaitForChild("WinStreakImages"))

local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local OverHeadTemplates = UITemplates:WaitForChild("OverheadTemplates")
local OverHeadTemplate = OverHeadTemplates:WaitForChild("Overhead")
local records = {}
local function clearCharacter(record)
    record.character = nil
    if record.cleanup then record.cleanup(); record.cleanup = nil end
end




-- // CORE FUNCTIONS // --

local function CreateOverhead(player: Player, character: Model, record)
    local head = character:WaitForChild("Head", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not (head and humanoid) or records[player] ~= record or record.character ~= character
        or player.Character ~= character or player.Parent ~= Players then return end
    
    -- Cleanup old overhead if it exists
    local overheadName = "OverheadUI_" .. player.Name
    if head:FindFirstChild(overheadName) then
        head[overheadName]:Destroy()
    end

    local overhead = OverHeadTemplate:Clone()
    overhead.Name = overheadName
    overhead.Enabled = true
    -- Keep world occlusion, but make the UI independent of sun/moon direction.
    -- World-space height keeps the label above the head when looking up/down.
    overhead.AlwaysOnTop = false
    overhead.LightInfluence = 0
    overhead.Brightness = 2
    overhead.StudsOffset = Vector3.zero
    overhead.StudsOffsetWorldSpace = Vector3.new(0, 0.8, 0)

    local container = overhead:WaitForChild("Container")
    local nameLabel = container:WaitForChild("PlayerName")
    local membershipBadge = container:WaitForChild("PlayerMembership")
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    for _, label in ipairs(container:GetDescendants()) do
        if label:IsA("TextLabel") then
            label.TextColor3 = Color3.fromRGB(246, 248, 255)
            label.TextTransparency = 0
            label.TextStrokeColor3 = Color3.fromRGB(6, 8, 12)
            label.TextStrokeTransparency = 0.12
        end
    end
    
    local leaderstats = player:WaitForChild("leaderstats", 5)
    if not leaderstats then overhead:Destroy(); return end
    
    local settingsFolder = leaderstats:WaitForChild("Settings", 5)
    local lobbyModeSetting = settingsFolder and settingsFolder:WaitForChild("LobbyMode", 5)
    local winStreakValue = leaderstats:WaitForChild("WinStreak", 5)
    if not lobbyModeSetting or not winStreakValue or records[player] ~= record or record.character ~= character
        or player.Character ~= character or player.Parent ~= Players then overhead:Destroy(); return end

    local StreakFrame = container:WaitForChild("Streak")
    local StreakFireImage = StreakFrame:WaitForChild("FireEmoji")
    local StreakAmountLabel = StreakFrame:WaitForChild("StreakValue")
    local healthBar = container:WaitForChild("Health"):WaitForChild("Container"):WaitForChild("HealthBar")
    -- All template waits finish before this character can own any connections.
    if records[player] ~= record or record.character ~= character
        or player.Character ~= character or player.Parent ~= Players then overhead:Destroy(); return end

    -- Track connections to prevent memory leaks when player respawns
    local connections = {}
    local currentHealthTween
    local localVisibilityBound = false
    local cleaned = false
    local function cleanup()
        if cleaned then return end
        cleaned = true
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        if localVisibilityBound then
            localVisibilityBound = false
            RunService:UnbindFromRenderStep("LocalPlayerOverheadVisibility")
        end
        if currentHealthTween then currentHealthTween:Cancel(); currentHealthTween:Destroy(); currentHealthTween = nil end
        overhead:Destroy()
    end
    record.cleanup = cleanup

    local function updateMembershipBadge()
        membershipBadge.Visible = player:GetAttribute("HasVIP") == true
    end

    local isSpecial = player.UserId == 9304217232 or player.UserId == 1857999582
    if isSpecial then
        nameLabel.TextColor3 = Color3.fromHex("#F5A9D0")
    end

    local function updateDisplayName()
        local baseName = isSpecial and ("[FRIEND] " .. player.Name) or player.Name
        nameLabel.Text = lobbyModeSetting.Value == true and (baseName .. " [AFK]") or baseName
    end

    local function updateWinStreak()
        local streak = winStreakValue.Value
        if streak == 0 then
            StreakFrame.Visible = false
            return
        end
        
        StreakFrame.Visible = true
        local ImageId = WinStreakImages[0]
        if streak >= 10 then
            ImageId = WinStreakImages[10]
        elseif streak >= 5 then
            ImageId = WinStreakImages[5]
        end
        
        StreakFireImage.Image = ImageId
        StreakAmountLabel.Text = tostring(streak)
    end

    -- Run initial updates
    updateMembershipBadge()
    updateDisplayName()
    updateWinStreak()

    -- Connect signals
    table.insert(connections, player:GetAttributeChangedSignal("HasVIP"):Connect(updateMembershipBadge))
    table.insert(connections, lobbyModeSetting:GetPropertyChangedSignal("Value"):Connect(updateDisplayName))
    table.insert(connections, winStreakValue.Changed:Connect(updateWinStreak))

    -- Health Bar Logic
    container.Health.Visible = true
    healthBar.Size = UDim2.new(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 0, 1, 0)

    table.insert(connections, humanoid.HealthChanged:Connect(function(currentHealth)
        local percent = math.clamp(currentHealth / humanoid.MaxHealth, 0, 1)
        if currentHealthTween then currentHealthTween:Cancel(); currentHealthTween:Destroy() end
        
        currentHealthTween = TweenService:Create(
            healthBar,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(percent, 0, 1, 0)}
        )
        currentHealthTween:Play()
    end))

    if records[player] ~= record or record.character ~= character
        or player.Character ~= character or player.Parent ~= Players then cleanup(); return end
    overhead.Parent = head
    if player == Players.LocalPlayer then
        local hidden = false
        local function updateLocalVisibility()
            local camera = workspace.CurrentCamera
            local ownsView = camera and camera.CameraType == Enum.CameraType.Custom
                and camera.CameraSubject == humanoid and humanoid.Health > 0
            local distance = ownsView and (camera.CFrame.Position - camera.Focus.Position).Magnitude or math.huge
            -- Hysteresis avoids toggling the billboard at the native zoom boundary.
            hidden = ownsView and (player.CameraMode == Enum.CameraMode.LockFirstPerson
                or distance < (hidden and 1.1 or 0.85)) or false
            if overhead.Enabled == hidden then overhead.Enabled = not hidden end
        end
        updateLocalVisibility()
        localVisibilityBound = true
        -- One local billboard only; other players need no per-frame Lua work.
        RunService:BindToRenderStep("LocalPlayerOverheadVisibility", Enum.RenderPriority.Camera.Value + 5, updateLocalVisibility)
    end

    -- Cleanup when character dies/leaves
    table.insert(connections, overhead.AncestryChanged:Connect(function(_, parent)
        if not parent then
            cleanup()
        end
    end))
end

-- Damage text is pooled and animated by Modules.HitFeedback independently of overheads.

-- // CONNECTIONS // --

local function SetupPlayer(player: Player)
    if records[player] or player.Parent ~= Players then return end
    local record = {connections = {}}
    records[player] = record
    local function added(character)
        if record.character == character or player.Character ~= character then return end
        clearCharacter(record); record.character = character
        task.spawn(CreateOverhead, player, character, record)
    end
    table.insert(record.connections, player.CharacterAdded:Connect(added))
    table.insert(record.connections, player.CharacterRemoving:Connect(function(character)
        if record.character == character then clearCharacter(record) end
    end))
    if player.Character then added(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do
    SetupPlayer(player)
end
Players.PlayerAdded:Connect(SetupPlayer)
Players.PlayerRemoving:Connect(function(player)
    local record = records[player]
    if not record then return end
    clearCharacter(record)
    for _, connection in ipairs(record.connections) do connection:Disconnect() end
    records[player] = nil
end)



return {}
