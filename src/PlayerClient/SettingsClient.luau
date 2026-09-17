-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- // MODULES // --
local OpenFrameModule = require(script.Parent:WaitForChild("FramesHandler"))

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
local dayTween
local musicVolumes = {}

local function isMusicSound(sound: Sound)
	local soundGroup = sound.SoundGroup
	return sound:GetAttribute("IsMusic") == true
		or string.find(string.lower(sound.Name), "music", 1, true) ~= nil
		or (soundGroup and string.lower(soundGroup.Name) == "music")
end

local function ApplyMusicSetting(isEnabled: boolean)
	for sound, originalVolume in pairs(musicVolumes) do
		if sound.Parent then
			sound.Volume = isEnabled and originalVolume or 0
		else
			musicVolumes[sound] = nil
		end
	end

	for _, descendant in ipairs(SoundService:GetDescendants()) do
		if descendant:IsA("Sound") and isMusicSound(descendant) then
			if musicVolumes[descendant] == nil then
				musicVolumes[descendant] = descendant.Volume
			end
			descendant.Volume = isEnabled and musicVolumes[descendant] or 0
		end
	end
end

local function ApplyDayLighting(isDay: boolean)
	if dayTween then
		dayTween:Cancel()
	end

	dayTween = TweenService:Create(
		Lighting,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ ClockTime = isDay and 14.5 or 0 }
	)
	dayTween:Play()
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
		if UserInputService.TouchEnabled then
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
			if v.Name == "KeybindEdit" and UserInputService.TouchEnabled then
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
	daySetting:GetPropertyChangedSignal("Value"):Connect(function()
		ApplyDayLighting(daySetting.Value)
	end)
	ApplyDayLighting(daySetting.Value)
end
local musicSetting = SettingsFolder:FindFirstChild("Music")
if musicSetting and musicSetting:IsA("BoolValue") then
	musicSetting:GetPropertyChangedSignal("Value"):Connect(function()
		ApplyMusicSetting(musicSetting.Value)
	end)
	SoundService.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") and isMusicSound(descendant) then
			ApplyMusicSetting(musicSetting.Value)
		end
	end)
	ApplyMusicSetting(musicSetting.Value)
end
CloseButton.MouseButton1Up:Connect(CloseFrame)

return {}