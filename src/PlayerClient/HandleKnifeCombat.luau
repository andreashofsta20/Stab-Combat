local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CombatController = require(script.Parent:WaitForChild("Modules"):WaitForChild("CombatController"))

local leaderstats = player:WaitForChild("leaderstats")
local KeyBindFolder = leaderstats:WaitForChild("KeyBinds")

local CurrentKeyBind = nil

local function isThrowInput(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return true
	end
	if typeof(CurrentKeyBind) == "EnumItem" and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == CurrentKeyBind then
		return true
	end
	if CurrentKeyBind == "MouseButton2" and input.UserInputType == Enum.UserInputType.MouseButton2 then
		return true
	end
	return false
end

local function parseInput(inputString)
	if not inputString or inputString == "" then return nil end

	if inputString:find("Enum.KeyCode.") then
		local keyName = inputString:match("Enum%.KeyCode%.(.+)")
		if keyName and Enum.KeyCode[keyName] then
			return Enum.KeyCode[keyName]
		end
	elseif inputString == "MouseButton1" then
		return "MouseButton1"
	elseif inputString == "MouseButton2" then
		return "MouseButton2"
	end
	return nil
end

local function initializeKnifeKeybinds()
	local throwKeyBind = KeyBindFolder:WaitForChild("ThrowKnife")
	KeyBindFolder:WaitForChild("Stab")

	if throwKeyBind.Value == "" or throwKeyBind.Value == nil then
		task.wait(0.1)
	end

	CurrentKeyBind = parseInput(throwKeyBind.Value) or Enum.KeyCode.E

	CombatController.Init()

--	print("Initialized knife keybinds:")
--	print("Throw:", CurrentKeyBind)
end

initializeKnifeKeybinds()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if isThrowInput(input) then
		CombatController.BeginCharge()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if isThrowInput(input) then
		CombatController.ReleaseCharge()
	end
end)

KeyBindFolder:WaitForChild("ThrowKnife").Changed:Connect(function()
	local newValue = KeyBindFolder.ThrowKnife.Value
	local newInput = parseInput(newValue)
	if newInput then
		CurrentKeyBind = newInput
	--	print("Updated ThrowKnife bind to", tostring(newInput))
	else
		warn("Invalid ThrowKnife bind:", newValue)
	end
end)

KeyBindFolder:WaitForChild("Stab").Changed:Connect(function()
	-- Stab bind remains data-driven for UI consistency; combat action is hold/tap unified via Throw input.
end)

return {}