-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")



-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

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
local AppliedClient  = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings"):WaitForChild("AppliedClient")


local Debounce = false



local function RefreshUI()
	for _, v in pairs(SettingsContainer:GetChildren()) do
		if v:IsA("Frame") and v.Name ~= "Fov" then
			local settingName = v.Name
			local button = v:FindFirstChild("SettingsButton")
			local dot = button and button:FindFirstChild("ButtonThingy")
			local settingValue = Player:WaitForChild("leaderstats"):WaitForChild("Settings"):FindFirstChild(settingName)

			if button and dot and settingValue then
				if settingValue.Value then
					button.BackgroundColor3 = Color3.fromRGB(45, 125, 217)
					dot.Position = UDim2.new(0.925, 0,0.5, 0)
				else
					button.BackgroundColor3 = Color3.fromRGB(217, 43, 46)
					dot.Position = UDim2.new(0.43, 0,0.5, 0)
				end
			end
			
			
		end
	end
end


AppliedClient.OnClientEvent:Connect(function(settingname : string, value : boolean)
	if not settingname then return end
	
	
	
	if SettingsContainer:FindFirstChild(settingname) then
		local Button:ImageButton = SettingsContainer:FindFirstChild(settingname):WaitForChild("SettingsButton")
		local ButtonDot:Frame = SettingsContainer:FindFirstChild(settingname):WaitForChild("SettingsButton"):WaitForChild("ButtonThingy")
		
		if value == true then
			Button.BackgroundColor3 = Color3.fromRGB(45, 125, 217)
			ButtonDot.Position = UDim2.new(0.925, 0,0.5, 0)
		elseif value == false then
			Button.BackgroundColor3 = Color3.fromRGB(217, 43, 46)
			ButtonDot.Position = UDim2.new(0.43, 0,0.5, 0)
		end
		
	end
end)

local function Apply(settingname : string)
	if settingname == "Day" then
		local settingFrame = SettingsContainer:FindFirstChild("Day")
		if settingFrame then
			local button = settingFrame:FindFirstChild("SettingsButton")
			local dot = button and button:FindFirstChild("ButtonThingy")
			if button and dot then
				if Lighting.ClockTime < 15.5 then
					Lighting.ClockTime = 15.4
					button.BackgroundColor3 = Color3.fromRGB(217, 43, 46)
					dot.Position = UDim2.new(0.43, 0, 0.5, 0)
				else
					Lighting.ClockTime = 15.4
					button.BackgroundColor3 = Color3.fromRGB(45, 125, 217)
					dot.Position = UDim2.new(0.925, 0, 0.5, 0)
				end
			end
		end
		return -- skip server call
	end
	
	if settingname == "KeybindEdit" then
		OpenFrameModule.OpenFrame(tostring(settingname))
		return
	end
	ApplySetting:FireServer(settingname)
end

local function SetUpContainer()
	for i , v in pairs(SettingsContainer:GetChildren()) do
		if v:IsA("Frame") then
			v.SettingsButton.MouseButton1Up:Connect(function()
				if Debounce then
					return
				end
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


local function CloseFrame()
	SettingsFrame.Visible = false
	Lighting.Blur.Enabled = false
end












SetUpContainer()
RefreshUI()

CloseButton.MouseButton1Up:Connect(function()
	CloseFrame()
end)


return {}