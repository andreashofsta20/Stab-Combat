local Player = game.Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local PlrGui = Player:WaitForChild("PlayerGui")
local MainUI = PlrGui:WaitForChild("Main")
local CountdownTextsFolder = MainUI:WaitForChild("CountdownTexts")

local StartingText = CountdownTextsFolder:WaitForChild("Starting")
local AttackText = CountdownTextsFolder:WaitForChild("Attack")
local RoundOverText = CountdownTextsFolder:WaitForChild("Results")

local RoundCountdownRemote = RemotesFolder:WaitForChild("RoundCountdown")

-- State tracking variables
local activeThread = nil
local activeTweens = {}

local function hideLabel(label)
    label.Visible = false
    label.TextTransparency = 1
    label.TextStrokeTransparency = 1
end

-- Cancels old animations and resets the UI
local function resetUI()
    -- 1. Stop the active while/for loops and task.waits
    if activeThread then
        task.cancel(activeThread)
        activeThread = nil
    end

    -- 2. Stop any currently playing tweens
    for _, tween in ipairs(activeTweens) do
        if tween.PlaybackState == Enum.PlaybackState.Playing then
            tween:Cancel()
        end
    end
    table.clear(activeTweens)

    -- 3. Hide all UI labels to start with a clean slate
    hideLabel(StartingText)
    hideLabel(AttackText)
    hideLabel(RoundOverText)
end

local function preCountdown(seconds, fadeAtSeconds)
    seconds = math.clamp(math.floor(seconds), 1, 30)
    fadeAtSeconds = fadeAtSeconds or 6

    StartingText.AnchorPoint = Vector2.new(0.5, 0.5)
    StartingText.Position = UDim2.new(-0.5, 0, 0.5, 0)
    StartingText.Rotation = -10
    StartingText.Text = "ROUND BEGINS IN " .. tostring(seconds)
    StartingText.Visible = true

    local slideIn = TweenService:Create(StartingText, TweenInfo.new(1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.5, 0),
        TextTransparency = 0,
        TextStrokeTransparency = 1,
        Rotation = 0,
    })
    table.insert(activeTweens, slideIn) -- Track the tween
    slideIn:Play()
    slideIn.Completed:Wait()
    task.wait(0.5)

    for i = seconds - 1, 1, -1 do
        StartingText.Text = "ROUND BEGINS IN " .. tostring(i)

        if i <= fadeAtSeconds then
            local slideOff = TweenService:Create(StartingText, TweenInfo.new(1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Position = UDim2.new(1.5, 0, 0.5, 0),
                TextTransparency = 1,
                TextStrokeTransparency = 1,
                Rotation = 10,
            })
            table.insert(activeTweens, slideOff) -- Track the tween
            slideOff:Play()

            for j = i - 1, 1, -1 do
                task.wait(1)
                StartingText.Text = "ROUND BEGINS IN " .. tostring(j)
            end

            slideOff.Completed:Wait()
            hideLabel(StartingText)
            StartingText.Position = UDim2.new(0.5, 0, 0.5, 0)
            StartingText.Rotation = 0
            return
        end

        task.wait(1)
    end

    hideLabel(StartingText)
end

local function roundOverAnimation()
    RoundOverText.Text = "ROUND OVER"
    RoundOverText.Size = UDim2.new(0.4, 0, 0.2, 0)
    RoundOverText.Rotation = math.random(-30, 30)
    RoundOverText.Visible = true

    local tweenIn = TweenService:Create(RoundOverText, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        TextTransparency = 0,
        TextStrokeTransparency = 1,
        Size = UDim2.new(0.8, 0, 0.8, 0),
        Rotation = 0,
    })
    table.insert(activeTweens, tweenIn) -- Track the tween
    tweenIn:Play()
    tweenIn.Completed:Wait()
    task.wait(0.7)

    local tweenOut = TweenService:Create(RoundOverText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        Size = UDim2.new(0.95, 0, 0.95, 0),
        Rotation = math.random(-20, 20),
    })
    table.insert(activeTweens, tweenOut) -- Track the tween
    tweenOut:Play()
    tweenOut.Completed:Wait()
    task.wait(0.1)
    
    hideLabel(RoundOverText)
end

local function fightCountdown()
    for _, v in ipairs({"3", "2", "1"}) do
        AttackText.Text = v
        AttackText.Size = UDim2.new(0.4, 0, 0.2, 0)
        AttackText.Rotation = math.random(-30, 30)
        AttackText.Visible = true

        local tweenIn = TweenService:Create(AttackText, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            TextTransparency = 0,
            TextStrokeTransparency = 1,
            Size = UDim2.new(0.8, 0, 0.8, 0),
            Rotation = 0,
        })
        table.insert(activeTweens, tweenIn) -- Track the tween
        tweenIn:Play()
        tweenIn.Completed:Wait()
        task.wait(0.4)

        local tweenOut = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
            Size = UDim2.new(0.95, 0, 0.95, 0),
            Rotation = math.random(-20, 20),
        })
        table.insert(activeTweens, tweenOut) -- Track the tween
        tweenOut:Play()
        tweenOut.Completed:Wait()
        task.wait(0.1)
    end

    AttackText.Text = "FIGHT"
    AttackText.Size = UDim2.new(1, 0, 1, 0)
    AttackText.Rotation = -20
    AttackText.Visible = true

    local fightIn = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        TextTransparency = 0,
        TextStrokeTransparency = 1,
        Rotation = 0,
        Size = UDim2.new(0.85, 0, 0.85, 0),
    })
    table.insert(activeTweens, fightIn) -- Track the tween
    fightIn:Play()
    fightIn.Completed:Wait()
    task.wait(0.5)

    local fightOut = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        Size = UDim2.new(1.1, 0, 1.1, 0),
        Rotation = 30,
    })
    table.insert(activeTweens, fightOut) -- Track the tween
    fightOut:Play()
    fightOut.Completed:Wait()
    
    hideLabel(AttackText)
end

RoundCountdownRemote.OnClientEvent:Connect(function(phase, ...)
    resetUI() -- Critical: Clears old backlogged animations before starting a new one!

    if phase == "pre" then
        local seconds, fadeAt = ...
        if type(seconds) ~= "number" then return end
        activeThread = task.spawn(preCountdown, seconds, fadeAt)
    elseif phase == "fight" then
        activeThread = task.spawn(fightCountdown)
    elseif phase == "roundover" then
        activeThread = task.spawn(roundOverAnimation)
    end
end)

return {}