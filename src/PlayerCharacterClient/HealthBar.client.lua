local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local GUI = PlayerGui:WaitForChild("Main")
local TopUIFrame = GUI:WaitForChild("TopUI")
local BarContainer = TopUIFrame:WaitForChild("BarContainer")
local HealthFrame = BarContainer:WaitForChild("Health")
local HealthBar = HealthFrame:WaitForChild("Container"):WaitForChild("HealthBar")

local LosingHealthFrame = GUI:WaitForChild("HitFrame")
LosingHealthFrame.Visible = false -- Ensure it starts hidden

local connections = {}
local character = script.Parent
local alive = true

local currentTween = nil
local hitFrameThread = nil -- Stores our delayed task to hide the frame
local lastHealth = 100 -- Stores health to check if it went up or down

local tweenInfo = TweenInfo.new(
    0.5,
    Enum.EasingStyle.Quad,
    Enum.EasingDirection.Out
)


local function cleanupConnections()
    for _, connection in ipairs(connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(connections)
end

local function cleanup()
    if not alive then return end
    alive = false
    cleanupConnections()
    if currentTween then currentTween:Cancel(); currentTween = nil end
    if hitFrameThread then pcall(task.cancel, hitFrameThread); hitFrameThread = nil end
    if Player.Character == character then LosingHealthFrame.Visible = false end
end

local function setupHealthBar(character)
    cleanupConnections()

    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid or Player.Character ~= character then
        warn("HealthBar: Couldn't find Humanoid")
        return
    end

    -- Set initial health
    lastHealth = humanoid.Health

    local function updateBar(snapInstantly)
        if not alive or Player.Character ~= character then return end
        local health = humanoid.Health
        local maxHealth = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
        local percent = math.clamp(health / maxHealth, 0, 1)
        
        local targetSize = UDim2.new(percent, 0, 1, 0)

        if currentTween then
            currentTween:Cancel()
            currentTween = nil
        end

        if snapInstantly then
            HealthBar.Size = targetSize
        else
            currentTween = TweenService:Create(HealthBar, tweenInfo, {Size = targetSize})
            currentTween:Play()
        end

        -- // NEW HIT FRAME LOGIC //
        if health < lastHealth then
            -- Make the red flash frame visible
            LosingHealthFrame.Visible = true
            
            -- If they get hit again while it's visible, cancel the previous hide timer
            if hitFrameThread then
                pcall(task.cancel, hitFrameThread)
            end
            
            -- Hide the frame after 0.25 seconds (adjust this number to make it longer/shorter)
            hitFrameThread = task.delay(0.25, function()
                hitFrameThread = nil
                if alive and Player.Character == character then LosingHealthFrame.Visible = false end
            end)
        end
        
        -- Update lastHealth for the next time this function runs
        lastHealth = health
    end

    updateBar(true)

    table.insert(connections, humanoid.HealthChanged:Connect(function()
        updateBar(false)
    end))
    
    table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        updateBar(false)
    end))
end

-- StarterCharacterScripts creates a fresh controller for each character. Old
-- controllers must not subscribe to future spawns or redraw the new HUD.
setupHealthBar(character)
table.insert(connections, Player.CharacterRemoving:Connect(function(removed)
    if removed == character then cleanup() end
end))
table.insert(connections, script.Destroying:Connect(cleanup))

return {}
