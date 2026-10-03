local Players = game:GetService("Players")
local connections = {}
local function characterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then return end
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
end
local function observe(player)
	connections[player] = player.CharacterAdded:Connect(function(character) characterAdded(player, character) end)
	if player.Character then task.spawn(characterAdded, player, player.Character) end
end
Players.PlayerAdded:Connect(observe)
Players.PlayerRemoving:Connect(function(player)
	if connections[player] then connections[player]:Disconnect(); connections[player] = nil end
end)
for _, player in ipairs(Players:GetPlayers()) do observe(player) end
