local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Math = require(ReplicatedStorage.Modules.RevolverPoseMath)
local player = Players.LocalPlayer
local Aim = {}
local current, bound, turnConnection
local binding = "RevolverAimCamera"
local externalShiftLock = false

local function restoreControls(state)
	if state.controlsReleased then return end
	state.controlsReleased = true
	if state.humanoid.Parent and state.humanoid.AutoRotate == false then
		state.humanoid.AutoRotate = state.autoRotate
	end
	-- A temporary camera/RMB lock is not a persistent user preference. Release
	-- our lock; the native camera reapplies first person/native shift lock itself.
	UserInputService.MouseBehavior = state.mouseBehavior
	if not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = state.mouseIcon end
	if turnConnection then turnConnection:Disconnect(); turnConnection = nil end
end

local function finish()
	local state = current
	if not state then return end
	restoreControls(state)
	-- Do not undo a camera/offset taken over by another system (e.g. spectating).
	if state.camera.FieldOfView == state.lastFov then state.camera.FieldOfView = state.fov end
	if state.humanoid.Parent and state.humanoid.CameraOffset == state.lastOffset then
		state.humanoid.CameraOffset = state.offset
	end
	current = nil
	if bound then RunService:UnbindFromRenderStep(binding); bound = false end
end

function Aim.IsAiming() return current ~= nil and current.active end

function Aim.SetExternalShiftLock(enabled)
	externalShiftLock = enabled == true
	if not current then return end
	current.autoRotate = not enabled
	current.mouseBehavior = enabled and UserInputService.MouseEnabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	if current.active then current.humanoid.AutoRotate = false end
end

function Aim.Stop(immediate)
	if not current then return end
	current.active = false
	restoreControls(current)
	if immediate then finish() end
end

local function validCamera(state)
	return workspace.CurrentCamera == state.camera and player.Character == state.character
		and state.root.Parent == state.character and state.humanoid.Parent == state.character
		and state.tool.Parent == state.character and state.humanoid.Health > 0
		and state.camera.CameraType == Enum.CameraType.Custom and state.camera.CameraSubject == state.humanoid
end

local function update(dt)
	local state = current
	if not state then return end
	if not validCamera(state) then finish(); return end
	if state.active and not state.allowed() then Aim.Stop() end
	if state.camera.FieldOfView ~= state.lastFov or state.humanoid.CameraOffset ~= state.lastOffset then finish(); return end
	local alpha = Math.Alpha(state.settings.CameraFollowSpeed, dt)
	state.weight += ((state.active and 1 or 0) - state.weight) * alpha
	-- Keep native camera collision/zoom. Avoid a shoulder offset in first person.
	local firstPerson = (state.camera.CFrame.Position - state.camera.Focus.Position).Magnitude < 1
	local wantedShoulder = state.active and not firstPerson and 1 or 0
	state.shoulder += (wantedShoulder - state.shoulder) * alpha
	state.lastFov = state.fov + (math.min(state.fov, state.settings.FieldOfView) - state.fov) * state.weight
	state.lastOffset = state.offset + state.shoulderOffset * state.shoulder
	state.camera.FieldOfView, state.humanoid.CameraOffset = state.lastFov, state.lastOffset
	-- Engine properties can round numbers on assignment. Track the stored values
	-- so the ownership check doesn't mistake float rounding for another script.
	state.lastFov, state.lastOffset = state.camera.FieldOfView, state.humanoid.CameraOffset
	if state.active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	elseif state.weight < 0.001 and state.shoulder < 0.001 then finish() end
end

function Aim.Start(tool, settings, allowed)
	if not settings.Enabled or not allowed() then return false end
	if current and current.active and current.tool == tool then return true end
	-- Re-press during blend out uses the original snapshot, preventing drift.
	if current and (current.tool ~= tool or not validCamera(current)) then finish() end
	if not current then
		local character, camera = player.Character, workspace.CurrentCamera
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not character:FindFirstChild("Torso") or humanoid.Health <= 0
			or not camera or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then return false end
		current = { character = character, tool = tool, humanoid = humanoid, root = root, camera = camera,
			fov = camera.FieldOfView, lastFov = camera.FieldOfView, offset = humanoid.CameraOffset,
			lastOffset = humanoid.CameraOffset, autoRotate = humanoid.AutoRotate,
			mouseBehavior = externalShiftLock and UserInputService.MouseEnabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default,
			mouseIcon = UserInputService.MouseIconEnabled, weight = 0, shoulder = 0 }
	end
	local state = current
	state.active, state.controlsReleased, state.settings, state.allowed = true, false, settings, allowed
	state.shoulderOffset = Vector3.new(table.unpack(settings.CameraOffset))
	state.humanoid.AutoRotate = false
	UserInputService.MouseBehavior, UserInputService.MouseIconEnabled = Enum.MouseBehavior.LockCenter, false
	if not bound then
		bound = true
		RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 1, function(dt)
			local ok, err = pcall(update, dt)
			if not ok then finish(); warn("Revolver aim camera released after an error: " .. tostring(err)) end
		end)
	end
	if not turnConnection then
		turnConnection = RunService.PreSimulation:Connect(function(dt)
			if not current or not current.active then return end
			local s = current
			if not validCamera(s) or not s.allowed() then Aim.Stop(true); return end
			if s.humanoid.Sit or s.humanoid.PlatformStand or s.root.Anchored then return end
			local look = s.camera.CFrame.LookVector
			if look.X * look.X + look.Z * look.Z < 1e-6 then return end
			local body = s.root.CFrame.LookVector
			local yaw, wanted = math.atan2(-body.X, -body.Z), math.atan2(-look.X, -look.Z)
			yaw += Math.WrapAngle(wanted - yaw) * Math.Alpha(s.settings.BodyFollowSpeed, dt)
			s.root.CFrame = CFrame.new(s.root.Position) * CFrame.Angles(0, yaw, 0)
		end)
	end
	return true
end

return Aim
