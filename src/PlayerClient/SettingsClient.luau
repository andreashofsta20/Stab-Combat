-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- // MODULES // --
local OpenFrameModule = require(script.Parent:WaitForChild("FramesHandler"))
local LobbyLighting = require(script.Parent:WaitForChild("Modules"):WaitForChild("LobbyLighting"))

-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGUI:WaitForChild("Frames")
local SettingsFrame = FramesFolder:WaitForChild("Settings")
local SettingsContainer = SettingsFrame:WaitForChild("Container")
local CloseButton = SettingsFrame:WaitForChild("Exit")

-- // REMOTE // --
local ApplySetting = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings"):WaitForChild("ApplySetting")
local AppliedClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings"):WaitForChild("AppliedClient")

-- // DEBOUNCE // --
local Debounce = false

local function WaitForSettings()
	local stats = Player:WaitForChild("leaderstats")
	local settingsFolder = stats:WaitForChild("Settings")
	return settingsFolder
end

local SettingsFolder = WaitForSettings()

-- These controls are generated so the new options also work in existing
-- Studio templates. They use the same persisted boolean settings protocol.
for index, info in ipairs({{"ReducedEffects", "Reduced effects"}, {"HighContrastCrosshair", "High contrast crosshair"}}) do
	if not SettingsContainer:FindFirstChild(info[1]) then
		local row = Instance.new("Frame")
		row.Name, row.Size, row.BackgroundTransparency, row.LayoutOrder = info[1], UDim2.new(1, 0, 0, 44), 1, 100 + index
		local title = Instance.new("TextLabel")
		title.Name, title.Text, title.Size, title.BackgroundTransparency = "Title", info[2], UDim2.new(0.65, 0, 1, 0), 1
		title.TextColor3, title.TextSize, title.Parent = Color3.new(1, 1, 1), 16, row
		local button = Instance.new("TextButton")
		button.Name, button.Text, button.Size, button.Position = "SettingsButton", "", UDim2.new(0.2, 0, 0.65, 0), UDim2.new(0.77, 0, 0.175, 0)
		button.Parent = row
		local dot = Instance.new("Frame")
		dot.Name, dot.Size, dot.AnchorPoint, dot.Parent = "ButtonThingy", UDim2.new(0, 12, 0, 12), Vector2.new(0.5, 0.5), button
		row.Parent = SettingsContainer
	end
end

local function RefreshUI()
	for _, v in pairs(SettingsContainer:GetChildren()) do
		if v:IsA("Frame") and v.Name ~= "Fov" then
			local settingName = v.Name
			local button = v:FindFirstChild("SettingsButton")
			local dot = button and button:FindFirstChild("ButtonThingy")
			local settingValue = SettingsFolder:FindFirstChild(settingName)

			if button and dot and settingValue then
				if settingValue.Value then
					button.BackgroundColor3 = Color3.fromRGB(45, 125, 217)
					dot.Position = UDim2.new(0.925, 0, 0.5, 0)
				else
					button.BackgroundColor3 = Color3.fromRGB(217, 43, 46)
					dot.Position = UDim2.new(0.43, 0, 0.5, 0)
				end
			end
		end
	end
end

AppliedClient.OnClientEvent:Connect(function(settingName : string, value : boolean)
	if not settingName then return end

	local frame = SettingsContainer:FindFirstChild(settingName)
	if frame then
		local button = frame:WaitForChild("SettingsButton")
		local dot = button:WaitForChild("ButtonThingy")

		if value then
			button.BackgroundColor3 = Color3.fromRGB(45, 125, 217)
			dot.Position = UDim2.new(0.925, 0, 0.5, 0)
		else
			button.BackgroundColor3 = Color3.fromRGB(217, 43, 46)
			dot.Position = UDim2.new(0.43, 0, 0.5, 0)
		end
	end
end)

local function Apply(settingName : string)
	if settingName == "KeybindEdit" then
		if not UserInputService.KeyboardEnabled then
			return
		end
		OpenFrameModule.OpenFrame(tostring(settingName))
		return
	end

	ApplySetting:FireServer(settingName)
end

local function SetUpContainer()
	for _, v in pairs(SettingsContainer:GetChildren()) do
		if v:IsA("Frame") then
			if v.Name == "KeybindEdit" and not UserInputService.KeyboardEnabled then
				v.Visible = false
				continue
			end
			local button = v:FindFirstChild("SettingsButton")
			if button then
				button.MouseButton1Up:Connect(function()
					if Debounce then return end
					Debounce = true
					Apply(v.Name)
					task.spawn(function()
						task.wait(0.25)
						Debounce = false
					end)
				end)
			end
		end
	end
end


local function CloseFrame()
	SettingsFrame.Visible = false
	Lighting.Blur.Enabled = false
end

local function BindSettingSignals()
	for _, setting in ipairs(SettingsFolder:GetChildren()) do
		if setting:IsA("BoolValue") then
			setting:GetPropertyChangedSignal("Value"):Connect(RefreshUI)
		end
	end

	SettingsFolder.ChildAdded:Connect(function(child)
		if child:IsA("BoolValue") then
			child:GetPropertyChangedSignal("Value"):Connect(RefreshUI)
		end
		RefreshUI()
	end)

	SettingsFolder.ChildRemoved:Connect(RefreshUI)
end


BindSettingSignals()
SetUpContainer()
RefreshUI()
local daySetting = SettingsFolder:FindFirstChild("Day")
if daySetting and daySetting:IsA("BoolValue") then
	local lightingController
	local lightingDestroyed = false
	-- Register teardown before New can yield while waiting for replicated state.
	script.Destroying:Connect(function()
		lightingDestroyed = true
		if lightingController then lightingController.Destroy(); lightingController = nil end
	end)
	local createdController = LobbyLighting.New(Player, daySetting)
	if lightingDestroyed then createdController.Destroy() else lightingController = createdController end
end
CloseButton.MouseButton1Up:Connect(CloseFrame)

return {}
