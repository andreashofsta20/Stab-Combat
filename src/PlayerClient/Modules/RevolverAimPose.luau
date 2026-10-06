local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local Catalog = require(ReplicatedStorage.Modules.RevolversInfo)
local Math = require(ReplicatedStorage.Modules.RevolverPoseMath)
local Raycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)
local Pose = {}
local localPlayer = Players.LocalPlayer
local states = {}
local initialized = false
local remote, localSession
local sequence, lastSent, lastSample = 0, 0, 0
local lastPitch, lastYaw, lastAiming, lastReloading
local cursorParams, filterCharacter, nextFilterRefresh = nil, nil, 0

local function time() return workspace:GetServerTimeNow() end
local function getTool(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and Catalog[child.Name] then return child end
	end
	return nil
end

local function restore(state)
	for _, entry in ipairs(state.joints) do
		local joint = entry.joint
		if joint.Parent and entry.applied and joint.Transform == entry.applied then joint.Transform = entry.base end
		entry.applied = nil
	end
end

local function getState(player, character)
	local state = states[player]
	if not state or state.character ~= character then
		if state then restore(state) end
		state = { character = character, humanoid = character:FindFirstChildOfClass("Humanoid"), head = character:FindFirstChild("Head"),
			pitch = 0, yaw = 0, targetPitch = 0, targetYaw = 0, weight = 0, aimWeight = 0,
			recoil = 0, updated = 0, joints = {}, nextBind = 0 }
		states[player] = state
	end
	return state
end

local function bindJoints(state)
	if #state.joints == 2 then
		local right, left = state.joints[1], state.joints[2]
		if right.joint.Parent and left.joint.Parent and right.arm.Parent and left.arm.Parent then return end
	end
	if time() < state.nextBind then return end
	state.nextBind = time() + 0.25
	restore(state)
	table.clear(state.joints)
	local torso = state.character:FindFirstChild("Torso")
	if not torso then return end -- R6 only; no descendant scans or extra limb solvers
	for _, name in ipairs({ "Right Shoulder", "Left Shoulder" }) do
		local joint = torso:FindFirstChild(name)
		if not joint or not joint:IsA("Motor6D") or joint.Part0 ~= torso or not joint.Part1 then return end
		table.insert(state.joints, { joint = joint, torso = torso, arm = joint.Part1,
			c0 = joint.C0, c1 = joint.C1, base = joint.Transform })
	end
end

local function setTool(state, tool)
	if state.tool ~= tool then
		state.tool, state.tuning = tool, Config.Get(tool.Name)
		state.rightOffset = Vector3.new(table.unpack(state.tuning.Aim.RightArmOffset))
		state.supportOffset = Vector3.new(table.unpack(state.tuning.Aim.SupportHandOffset))
		state.nextBind = 0
	end
end

function Pose.SetSession(session)
	if localSession == session then return end
	localSession, sequence, lastSent = session, 0, 0
	lastPitch, lastYaw, lastAiming, lastReloading = nil, nil, nil, nil
end

function Pose.SetLocalAim(tool, aimPoint, reloading, aiming)
	local character = localPlayer.Character
	if not character then return end
	if not tool and not states[localPlayer] then return end
	local state = getState(localPlayer, character)
	state.active, state.reloading, state.aiming = tool ~= nil, reloading == true, aiming == true
	if not tool then return end
	setTool(state, tool)
	bindJoints(state)
	local shoulder = state.joints[1]
	if aimPoint and shoulder then
		local torso = shoulder.torso.CFrame
		local origin = torso:PointToWorldSpace(shoulder.c0.Position)
		local direction = torso:VectorToObjectSpace(aimPoint - origin)
		state.targetPitch, state.targetYaw = Math.Angles(direction.X, direction.Y, direction.Z, state.tuning.Pose)
	end
	local now = time()
	state.updated = now
	local limits = Config.PoseReplication
	local transition = lastAiming ~= state.aiming or lastReloading ~= state.reloading
	local threshold = math.rad(limits.AngleThresholdDegrees)
	local changed = lastPitch == nil or math.abs(state.targetPitch - lastPitch) >= threshold
		or math.abs(state.targetYaw - lastYaw) >= threshold
	if remote and localSession and state.tuning.Pose.Enabled and (transition
		or (now - lastSent >= 1 / limits.SendHz and (changed or now - lastSent >= limits.KeepAliveMs / 1000))) then
		lastSent = now; sequence += 1
		lastPitch, lastYaw, lastAiming, lastReloading = state.targetPitch, state.targetYaw, state.aiming, state.reloading
		remote:FireServer(localSession, sequence, state.targetPitch, state.targetYaw, state.aiming)
	end
end

function Pose.SampleCursor(tool, ray, reloading, aiming)
	if not tool or not ray then Pose.SetLocalAim(nil); return end
	local now = time()
	local state = getState(localPlayer, localPlayer.Character)
	local transition = state.aiming ~= (aiming == true) or state.reloading ~= (reloading == true)
	if not transition and now - lastSample < 1 / Config.PoseReplication.SampleHz then return end
	lastSample = now
	setTool(state, tool)
	bindJoints(state)
	if not cursorParams then
		cursorParams = RaycastParams.new()
		cursorParams.FilterType, cursorParams.IgnoreWater = Enum.RaycastFilterType.Exclude, true
	end
	-- Reuse params; rebuild the short ignore list four times/sec, not every sample.
	if filterCharacter ~= localPlayer.Character or now >= nextFilterRefresh then
		filterCharacter, nextFilterRefresh = localPlayer.Character, now + 0.25
		local ignore = { filterCharacter }
		for _, other in ipairs(Players:GetPlayers()) do
			local box = other.Character and other.Character:FindFirstChild("Hitbox")
			if box then table.insert(ignore, box) end
		end
		cursorParams.FilterDescendantsInstances = RagdollQuery.Exclude(ignore)
	end
	-- Sample the full cursor ray, matching gameplay even for rear targets
	-- between the camera and character. The posed barrel never moves this ray.
	local origin = Raycast.GetAimOrigin(ray.Origin)
	local hit = workspace:Raycast(origin, ray.Direction * state.tuning.Range, cursorParams)
	local shoulder = state.joints[1]
	local shoulderOrigin = shoulder and shoulder.torso.CFrame:PointToWorldSpace(shoulder.c0.Position)
	local point = hit and (not shoulderOrigin or (hit.Position - shoulderOrigin).Magnitude >= state.tuning.Pose.MinAimDistance)
		and hit.Position or origin + ray.Direction * state.tuning.Range
	Pose.SetLocalAim(tool, point, reloading, aiming)
end

function Pose.Kick(player, character, weapon)
	if not character then return end
	local state = getState(player, character)
	local settings = state.tuning and state.tool.Name == weapon and state.tuning.Pose or Config.Get(weapon).Pose
	state.recoil = math.min(state.recoil + math.rad(settings.RecoilDegrees), math.rad(20))
end

function Pose.ResetLocal()
	local state = states[localPlayer]
	if state then restore(state); states[localPlayer] = nil end
	Pose.SetSession(nil)
	lastSample, filterCharacter = 0, nil
end

function Pose.GetLocalAnimation()
	local state = states[localPlayer]
	if not state or not state.active or state.character ~= localPlayer.Character then return nil, nil end
	local rootJoint = state.rootJoint
	if not rootJoint or not rootJoint.Parent then
		local root = state.character:FindFirstChild("HumanoidRootPart")
		rootJoint = root and root:FindFirstChild("RootJoint")
		state.rootJoint = rootJoint
	end
	local body
	if rootJoint and rootJoint:IsA("Motor6D") and rootJoint.Part0 and rootJoint.Part1 then
		local basis = rootJoint.C0.Rotation
		body = basis * rootJoint.Transform * basis:Inverse()
	end
	local right = state.joints[1]
	local arm
	if right and right.joint.Parent then
		local basis = right.c0.Rotation
		-- PreSimulation saves this before applying the cursor/ADS pose, avoiding
		-- a feedback loop through the already aimed shoulder.
		arm = basis * right.base * basis:Inverse()
	end
	return body, arm
end

function Pose.Init(aimRemote)
	if initialized then return end
	initialized, remote = true, aimRemote
	remote.OnClientEvent:Connect(function(userId, character, session, packetSequence, pitch, yaw, aiming, reloading, timestamp)
		if userId == localPlayer.UserId then return end
		local player = Players:GetPlayerByUserId(userId)
		if not player or player.Character ~= character then return end
		local state = getState(player, character)
		local tool = state.tool and state.tool.Parent == character and state.tool or getTool(character)
		if not tool then return end
		setTool(state, tool)
		if state.remoteSession ~= session then state.remoteSession, state.poseSequence = session, 0 end
		if type(aiming) ~= "boolean" or type(timestamp) ~= "number" or timestamp ~= timestamp
			or math.abs(timestamp) == math.huge or time() - timestamp > Config.PoseReplication.TimeoutMs / 1000
			or timestamp < state.updated or not Math.AcceptPacket(state, packetSequence, pitch, yaw, state.tuning.Pose, aiming) then return end
		state.aiming, state.reloading = aiming, reloading
		state.targetPitch, state.targetYaw, state.updated = pitch, yaw, timestamp
	end)
	Players.PlayerRemoving:Connect(function(player)
		if states[player] then restore(states[player]); states[player] = nil end
	end)
	-- Restore before Animator; apply after Animator. Never change C0/C1 or stop
	-- movement tracks. These transforms are cosmetic and don't replicate themselves.
	RunService.PreAnimation:Connect(function()
		for _, state in pairs(states) do restore(state) end
	end)
	RunService.PreSimulation:Connect(function(dt)
		local now = time()
		for player, state in pairs(states) do
			local character, tuning = state.character, state.tuning
			if player.Character ~= character or not character.Parent or character:GetAttribute("Ragdolled") == true then
				restore(state); states[player] = nil; continue
			end
			if not tuning then states[player] = nil; continue end
			local settings = tuning.Pose
			local alive = state.humanoid and state.humanoid.Health > 0
			local fresh = now - state.updated <= Config.PoseReplication.TimeoutMs / 1000
			local authoredReload = state.reloading and tuning.Effects.ReloadAnimationId ~= ""
			local active = state.tool.Parent == character and alive and settings.Enabled and fresh and not authoredReload
			if player == localPlayer then active = active and state.active end
			state.weight += ((active and 1 or 0) - state.weight) * Math.Alpha(settings.BlendSpeed, dt)
			state.aimWeight += ((active and state.aiming and tuning.Aim.Enabled and 1 or 0) - state.aimWeight) * Math.Alpha(tuning.Aim.PoseBlendSpeed, dt)
			if state.weight < 0.001 then
				if not active then states[player] = nil end
				continue
			end
			state.pitch += (state.targetPitch - state.pitch) * Math.Alpha(settings.FollowSpeed, dt)
			state.yaw += (state.targetYaw - state.yaw) * Math.Alpha(settings.FollowSpeed, dt)
			state.recoil *= 1 - Math.Alpha(settings.RecoilRecovery, dt)
			bindJoints(state)
			local right, left = state.joints[1], state.joints[2]
			if not right or not right.joint.Parent then continue end
			local pitch = math.clamp(state.pitch + state.recoil, math.rad(-85), math.rad(85))
			local target = Math.ShoulderTransform(right.c0, right.c1, pitch, state.yaw,
				settings.R6RotationOffset, state.rightOffset * state.aimWeight)
			right.base = right.joint.Transform
			right.applied = right.base:Lerp(target, state.weight)
			right.joint.Transform = right.applied
			if left and left.joint.Parent and state.aimWeight > 0.001 then
				local armFrame = right.c0 * right.applied * right.c1:Inverse()
				local support = armFrame:PointToWorldSpace(state.supportOffset)
				local goal = Math.SupportTransform(left.c0, left.c1, support, left.arm.Size.Y)
				left.base = left.joint.Transform
				left.applied = left.base:Lerp(goal, state.weight * state.aimWeight)
				left.joint.Transform = left.applied
			end
		end
	end)
end

return Pose
