local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer
local Validation = require(RS.Modules.KeybindValidation)
local frame = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("Frames"):WaitForChild("KeybindEdit")
local container, editor = frame:WaitForChild("Container"), frame:WaitForChild("EditKeybindFrame")
local binds = player:WaitForChild("leaderstats"):WaitForChild("KeyBinds")
local remote = RS:WaitForChild("Remotes"):WaitForChild("Keybinds"):WaitForChild("ChangeKeybind")
local capture, action
local function closeEditor()
	editor.Visible = false
	action = nil
	if capture then capture:Disconnect(); capture = nil end
end
local function refresh(bind)
	local row = container:FindFirstChild(bind.Name)
	local label = row and row:FindFirstChild("KeybindFrame") and row.KeybindFrame:FindFirstChild("TextLabel")
	if label then label.Text = Validation.ToDisplay(bind.Value) end
end
local function observe(bind)
	if not bind:IsA("StringValue") then return end
	refresh(bind)
	bind.Changed:Connect(function() refresh(bind) end)
end
for _, bind in ipairs(binds:GetChildren()) do observe(bind) end
binds.ChildAdded:Connect(observe)
for _, row in ipairs(container:GetChildren()) do
	local button = row:FindFirstChild("EditKeybind")
	if button and button:IsA("GuiButton") and Validation.IsKnownAction(row.Name) then
		button.Activated:Connect(function()
			closeEditor()
			action, editor.Visible = row.Name, true
			capture = UIS.InputBegan:Connect(function(input, processed)
				if input.KeyCode == Enum.KeyCode.Escape then closeEditor(); return end
				if not frame.Visible or not editor.Visible or processed or UIS:GetFocusedTextBox() then return end
				local value = input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode or input.UserInputType.Name
				local normalized = Validation.NormalizeForAction(action, value)
				if not normalized then return end
				for _, bind in ipairs(binds:GetChildren()) do
					if bind.Name ~= action and bind:IsA("StringValue") and Validation.Normalize(bind.Value) == normalized then return end
				end
				remote:FireServer(action, normalized)
				closeEditor()
			end)
		end)
	end
end
frame:GetPropertyChangedSignal("Visible"):Connect(function() if not frame.Visible then closeEditor() end end)
UIS.WindowFocusReleased:Connect(closeEditor)
frame:WaitForChild("Exit").Activated:Connect(function()
	frame.Visible = false
	local blur = Lighting:FindFirstChild("Blur")
	if blur then blur.Enabled = false end
end)
frame:WaitForChild("Back").Activated:Connect(function()
	frame.Visible = false
	frame.Parent:WaitForChild("Settings").Visible = true
end)
return {}
