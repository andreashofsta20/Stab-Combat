local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local GUI = PlayerGui:WaitForChild("Main")
local TopUIFrame = GUI:WaitForChild("TopUI")
local BarContainer = TopUIFrame:WaitForChild("BarContainer")
local HealthFrame = BarContainer:WaitForChild("Health")
local HealthBar = HealthFrame:WaitForChild("Container"):WaitForChild("HealthBar")

while not HealthBar:IsDescendantOf(game) do
	task.wait()
end

local function setupHealthBar(character)
	local humanoid = character:FindFirstChild("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("HealthBar: Couldn't find Humanoid")
		return
	end

	local function updateBar()
		local health = humanoid.Health
		local maxHealth = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
		local percent = math.clamp(health / maxHealth, 0, 1)

		HealthBar:TweenSize(
			UDim2.new(percent, 0, 1, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quad,
			0.5
		)
	end

	updateBar()

	humanoid.HealthChanged:Connect(updateBar)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateBar)
end

if Player.Character then
	setupHealthBar(Player.Character)
	task.wait(0.2)
	HealthBar.Size = UDim2.new(1, 0, 1, 0)
end

Player.CharacterAdded:Connect(setupHealthBar)

return {}