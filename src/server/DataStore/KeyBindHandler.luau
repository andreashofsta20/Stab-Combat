local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Validation = require(ReplicatedStorage.KeyBinds.KeybindValidation)
local Notifications = require(script.Parent.Parent.Game.SendNotification)
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Keybinds"):WaitForChild("ChangeKeybind")
local nextRequest = {}

remote.OnServerEvent:Connect(function(player, action, value)
	if player:GetAttribute("DataReady") ~= true then return end
	local now = os.clock()
	if now < (nextRequest[player] or 0) then return end
	nextRequest[player] = now + 0.25
	local folder = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("KeyBinds")
	local bind = Validation.IsKnownAction(action) and folder and folder:FindFirstChild(action)
	if not bind or not bind:IsA("StringValue") then return end
	local normalized = Validation.NormalizeForAction(action, value)
	local message = "That key is reserved or unsupported"
	if normalized then
		for _, other in ipairs(folder:GetChildren()) do
			if other ~= bind and other:IsA("StringValue") and Validation.Normalize(other.Value) == normalized then
				normalized, message = nil, "Already using this keybind"
				break
			end
		end
	end
	if not normalized then Notifications.SendNotification(player, message, 2, "Error"); return end
	if bind.Value == normalized then return end
	bind.Value = normalized
	Notifications.SendNotification(player, "Applied new keybind", 2, "Success")
end)
Players.PlayerRemoving:Connect(function(player) nextRequest[player] = nil end)
return {}
