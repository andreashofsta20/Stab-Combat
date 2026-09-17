-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KeybindRemotes = RemotesFolder:WaitForChild("Keybinds")

local ChangeKeybindRemote = KeybindRemotes:WaitForChild("ChangeKeybind")
local SendBackClient = KeybindRemotes:WaitForChild("KeybindClient")


-- // MODULES // --
local DefaultKeybinds = require(ReplicatedStorage:WaitForChild("KeyBinds"):WaitForChild("DefaultKeybinds"))
local KeybindValidation = require(ReplicatedStorage:WaitForChild("KeyBinds"):WaitForChild("KeybindValidation"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

local function Notify(player : Player, message : string, duration : number, image : string)
	NotificationHandler.SendNotification(player, message, duration, image)
end


-- // DEBOUNCE // --
local Debounces = {}
local DebounceTime = 0.5



local function RemoveDebounce(player : Player)
	task.wait(DebounceTime)
	Debounces[player] = nil
end


local function ChangeKeybind(player : Player, Action : string, NewKeybind)
	if not player or not KeybindValidation.IsKnownAction(Action) then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	local keybindsFolder = leaderstats and leaderstats:FindFirstChild("KeyBinds")
	if not keybindsFolder then return end

	if Debounces[player] then
		Notify(player, "Debounce", 1, "Error")
		print("Debounce")
		return
	end
	Debounces[player] = true

	local normalized = KeybindValidation.Normalize(NewKeybind)
	if not normalized or (normalized:match("^MouseButton") and Action ~= "Stab") then
		Notify(player, "Something went wrong", 1, "Error")
		RemoveDebounce(player)
		return
	end

	for _, v in pairs(keybindsFolder:GetChildren()) do
		if v.Name ~= Action and v:IsA("StringValue") and KeybindValidation.Normalize(v.Value) == normalized then
			Notify(player, "Already using this keybind", 1, "Error")
			RemoveDebounce(player)
			return
		end
	end

	if not keybindsFolder:FindFirstChild(Action) then
		Notify(player, "Something went wrong", 1, "Error")
		RemoveDebounce(player)
		
		print("couldn't find action")
		return
	end

	local actionValue = keybindsFolder:FindFirstChild(Action)
	if actionValue then
		actionValue.Value = normalized
	else
		Notify(player, "Something went wrong", 1, "Error")
		print("couldn't find action")
	end
	Notify(player, "Applied new keybind", 1, "Success")
	RemoveDebounce(player)
end

Players.PlayerRemoving:Connect(function(player)
	Debounces[player] = nil
end)

ChangeKeybindRemote.OnServerEvent:Connect(function(player : Player, Action : string, NewKeybind)
	ChangeKeybind(player, Action, NewKeybind)
end)

return {}

