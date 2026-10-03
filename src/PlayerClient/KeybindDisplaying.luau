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
