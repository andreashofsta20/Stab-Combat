local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local Config = require(ReplicatedStorage.Modules.FirstPersonCameraConfig)
local player = Players.LocalPlayer
local Camera = {}
local beforeBinding, afterBinding = "FirstPersonPostureRestore", "FirstPersonPostureCamera"
local initialized = false
local character, camera, humanoid
local active, height = false, 0
local applied, hasApplied = {}, false

local function restore()
	local previous = applied
	if not hasApplied then return end
	hasApplied = false
	-- A spectating/custom camera may have taken ownership since our last frame.
	-- Only remove values that still match the camera values we assigned.
	if previous.camera.CameraType ~= Enum.CameraType.Custom then return end
	if previous.camera.CFrame == previous.frame then previous.camera.CFrame = previous.base end
	if previous.camera.Focus == previous.focus then previous.camera.Focus = previous.baseFocus end
end

local function reset()
	restore()
	active, height = false, 0
end

local function update(dt)
	local nextCharacter, nextCamera = player.Character, workspace.CurrentCamera
	if nextCharacter ~= character or nextCamera ~= camera then
		reset()
		character, camera = nextCharacter, nextCamera
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
	end
	if character and (not humanoid or humanoid.Parent ~= character) then
		humanoid = character:FindFirstChildOfClass("Humanoid")
	end
	if not Config.Enabled or VRService.VREnabled or not camera or not humanoid or not character
		or humanoid.Parent ~= character or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true
		or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then reset(); return end
	local base, focus = camera.CFrame, camera.Focus
	local distance = (base.Position - focus.Position).Magnitude
	active = distance < (active and Config.ExitDistance or Config.EnterDistance)
	-- Leave third-person, spectator and VR views entirely to their camera system.
	if not active then reset(); return end
	local posture = character:GetAttribute(Config.PostureAttribute)
	local target = posture == "Slide" and Config.SlideDrop or posture == "Crouch" and Config.CrouchDrop or 0
	local blend = 1 - math.exp(-Config.FollowSpeed * math.max(0, dt))
	height += (target - height) * blend
	if height < 0.0001 and target == 0 then height = 0; return end
	-- World vertical height avoids pushing the view forward when looking down.
	-- Shift Focus equally so native zoom distance and weapon activation stay exact.
	local offset = Vector3.new(0, -height, 0)
	camera.CFrame, camera.Focus = base + offset, focus + offset
	applied.camera, applied.base, applied.baseFocus = camera, base, focus
	applied.frame, applied.focus, hasApplied = camera.CFrame, camera.Focus, true
end

function Camera.Init()
	if initialized then return end
	initialized = true
	-- Clear our previous shift before native camera code reads the last frame.
	RunService:BindToRenderStep(beforeBinding, Enum.RenderPriority.Camera.Value - 1, restore)
	-- ADS is Camera+1; both weapon models update after this at Camera+3.
	RunService:BindToRenderStep(afterBinding, Enum.RenderPriority.Camera.Value + 2, function(dt)
		local ok, failure = pcall(update, dt)
		if not ok then reset(); warn("[FirstPersonPostureCamera] " .. tostring(failure)) end
	end)
end

function Camera.Destroy()
	if not initialized then return end
	initialized = false
	RunService:UnbindFromRenderStep(beforeBinding)
	RunService:UnbindFromRenderStep(afterBinding)
	reset()
	character, camera, humanoid = nil, nil, nil
	table.clear(applied)
end

return Camera
