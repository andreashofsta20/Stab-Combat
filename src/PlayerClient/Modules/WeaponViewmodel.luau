local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")
local PhysicsService = game:GetService("PhysicsService")
local PhysicsConfig = require(ReplicatedStorage.Modules.RevolverConfig).FirstPersonPhysics
local InspectConfig = require(ReplicatedStorage.Modules.WeaponInspectConfig)
local InspectMotion = require(ReplicatedStorage.Modules.WeaponInspectMotion)
local Geometry = require(script.Parent.WeaponViewmodelGeometry)
local SkinEffects = require(script.Parent.WeaponViewmodelEffects)
local player = Players.LocalPlayer
local Factory = {}
local profileBegin, profileEnd = debug.profilebegin, debug.profileend

function Factory.New(options)
	local Motion = assert(options.Motion, "Weapon viewmodel motion is required")
	local modelName = options.Name or "WeaponFirstPerson"
	local warningPrefix = options.WarningPrefix or modelName
	local buildProfileName = modelName .. "BuildBatch"
	local inspectKind = options.InspectKind or "Revolver"
	local Viewmodel = {}
	local current, retry, building
	local generation = 0
	local waitForBuild

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
		state.visual.visibility.SetActive(false)
		restore(state)
		state.motion = Motion.New()
		InspectMotion.Cancel(state.inspect, true)
		state.activeSeconds = 0
	end

	function Viewmodel.Clear()
		generation += 1 -- cancel an unfinished build without retaining the old avatar
		building = nil
		if current then
			deactivate(current)
			for _, connection in ipairs(current.connections) do connection:Disconnect() end
			if current.skinEffects then current.skinEffects.Destroy() end
			Geometry.Destroy(current.visual)
			current = nil
		end
		retry = nil
	end

	local function scheduleBuild(tool, character, tuning, humanoid)
		if building then return end
		local settings = tuning.FirstPerson
		local token = generation
		building = {tool = tool, character = character}
		task.defer(function()
			if token ~= generation then return end
			local count = 0
			local buildDirty = false
			local buildConnections = {}
			local function invalidate(item) if Geometry.IsVisual(item) then buildDirty = true end end
			table.insert(buildConnections, tool.DescendantAdded:Connect(invalidate))
			table.insert(buildConnections, tool.DescendantRemoving:Connect(invalidate))
			local function avatarChangedDuringBuild(item)
				local parent = item.Parent
				if parent == character or parent == character:FindFirstChild("Right Arm")
					or parent == character:FindFirstChild("Left Arm") then invalidate(item) end
			end
			table.insert(buildConnections, character.DescendantAdded:Connect(avatarChangedDuringBuild))
			table.insert(buildConnections, character.DescendantRemoving:Connect(avatarChangedDuringBuild))
			local limit = math.clamp(settings.BuildObjectsPerFrame or 8, 1, 32)
			local function budget(source)
				count += 1
				if count >= limit then
					count = 0
					if profileEnd then profileEnd() end
					task.wait()
					if profileBegin then profileBegin(buildProfileName) end
				end
				if buildDirty or token ~= generation or player.Character ~= character or tool.Parent ~= character
					or humanoid.Health <= 0 then error("Viewmodel build cancelled", 0) end
			end
			if profileBegin then profileBegin(buildProfileName) end
			local ok, visual = pcall(Geometry.Create, character, tool, settings, modelName, budget)
			if profileEnd then profileEnd() end
			for _, connection in ipairs(buildConnections) do connection:Disconnect() end
			if token ~= generation then
				if ok and visual then Geometry.Destroy(visual) end
				return
			end
			building = nil
			if buildDirty then
				if ok and visual then Geometry.Destroy(visual) end
				return -- a changed snapshot is retried next frame, without warning spam
			end
			if player.Character ~= character or tool.Parent ~= character or humanoid.Health <= 0 then
				if ok and visual then Geometry.Destroy(visual) end
				return
			end
			if not ok or not visual then waitForBuild(tool, character, settings, not ok and visual or nil); return end
			local effectsOk, effects = pcall(SkinEffects.New, visual.effects)
			if not effectsOk then Geometry.Destroy(visual); waitForBuild(tool, character, settings, effects); return end
			if options.PrepareVisual then
				local prepared, failure = pcall(options.PrepareVisual, visual.weapon, tuning)
				if not prepared then effects.Destroy(); Geometry.Destroy(visual); waitForBuild(tool, character, settings, failure); return end
			end
			current = {tool = tool, character = character, root = character:FindFirstChild("HumanoidRootPart"),
				visual = visual, motion = Motion.New(), inspect = InspectMotion.New(), context = {inspectBlend = 0},
				activeSeconds = 0, actionPause = 0, health = humanoid.Health, hidden = {}, connections = {}}
			local state = current
			state.skinEffects = effects
			local function changed(item)
				if Geometry.IsVisual(item) then state.dirty = true end
			end
			table.insert(state.connections, tool.DescendantAdded:Connect(changed))
			table.insert(state.connections, tool.DescendantRemoving:Connect(changed))
			local function avatarChanged(item)
				-- Other weapons and transient corpses/effects do not invalidate this copy.
				local parent = item.Parent
				if parent == character
					or parent == character:FindFirstChild("Right Arm") or parent == character:FindFirstChild("Left Arm") then changed(item) end
			end
			table.insert(state.connections, character.DescendantAdded:Connect(avatarChanged))
			table.insert(state.connections, character.DescendantRemoving:Connect(avatarChanged))
		end)
	end

	waitForBuild = function(tool, character, settings, failure)
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
		if building and (building.tool ~= tool or building.character ~= character) then Viewmodel.Clear() end
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
			scheduleBuild(tool, character, tuning, humanoid)
			return
		end
		local state = current
		Geometry.Guard(state.visual)
		if state.visual.model.Parent ~= camera then state.motion.previous = nil end
		local root = state.root
		local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		state.activeSeconds += math.max(0, dt)
		state.actionPause = math.max(0, state.actionPause - math.max(0, dt))
		if humanoid.Health < state.health then Viewmodel.InterruptInspect() end
		state.health = humanoid.Health
		local attack = action and (action.charging or action.holdingCharge
			or type(action.throwElapsed) == "number" and action.throwElapsed >= 0 and action.throwElapsed < 0.75
			or type(action.stabElapsed) == "number" and action.stabElapsed >= 0
				and action.stabElapsed < (settings.StabSeconds or 0.4))
		state.busy = aiming or reloading or attack or weaponVisible == false
		local movementBlocked = humanoid.FloorMaterial == Enum.Material.Air or humanoid.Sit
			or character:GetAttribute(InspectConfig.PostureAttribute) == "Slide"
		state.movementBlocked = movementBlocked
		if state.busy then InspectMotion.Cancel(state.inspect, true)
		elseif movementBlocked then InspectMotion.Cancel(state.inspect, false) end
		local context = state.context
		context.airborne = humanoid.FloorMaterial == Enum.Material.Air
		context.inspectBlend += ((InspectMotion.IsActive(state.inspect) and 1 or 0) - context.inspectBlend)
			* (1 - math.exp(-settings.TransitionSpeed * math.max(0, dt)))
		local frame, animationFrame = Motion.Step(state.motion, camera.CFrame, dt, aiming, reloading, speed, settings,
			bodyAnimation, armAnimation, action, context)
		if InspectMotion.IsActive(state.inspect) then
			local pose = InspectMotion.Step(state.inspect, dt)
			frame = CFrame.new(pose.Position) * frame * pose.Rotation
		end
		if not Geometry.Place(state.visual, camera.CFrame, frame, settings, tuning.Pose.R6RotationOffset, animationFrame, weaponVisible) then
			deactivate(state)
			return
		end
		-- Publish a complete, safely placed model before hiding the real gun/arms.
		if state.visual.model.Parent ~= camera then state.visual.model.Parent = camera end
		state.active = true
		state.skinEffects.SetActive(true)
		state.skinEffects.Guard()
		state.visual.visibility.SetActive(true)
		state.visual.visibility.Guard()
		for _, part in ipairs(state.visual.originals) do
			if part.Parent then
				if state.hidden[part] == nil then state.hidden[part] = part.LocalTransparencyModifier end
				if part.LocalTransparencyModifier ~= 1 then part.LocalTransparencyModifier = 1 end
			end
		end
		retry = nil -- reset backoff only after a complete successful presentation update
	end

	function Viewmodel.Update(tool, tuning, allowed, aiming, reloading, dt, bodyAnimation, armAnimation, action, weaponVisible)
		if profileBegin then profileBegin(modelName) end
		local ok, failure = pcall(update, tool, tuning, allowed, aiming, reloading, dt, bodyAnimation, armAnimation, action, weaponVisible)
		if profileEnd then profileEnd() end
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
		if current and current.active and current.tool == tool then
			Viewmodel.InterruptInspect()
			if Motion.Kick then Motion.Kick(current.motion) end
		end
	end

	function Viewmodel.StartInspect(tool)
		if not Viewmodel.IsActive(tool) or current.busy or current.movementBlocked
			or current.activeSeconds < InspectConfig.EquipGraceSeconds or current.actionPause > 0 then return false end
		return InspectMotion.Start(current.inspect, inspectKind)
	end

	function Viewmodel.IsInspecting(tool)
		return Viewmodel.IsActive(tool) and InspectMotion.IsActive(current.inspect)
	end

	function Viewmodel.CancelInspect(immediate)
		if current then InspectMotion.Cancel(current.inspect, immediate == true) end
	end

	function Viewmodel.InterruptInspect()
		if current then
			InspectMotion.Cancel(current.inspect, true)
			current.actionPause = InspectConfig.AfterActionSeconds
		end
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
