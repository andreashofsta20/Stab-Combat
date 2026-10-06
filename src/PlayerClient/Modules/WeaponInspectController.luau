local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VRService = game:GetService("VRService")
local Config = require(ReplicatedStorage.Modules.WeaponInspectConfig)
local Revolvers = require(ReplicatedStorage.Modules.RevolversInfo)
local Knives = require(ReplicatedStorage.Modules.KnivesInfo)
local RevolverViewmodel = require(script.Parent.RevolverViewmodel)
local KnifeViewmodel = require(script.Parent.KnifeViewmodel)
local player = Players.LocalPlayer
local Controller = {}
local initialized = false
local lastStart = -math.huge
local connections = {}

local function cancel(immediate)
	RevolverViewmodel.CancelInspect(immediate)
	KnifeViewmodel.CancelInspect(immediate)
end

local function uiBlocked()
	if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return true end
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local main = gui and gui:FindFirstChild("Main")
	local frames = main and main:FindFirstChild("Frames")
	if frames then
		for _, frame in ipairs(frames:GetChildren()) do
			if frame:IsA("GuiObject") and frame.Visible then return true end
		end
	end
	local emote = main and main:FindFirstChild("EmoteFrame")
	local background = emote and emote:FindFirstChild("background")
	return background ~= nil and background.Visible
end

function Controller.Inspect()
	if not initialized or player:GetAttribute("DataReady") ~= true or uiBlocked() or VRService.VREnabled then return false end
	local character, camera = player.Character, workspace.CurrentCamera
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true
		or not camera or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid
		or (camera.CFrame.Position - camera.Focus.Position).Magnitude > Config.MaxCameraDistance then return false end
	-- Scan equipped children only on F, never every frame or through the backpack.
	for _, tool in ipairs(character:GetChildren()) do
		local view = tool:IsA("Tool") and (Revolvers[tool.Name] and RevolverViewmodel or Knives[tool.Name] and KnifeViewmodel)
		if view and view.IsActive(tool) then
			if view.IsInspecting(tool) then view.CancelInspect(false); return true end
			if humanoid.FloorMaterial == Enum.Material.Air or humanoid.Sit
				or character:GetAttribute(Config.PostureAttribute) == "Slide"
				or os.clock() - lastStart < Config.CooldownSeconds then return false end
			if view.StartInspect(tool) then lastStart = os.clock(); return true end
			return false
		end
	end
	return false
end

function Controller.Init()
	if initialized then return end
	initialized = true
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode[Config.Key] then
			Controller.Inspect()
		end
	end))
	local function interrupt() cancel(true) end
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(interrupt))
	table.insert(connections, UserInputService.TextBoxFocused:Connect(interrupt))
	table.insert(connections, GuiService.MenuOpened:Connect(interrupt))
	table.insert(connections, player.CharacterRemoving:Connect(interrupt))
end

function Controller.Destroy()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	cancel(true)
	initialized, lastStart = false, -math.huge
end

return Controller
