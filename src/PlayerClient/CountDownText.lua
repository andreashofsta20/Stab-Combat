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

local function hideLabel(label)
	label.Visible = false
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
end

local function preCountdown(seconds, fadeAtSeconds)
	seconds = math.clamp(math.floor(seconds), 1, 30)
	fadeAtSeconds = fadeAtSeconds or 6

	StartingText.AnchorPoint = Vector2.new(0.5, 0.5)

	StartingText.Position = UDim2.new(-0.5, 0, 0.5, 0)
	StartingText.TextTransparency = 1
	StartingText.TextStrokeTransparency = 1
	StartingText.Rotation = -10
	StartingText.Text = "ROUND BEGINS IN " .. tostring(seconds)
	StartingText.Visible = true

	local slideIn = TweenService:Create(StartingText, TweenInfo.new(1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, 0),
		TextTransparency = 0,
		TextStrokeTransparency = 1,
		Rotation = 0,
	})
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
			slideOff:Play()


			for j = i - 1, 1, -1 do
				task.wait(1)
				StartingText.Text = "ROUND BEGINS IN " .. tostring(j)
			end

			slideOff.Completed:Wait()
			StartingText.Visible = false
			StartingText.Position = UDim2.new(0.5, 0, 0.5, 0)
			StartingText.Rotation = 0
			return
		end

		task.wait(1)
	end

	StartingText.Visible = false
end

local function roundOverAnimation()
	RoundOverText.Text = "ROUND OVER"
	RoundOverText.TextTransparency = 1
	RoundOverText.TextStrokeTransparency = 1
	RoundOverText.Size = UDim2.new(0.4, 0, 0.2, 0)
	RoundOverText.Rotation = math.random(-30, 30)
	RoundOverText.Visible = true

	local tweenIn = TweenService:Create(RoundOverText, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Size = UDim2.new(0.8, 0, 0.8, 0),
		Rotation = 0,
	})
	tweenIn:Play()
	tweenIn.Completed:Wait()
	task.wait(0.7)

	local tweenOut = TweenService:Create(RoundOverText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		TextTransparency = 1,
		Size = UDim2.new(0.95, 0, 0.95, 0),
		Rotation = math.random(-20, 20),
	})
	tweenOut:Play()
	tweenOut.Completed:Wait()
	task.wait(0.1)
	RoundOverText.Visible = false
end

local function fightCountdown()
	for _, v in ipairs({"3", "2", "1"}) do
		AttackText.Text = v
		AttackText.TextTransparency = 1
		AttackText.TextStrokeTransparency = 1
		AttackText.Size = UDim2.new(0.4, 0, 0.2, 0)
		AttackText.Rotation = math.random(-30, 30)
		AttackText.Visible = true

		local tweenIn = TweenService:Create(AttackText, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Size = UDim2.new(0.8, 0, 0.8, 0),
			Rotation = 0,
		})
		tweenIn:Play()
		tweenIn.Completed:Wait()
		task.wait(0.4)

		local tweenOut = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			TextTransparency = 1,
			Size = UDim2.new(0.95, 0, 0.95, 0),
			Rotation = math.random(-20, 20),
		})
		tweenOut:Play()
		tweenOut.Completed:Wait()
		task.wait(0.1)
	end

	AttackText.Text = "FIGHT"
	AttackText.TextTransparency = 1
	AttackText.Size = UDim2.new(1, 0, 1, 0)
	AttackText.Rotation = -20
	AttackText.Visible = true

	local fightIn = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Rotation = 0,
		Size = UDim2.new(0.85, 0, 0.85, 0),
	})
	fightIn:Play()
	fightIn.Completed:Wait()
	task.wait(0.5)

	local fightOut = TweenService:Create(AttackText, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		TextTransparency = 1,
		Size = UDim2.new(1.1, 0, 1.1, 0),
		Rotation = 30,
	})
	fightOut:Play()
	fightOut.Completed:Wait()
	AttackText.Visible = false
end

RoundCountdownRemote.OnClientEvent:Connect(function(phase, ...)
	if phase == "pre" then
		local seconds, fadeAt = ...
		if type(seconds) ~= "number" then return end
		task.spawn(preCountdown, seconds, fadeAt)
	elseif phase == "fight" then
		task.spawn(fightCountdown)
	elseif phase == "roundover" then
		task.spawn(roundOverAnimation)
	end
end)

return {}
