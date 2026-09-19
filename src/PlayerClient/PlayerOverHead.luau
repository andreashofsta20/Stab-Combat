-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // TEMPLATE // --
local Modules = ReplicatedStorage:WaitForChild("Modules")
local WinStreakImages = require(Modules:WaitForChild("WinStreakImages"))

local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local OverHeadTemplates = UITemplates:WaitForChild("OverheadTemplates")
local OverHeadTemplate = OverHeadTemplates:WaitForChild("Overhead")
local DamageTextTemplate = OverHeadTemplates:WaitForChild("DamageAmount")

local DamageDealtClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("DamageDealtClient")

-- // CORE FUNCTIONS // --

local function CreateOverhead(player: Player, character: Model)
    local head = character:WaitForChild("Head", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not (head and humanoid) then return end
    
    -- Cleanup old overhead if it exists
    local overheadName = "OverheadUI_" .. player.Name
    if head:FindFirstChild(overheadName) then
        head[overheadName]:Destroy()
    end

    local overhead = OverHeadTemplate:Clone()
    overhead.Name = overheadName

    local container = overhead:WaitForChild("Container")
    local nameLabel = container:WaitForChild("PlayerName")
    local membershipBadge = container:WaitForChild("PlayerMembership")
    
    local leaderstats = player:WaitForChild("leaderstats", 5)
    if not leaderstats then return end
    
    local settingsFolder = leaderstats:WaitForChild("Settings")
    local lobbyModeSetting = settingsFolder:WaitForChild("LobbyMode")
    local winStreakValue = leaderstats:WaitForChild("WinStreak")

    -- Track connections to prevent memory leaks when player respawns
    local connections = {}

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

    local StreakFrame = container:WaitForChild("Streak")
    local StreakFireImage = StreakFrame:WaitForChild("FireEmoji")
    local StreakAmountLabel = StreakFrame:WaitForChild("StreakValue")

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
    local healthBar = container:WaitForChild("Health"):WaitForChild("Container"):WaitForChild("HealthBar")
    container.Health.Visible = true
    healthBar.Size = UDim2.new(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 0, 1, 0)

    local currentHealthTween
    table.insert(connections, humanoid.HealthChanged:Connect(function(currentHealth)
        local percent = math.clamp(currentHealth / humanoid.MaxHealth, 0, 1)
        if currentHealthTween then currentHealthTween:Cancel() end
        
        currentHealthTween = TweenService:Create(
            healthBar,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(percent, 0, 1, 0)}
        )
        currentHealthTween:Play()
    end))

    overhead.Parent = head

    -- Cleanup when character dies/leaves
    overhead.AncestryChanged:Connect(function(_, parent)
        if not parent then
            for _, conn in ipairs(connections) do
                conn:Disconnect()
            end
            if currentHealthTween then currentHealthTween:Cancel() end
        end
    end)
end

local function AnimateDamageText(damageFrame, amount)
    local damageText = DamageTextTemplate:Clone()
    damageText.Text = tostring(amount)
    
    local randomOffset = math.random(-25, 25) / 100 

    damageText.Size = UDim2.new(0, 0, 0, 0)
    damageText.Position = UDim2.new(0.5 + randomOffset, 0, 0.7, 0)
    damageText.TextTransparency = 1
    damageText.TextStrokeTransparency = 1
    damageText.AnchorPoint = Vector2.new(0.5, 0.5)
    damageText.Visible = true
    damageText.Parent = damageFrame


    local popTween = TweenService:Create(damageText, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(1.2, 0, 1.2, 0),
        Position = UDim2.new(0.5 + randomOffset, 0, 0.4, 0),
        TextTransparency = 0,
        TextStrokeTransparency = 0
    })


    local fadeTween = TweenService:Create(damageText, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        Size = UDim2.new(0.9, 0, 0.9, 0),
        Position = UDim2.new(0.5 + randomOffset, 0, 0, 0),
        TextTransparency = 1,
        TextStrokeTransparency = 1
    })

    popTween:Play()
    popTween.Completed:Wait()
    
    task.wait(0.15) 
    
    fadeTween:Play()
    fadeTween.Completed:Wait()
    
    damageText:Destroy()
end

-- // CONNECTIONS // --

local function SetupPlayer(player: Player)
    player.CharacterAdded:Connect(function(character)
        CreateOverhead(player, character)
    end)
    if player.Character then
        CreateOverhead(player, player.Character)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    SetupPlayer(player)
end
Players.PlayerAdded:Connect(SetupPlayer)


DamageDealtClient.OnClientEvent:Connect(function(victimCharacter: Model, amount: number)
    if not victimCharacter then return end
    
    local head = victimCharacter:FindFirstChild("Head")
    if not head then return end
    
    local targetOverhead = nil
    for _, child in ipairs(head:GetChildren()) do
        if child.Name:match("^OverheadUI_") then
            targetOverhead = child
            break
        end
    end
    
    if targetOverhead then
        local container = targetOverhead:FindFirstChild("Container")
        local damageFrame = container and container:FindFirstChild("DamageFrame")
        if damageFrame then
            task.spawn(AnimateDamageText, damageFrame, amount)
        end
    end
end)

return {}