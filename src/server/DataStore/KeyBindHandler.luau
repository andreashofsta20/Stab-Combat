-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")


-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KeybindRemotes = RemotesFolder:WaitForChild("Keybinds")

local ChangeKeybindRemote = KeybindRemotes:WaitForChild("ChangeKeybind")
local SendBackClient = KeybindRemotes:WaitForChild("KeybindClient")


-- // MODULES // --
local DefaultKeybinds = require(ReplicatedStorage:WaitForChild("KeyBinds"):WaitForChild("DefaultKeybinds"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

local function Notify(player : Player, message : string, duration : number, image : string)
	NotificationHandler.SendNotification(player, message, duration, image)
end


-- // DEBOUNCE // --
local Debounces = {}
local DebounceTime = 0.5



local ForbiddenKeybinds = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true,

	[Enum.KeyCode.Tab] = true, 
	[Enum.KeyCode.Slash] = true,
	[Enum.KeyCode.Escape] = true, 
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,

	[Enum.KeyCode.I] = true,  
	[Enum.KeyCode.O] = true,  
	[Enum.KeyCode.MouseMiddleButton] = true,
	[Enum.KeyCode.MouseRightButton] = true, 
	[Enum.KeyCode.MouseLeftButton] = true,

	[Enum.KeyCode.F1] = true,
	[Enum.KeyCode.F2] = true,
	[Enum.KeyCode.F3] = true,
	[Enum.KeyCode.F4] = true,
	[Enum.KeyCode.F5] = true,
	[Enum.KeyCode.F6] = true,
	[Enum.KeyCode.F7] = true,
	[Enum.KeyCode.F8] = true,
	[Enum.KeyCode.F9] = true,
	[Enum.KeyCode.F10] = true,
	[Enum.KeyCode.F11] = true,  
	[Enum.KeyCode.F12] = true,
	[Enum.KeyCode.LeftMeta] = true,
	[Enum.KeyCode.RightMeta] = true,
}





local function RemoveDebounce(player : Player)
	task.wait(DebounceTime)
	Debounces[player] = nil
end


local function ChangeKeybind(player : Player, Action : string, NewKeybind)
	if not player then return end
	local leaderstats = player:WaitForChild("leaderstats")
	local keybindsFolder = leaderstats:WaitForChild("KeyBinds")
	

	local ignore = false
	
	if Action == "Stab" and tostring(NewKeybind) == "MouseButton1" then
		ignore = true
	end
	
	
	if not ignore then
		if tostring(NewKeybind) == "MouseButton1" or tostring(NewKeybind) == "MouseButton2" or tostring(NewKeybind) == "MouseButton3" then
			Notify(player, "Please try another keybind", 1, "Error")
			return
		end
	end
	
	
	if Action == "Emote" and (tostring(NewKeybind) == "MouseButton1" or tostring(NewKeybind) == "MouseButton2" or tostring(NewKeybind) == "MouseButton3") then
		Notify(player, "Please try another keybind", 1, "Error")
		return
	end

	if Debounces[player] then
		Notify(player, "Debounce", 1, "Error")
		print("Debounce")
		return
	end
	Debounces[player] = true

	if typeof(NewKeybind) == "EnumItem" then
		if ForbiddenKeybinds[NewKeybind] and not ignore then
			Notify(player, "Please try another keybind", 1, "Error")
			print("Forbidden keybind")
			RemoveDebounce(player)
			return
		end
	elseif typeof(NewKeybind) == "string" then
		if NewKeybind ~= "MouseButton1" and NewKeybind ~= "MouseButton2" and NewKeybind ~= "MouseButton3" then
			Notify(player, "Please try another keybind", 1, "Error")
			print("Invalid mouse button string")
			RemoveDebounce(player)
			return
		end
	else
		Notify(player, "Something went wrong", 1, "Error")
		print("Invalid keybind type")
		RemoveDebounce(player)
		return
	end

	-- Check if already used:
	for _, v in pairs(keybindsFolder:GetChildren()) do
		if v.Value == tostring(NewKeybind) then
			Notify(player, "Already using this keybind", 1, "Error")
			print("Already using this keybind")
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

	local actionValue = keybindsFolder:WaitForChild(Action)
	if actionValue then
		actionValue.Value = tostring(NewKeybind)
	else
		Notify(player, "Something went wrong", 1, "Error")
		print("couldn't find action")
	end
	Notify(player, "Applied new keybind", 1, "Success")
	RemoveDebounce(player)
end




ChangeKeybindRemote.OnServerEvent:Connect(function(player : Player, Action : string, NewKeybind)
	ChangeKeybind(player,Action, NewKeybind)
	
end)

return {}




