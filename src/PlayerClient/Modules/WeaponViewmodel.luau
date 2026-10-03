local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")
local PhysicsService = game:GetService("PhysicsService")
local PhysicsConfig = require(ReplicatedStorage.Modules.RevolverConfig).FirstPersonPhysics
local Geometry = require(script.Parent.WeaponViewmodelGeometry)
local SkinEffects = require(script.Parent.WeaponViewmodelEffects)
local player = Players.LocalPlayer
local Factory = {}

function Factory.New(options)
	local Motion = assert(options.Motion, "Weapon viewmodel motion is required")
	local modelName = options.Name or "WeaponFirstPerson"
	local warningPrefix = options.WarningPrefix or modelName
	local Viewmodel = {}
	local current, retry

	local function restore(state)
		for part, previous in pairs(state.hidden) do
			if part.Parent and part.LocalTransparencyModifier == 1 then part.LocalTransparencyModifier = previous end
		end
		table.clear(state.hidden)
	end

	local function deactivate(state)
		if not state or not state.active then return end
		state.active = false
		if state.visual.model.Parent then state.visual.model.Parent = nil end
		if state.skinEffects then state.skinEffects.SetActive(false) end
		restore(state)
		state.motion = Motion.New()
	end

	function Viewmodel.Clear()
		if current then
			deactivate(current)
			for _, connection in ipairs(current.connections) do connection:Disconnect() end
			if current.skinEffects then current.skinEffects.Destroy() end
			Geometry.Destroy(current.visual)
			current = nil
		end
		retry = nil
	end

	local function waitForBuild(tool, character, settings, failure)
		local previous = retry and retry.tool == tool and retry.character == character and retry or nil
		local delay = failure and previous and math.min(previous.delay * 2, settings.MaxBuildRetrySeconds)
			or settings.BuildRetrySeconds
		local message = failure and tostring(failure) or nil
		if message and (not previous or previous.failure ~= message) then warn("[" .. warningPrefix .. "] " .. message) end
		retry = {tool = tool, character = character, delay = delay, remaining = delay,
			failure = message or previous and previous.failure}
	end

	local function update(tool, tuning, allowed, aiming, reloading, dt, bodyAnimation, armAnimation, action, weaponVisible)
		local character, camera = player.Character, workspace.CurrentCamera
		if retry and (retry.tool ~= tool or retry.character ~= character) then retry = nil end
		if current and (current.tool ~= tool or current.character ~= character or current.dirty
			or current.active and not current.visual.model.Parent) then Viewmodel.Clear() end
		if not tool or tool.Parent ~= character or not tuning or not tuning.FirstPerson.Enabled then Viewmodel.Clear(); return end
		local humanoid = current and current.visual.humanoid or character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true then Viewmodel.Clear(); return end
		if not allowed or ReplicatedStorage:GetAttribute(PhysicsConfig.ReadyAttribute) ~= true
			or VRService.VREnabled or not camera or camera.CameraType ~= Enum.CameraType.Custom
			or camera.CameraSubject ~= humanoid then deactivate(current); return end
		local settings = tuning.FirstPerson
		local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		if not Motion.FirstPerson(current and current.active, distance, settings) then deactivate(current); return end
		if not current then
			if retry then
				retry.remaining = math.max(0, retry.remaining - math.max(dt, 0))
				if retry.remaining > 0 then return end
			end
			-- The readiness attribute and collision registry can replicate separately.
			if not PhysicsService:IsCollisionGroupRegistered(PhysicsConfig.CollisionGroup) then return end
			local visual = Geometry.Create(character, tool, settings, modelName)
			if not visual then waitForBuild(tool, character, settings); return end
			current = {tool = tool, character = character, root = character:FindFirstChild("HumanoidRootPart"),
				visual = visual, motion = Motion.New(), hidden = {}, connections = {}}
			local state = current
			state.skinEffects = SkinEffects.New(visual.effects)
			local function changed(item)
				if item:IsA("BasePart") or item:IsA("Shirt") or item:IsA("BodyColors") or item:IsA("CharacterMesh")
					or item:IsA("DataModelMesh") or item:IsA("FaceInstance") or item:IsA("SurfaceAppearance") or item:IsA("Attachment")
					or item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") or item:IsA("Light")
					or item:IsA("Fire") or item:IsA("Smoke") or item:IsA("Sparkles")
					or item.Name == "RightGrip" and item:IsA("JointInstance") then state.dirty = true end
			end
			table.insert(state.connections, tool.DescendantAdded:Connect(changed))
			table.insert(state.connections, tool.DescendantRemoving:Connect(changed))
			table.insert(state.connections, character.DescendantAdded:Connect(changed))
			table.insert(state.connections, character.DescendantRemoving:Connect(changed))
		end
		local state = current
		Geometry.Guard(state.visual)
		if state.visual.model.Parent ~= camera then state.motion.previous = nil end
		local root = state.root
		local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		local frame, animationFrame = Motion.Step(state.motion, camera.CFrame, dt, aiming, reloading, speed, settings, bodyAnimation, armAnimation, action)
		Geometry.Place(state.visual, camera.CFrame, frame, settings, tuning.Pose.R6RotationOffset, animationFrame, weaponVisible)
		-- Publish a complete, safely placed model before hiding the real gun/arms.
		if state.visual.model.Parent ~= camera then state.visual.model.Parent = camera end
		state.active = true
		state.skinEffects.SetActive(true)
		state.skinEffects.Guard()
		for _, part in ipairs(state.visual.originals) do
			if part.Parent then
				if state.hidden[part] == nil then state.hidden[part] = part.LocalTransparencyModifier end
				if part.LocalTransparencyModifier ~= 1 then part.LocalTransparencyModifier = 1 end
			end
		end
		retry = nil -- reset backoff only after a complete successful presentation update
	end

	function Viewmodel.Update(tool, tuning, allowed, aiming, reloading, dt, bodyAnimation, armAnimation, action, weaponVisible)
		local ok, failure = pcall(update, tool, tuning, allowed, aiming, reloading, dt, bodyAnimation, armAnimation, action, weaponVisible)
		if not ok then
			local previous = retry
			Viewmodel.Clear()
			if tool and tuning and tuning.FirstPerson then
				retry = previous
				waitForBuild(tool, player.Character, tuning.FirstPerson, failure)
			else warn("[" .. warningPrefix .. "] " .. tostring(failure)) end
		end
	end

	function Viewmodel.Kick(tool)
		if current and current.active and current.tool == tool and Motion.Kick then Motion.Kick(current.motion) end
	end

	function Viewmodel.GetVisualTool(tool)
		return current and current.active and current.tool == tool and current.visual.weapon or nil
	end

	function Viewmodel.IsActive(tool)
		return current ~= nil and current.active == true and current.tool == tool
	end

	function Viewmodel.GetOriginalTransparency(part)
		return current and current.hidden[part] or part.LocalTransparencyModifier
	end

	function Viewmodel.SetOriginalTransparency(part, value)
		if current and current.hidden[part] ~= nil then current.hidden[part] = value end
	end

	function Viewmodel.IsFirstPerson(tool, tuning)
		local character, camera = player.Character, workspace.CurrentCamera
		if not tool or tool.Parent ~= character or not tuning or not tuning.FirstPerson.Enabled
			or VRService.VREnabled or not camera or camera.CameraType ~= Enum.CameraType.Custom then return false end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true
			or camera.CameraSubject ~= humanoid then return false end
		return Motion.FirstPerson(Viewmodel.IsActive(tool),
			(camera.CFrame.Position - camera.Focus.Position).Magnitude, tuning.FirstPerson)
	end

	return Viewmodel
end

return Factory
