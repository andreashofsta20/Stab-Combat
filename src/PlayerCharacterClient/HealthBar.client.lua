local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local GUI = PlayerGui:WaitForChild("Main")
local TopUIFrame = GUI:WaitForChild("TopUI")
local BarContainer = TopUIFrame:WaitForChild("BarContainer")
local HealthFrame = BarContainer:WaitForChild("Health")
local HealthBar = HealthFrame:WaitForChild("Container"):WaitForChild("HealthBar")

local connections = {}

local currentTween = nil

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

local function setupHealthBar(character)
	cleanupConnections()

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("HealthBar: Couldn't find Humanoid")
		return
	end

	local function updateBar(snapInstantly)
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
	end

	updateBar(true)

	table.insert(connections, humanoid.HealthChanged:Connect(function()
		updateBar(false)
	end))
	
	table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateBar(false)
	end))
end

if Player.Character then
	setupHealthBar(Player.Character)
end

Player.CharacterAdded:Connect(setupHealthBar)

return {}