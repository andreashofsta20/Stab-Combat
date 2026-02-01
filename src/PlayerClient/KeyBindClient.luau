-- // SERVICES // --
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local GUI = PlayerGui:WaitForChild("Main")
local FramesFolder = GUI:WaitForChild("Frames")
local KeyBindFrame = FramesFolder:WaitForChild("KeybindEdit")
local Container = KeyBindFrame:WaitForChild("Container")
local EditKeybindFrame = KeyBindFrame:WaitForChild("EditKeybindFrame")

local RemotesFolder = RS:WaitForChild("Remotes")
local KeyBindRemotes = RemotesFolder:WaitForChild("Keybinds")
local EditKeybindRemote = KeyBindRemotes:WaitForChild("ChangeKeybind")

local CloseButton = KeyBindFrame:WaitForChild("Exit")
local BackButton = KeyBindFrame:WaitForChild("Back")

local LastAction
local InputConnection
local debounce = false



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

	local numberWords = {
		Zero = "0",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
	}
	
	
	if cleaned == "One" then
		cleaned = "1"
	elseif cleaned == "Two" then
		cleaned = "2"
	elseif cleaned == "Three" then
		cleaned = "3"
	end

	if numberWords[cleaned] then
		return numberWords[cleaned]
	end

	if cleaned == "MouseButton1" or cleaned == "MouseLeftButton" then
		cleaned = "LClick"
	elseif cleaned == "MouseButton2" or cleaned == "MouseRightButton" then
		cleaned = "RClick"
	elseif cleaned == "MouseButton3" then
		cleaned = "MClick"
	end

	local specialNames = {
		Space = "Space",
		LeftShift = "Shift",
		RightShift = "Shift",
		LeftControl = "Ctrl",
		RightControl = "Ctrl",
		LeftAlt = "Alt",
		RightAlt = "Alt",
		Enter = "Enter",
		Backspace = "Backspace",
		Tab = "Tab",
		CapsLock = "Caps",
		Escape = "Esc",
	}

	if specialNames[cleaned] then
		return specialNames[cleaned]
	end

	return cleaned
end


local function KeyCodeToString(keycode)
	local name = keycode.Name

	local numberWords = {
		Zero = "0",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
	}

	if numberWords[name] then
		return numberWords[name]
	end

	local specialNames = {
		Space = "Space",
		LeftShift = "Shift",
		RightShift = "Shift",
		LeftControl = "Ctrl",
		RightControl = "Ctrl",
		LeftAlt = "Alt",
		RightAlt = "Alt",
		Enter = "Enter",
		Backspace = "Backspace",
	}

	if specialNames[name] then
		return specialNames[name]
	end

	return name
end

local function RefreshKeyBinds()
	local leaderstats = Player:WaitForChild("leaderstats")
	local keybindsFolder = leaderstats:WaitForChild("KeyBinds")
	for _, v in pairs(keybindsFolder:GetChildren()) do
		if v:IsA("StringValue") then
			if Container:FindFirstChild(v.Name) then
				local keybindText = Container[v.Name]:WaitForChild("KeybindFrame"):WaitForChild("TextLabel")
				keybindText.Text = NormalizeKeyValue(v.Value)
			end
		end
	end
end

local function EditKeyBind(action, keycodeOrString)
	if debounce then return end
	debounce = true
	EditKeybindRemote:FireServer(action, keycodeOrString)
	wait(0.2)
	debounce = false
end


local function CloseEditKeyBind()
	EditKeybindFrame.Visible = false
	if InputConnection then
		InputConnection:Disconnect()
		InputConnection = nil
	end
end

local function OpenEditKeyBind(action)
	if EditKeybindFrame.Visible then
		return
	end
	LastAction = action
	EditKeybindFrame.Visible = true

	InputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not EditKeybindFrame.Visible then
			if gameProcessed then
				return
			end
		end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			EditKeyBind(LastAction, input.KeyCode)
			CloseEditKeyBind()
		elseif inputType == Enum.UserInputType.MouseButton1 then
			EditKeyBind(LastAction, "MouseButton1")
			CloseEditKeyBind()
		elseif inputType == Enum.UserInputType.MouseButton2 then
			EditKeyBind(LastAction, "MouseButton2")
			CloseEditKeyBind()
		elseif inputType == Enum.UserInputType.MouseButton3 then
			EditKeyBind(LastAction, "MouseButton3")
			CloseEditKeyBind()
		end
	end)

end

local function SetUpContainer()
	for _, v in pairs(Container:GetChildren()) do
		if v:IsA("Frame") then
			local btn = v:WaitForChild("EditKeybind")
			btn.MouseButton1Up:Connect(function()
				OpenEditKeyBind(v.Name)
			end)
		end
	end
end

local function CloseFrame()
	if KeyBindFrame.Visible then
		KeyBindFrame.Visible = false
		if Lighting:FindFirstChild("Blur") and Lighting.Blur.Enabled then
			Lighting.Blur.Enabled = false
		end
		CloseEditKeyBind()
	end
end

local function Back()
	local SettingsFrame = FramesFolder:WaitForChild("Settings")
	if SettingsFrame.Visible then
		return
	end
	SettingsFrame.Visible = true
	KeyBindFrame.Visible = false
	CloseEditKeyBind()
end

BackButton.MouseButton1Up:Connect(Back)
CloseButton.MouseButton1Up:Connect(CloseFrame)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Escape and EditKeybindFrame.Visible then
		CloseEditKeyBind()
	end
end)

SetUpContainer()

local leaderstats = Player:WaitForChild("leaderstats")
local keybindsFolder = leaderstats:WaitForChild("KeyBinds")

RefreshKeyBinds()

for _, keybind in pairs(keybindsFolder:GetChildren()) do
	if keybind:IsA("StringValue") then
		keybind.Changed:Connect(RefreshKeyBinds)
	end
end

keybindsFolder.ChildAdded:Connect(function(child)
	if child:IsA("StringValue") then
		child.Changed:Connect(RefreshKeyBinds)
		RefreshKeyBinds()
	end
end)

keybindsFolder.ChildRemoved:Connect(function()
	RefreshKeyBinds()
end)

return {}
