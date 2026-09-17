-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeybindValidation = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KeybindValidation"))

-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui


-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")


local ThrowKnife = MainGUI:WaitForChild("BottomLeft"):WaitForChild("StuffContainer"):WaitForChild("Ability"):WaitForChild("Keybind"):WaitForChild("KeyText")
local Emote = MainGUI:WaitForChild("BasicControls"):WaitForChild("1"):WaitForChild("Slot#")
local Sprint = MainGUI:WaitForChild("BasicControls"):WaitForChild("2"):WaitForChild("Slot#")
local Crouch = MainGUI:WaitForChild("BasicControls"):WaitForChild("3"):WaitForChild("Slot#")
local Slide = MainGUI:WaitForChild("BasicControls"):WaitForChild("4"):WaitForChild("Slot#")
local Slot1 = MainGUI:WaitForChild("Bottom"):WaitForChild("1"):WaitForChild("Slot#")
local Slot2 = MainGUI:WaitForChild("Bottom"):WaitForChild("2"):WaitForChild("Slot#")
local Slot3 = MainGUI:WaitForChild("Bottom"):WaitForChild("3"):WaitForChild("Slot#")





local leaderstats = Player:WaitForChild("leaderstats")
local KeybindsFolder = leaderstats:WaitForChild("KeyBinds")

-- // FUNCTIONS // --

local function StringToEnum(str)
	local prefix = "Enum.KeyCode."
	if str:sub(1, #prefix) == prefix then
		local keyName = str:sub(#prefix + 1)
		return Enum.KeyCode[keyName]
	end
	return nil
end

local function NormalizeKeyValue(value)
	local cleaned = tostring(value)
	cleaned = cleaned:gsub("^Enum%.KeyCode%.", "")
	
	if cleaned == "One" then
		cleaned = "1"
	elseif cleaned == "Two" then
		cleaned = "2"
	elseif cleaned == "Three" then
		cleaned = "3"
	end

	if cleaned == "MouseButton1" or cleaned == "MouseLeftButton" then
		cleaned = "LClick"
	elseif cleaned == "MouseButton2" or cleaned == "MouseRightButton" then
		cleaned = "RClick"
	elseif cleaned == "MouseButton3" then
		cleaned = "MClick"
	end

	return cleaned
end

local function KeyCodeToString(keycode)
	if typeof(keycode) == "string" then
		keycode = StringToEnum(keycode) or keycode
	end

	if typeof(keycode) == "string" then
		return NormalizeKeyValue(keycode)
	end

	local name = keycode.Name

	local numberWords = {
		Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
		Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	}

	if numberWords[name] then
		return numberWords[name]
	end

	local specialNames = {
		Space = "Space",
		LeftShift = "Shift", RightShift = "Shift",
		LeftControl = "Ctrl", RightControl = "Ctrl",
		LeftAlt = "Alt", RightAlt = "Alt",
		Enter = "Enter",
		Backspace = "Backspace",
	}

	if specialNames[name] then
		return specialNames[name]
	end

	return name
end

local function FormatKeybindDisplay(rawValue)
	return KeybindValidation.ToDisplay(rawValue)
end

local function ChangeText(name, newKeybind)
	local displayValue = FormatKeybindDisplay(newKeybind)

	if name == "ThrowKnife" then
		ThrowKnife.Text = displayValue
	elseif name == "Emote" then
		Emote.Text = displayValue
	elseif name == "Sprint" then
		Sprint.Text = displayValue
	elseif name == "Slot1" then
		Slot1.Text = displayValue
	elseif name == "Slot2" then
		Slot2.Text = displayValue
	elseif name == "Slot3" then
		Slot3.Text = displayValue
	elseif name == "Crouch" then
		Crouch.Text = displayValue
	elseif name == "Slide" then
		Slide.Text = displayValue
	end
end


for _, v in pairs(KeybindsFolder:GetChildren()) do
	if v:IsA("StringValue") then
		ChangeText(v.Name, v.Value)
		v.Changed:Connect(function(newValue)
			ChangeText(v.Name, newValue) 
		end)
	end
end

return {}