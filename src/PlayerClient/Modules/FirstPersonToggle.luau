local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local Config = require(ReplicatedStorage.Modules.CameraToggleConfig)
local Validation = require(ReplicatedStorage.Modules.KeybindValidation)
local MenuCamera = require(script.Parent.MenuCamera)
local player = Players.LocalPlayer
local Toggle = {}
local initialized, locked = false, false
local binding = Validation.GetDefaults().ToogleCam
local lastToggle = -math.huge
local previousMode, previousZoom
local connections = {}
local restoreBinding = "FirstPersonToggleZoomRestore"
local ownedMin, previousMin

local function waitForPlayerData()
	while player.Parent == Players
		and player:GetAttribute("DataReady") ~= true
		and player:GetAttribute("DataLoadState") ~= "Failed" do
		player.AttributeChanged:Wait()
	end
	if player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then
		warn("[FirstPersonToggle] Player data was not ready; first-person toggle disabled")
		return nil
	end
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local keyBinds = leaderstats and leaderstats:WaitForChild("KeyBinds", 10)
	local bind = keyBinds and keyBinds:WaitForChild("ToogleCam", 10)
	if not bind then
		warn("[FirstPersonToggle] Missing leaderstats.KeyBinds.ToogleCam; first-person toggle disabled")
	end
	return bind
end

local function restoreZoomLimit()
	RunService:UnbindFromRenderStep(restoreBinding)
	if ownedMin ~= nil and player.CameraMinZoomDistance == ownedMin then
		player.CameraMinZoomDistance = math.min(previousMin, player.CameraMaxZoomDistance)
	end
	ownedMin, previousMin = nil, nil
end

local function uiBlocked()
	if MenuCamera.IsBlocking() then return true end
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

local function ownCamera()
	local camera, character = workspace.CurrentCamera, player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return not VRService.VREnabled and camera and camera.CameraType == Enum.CameraType.Custom
		and humanoid and humanoid.Health > 0 and character:GetAttribute("Ragdolled") ~= true
		and camera.CameraSubject == humanoid
end

local function returnToThirdPerson()
	if not ownCamera() then return end
	local distance = previousZoom or Config.ReturnZoomDistance
	if distance <= Config.FirstPersonDistance then distance = Config.ReturnZoomDistance end
	local minimum = player.CameraMinZoomDistance
	local target = math.clamp(distance, minimum, player.CameraMaxZoomDistance)
	if target <= minimum then return end
	-- Classic unlocks the wheel but retains the native camera's current distance.
	-- Let that camera clamp outward for one update, then restore the zoom range.
	-- No camera CFrame, private PlayerModule API or permanent render loop is used.
	previousMin, ownedMin = minimum, target
	player.CameraMinZoomDistance = target
	RunService:BindToRenderStep(restoreBinding, Enum.RenderPriority.Camera.Value + 4, restoreZoomLimit)
end

function Toggle.Toggle()
	if not initialized or player:GetAttribute("DataReady") ~= true or uiBlocked() then return false end
	local time = os.clock()
	if time - lastToggle < Config.CooldownSeconds then return false end
	if not locked and not ownCamera() then return false end
	restoreZoomLimit()
	lastToggle = time
	if locked then
		locked = false
		if player.CameraMode == Enum.CameraMode.LockFirstPerson then
			player.CameraMode = previousMode
			returnToThirdPerson()
		end
		previousMode, previousZoom = nil, nil
	else
		local camera = workspace.CurrentCamera
		previousMode = Enum.CameraMode.Classic
		previousZoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		locked = true
		-- Native LockFirstPerson also blocks wheel/gamepad zoom-out and persists
		-- through equipment changes and respawn without touching character physics.
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	return true
end

function Toggle.Init()
	if initialized then return end
	local bind = waitForPlayerData()
	if not bind then return end
	initialized = true
	local function updateBinding()
		binding = Validation.NormalizeForAction("ToogleCam", bind.Value) or Validation.GetDefaults().ToogleCam
	end
	updateBinding()
	table.insert(connections, bind.Changed:Connect(updateBinding))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and Validation.Matches(binding, input) then Toggle.Toggle() end
	end))
	table.insert(connections, player:GetPropertyChangedSignal("CameraMode"):Connect(function()
		if MenuCamera.IsWritingMode() or MenuCamera.IsSuspendingFirstPerson() then return end
		-- Respect another camera controller taking ownership, rather than fighting it.
		if locked and player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			locked, previousMode, previousZoom = false, nil, nil
		end
	end))
	MenuCamera.Init()
end

function Toggle.Destroy()
	if not initialized then return end
	initialized = false
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	MenuCamera.Destroy()
	restoreZoomLimit()
	if locked and player.CameraMode == Enum.CameraMode.LockFirstPerson then player.CameraMode = previousMode end
	locked, previousMode, previousZoom = false, nil, nil
	lastToggle = -math.huge
end

return Toggle
