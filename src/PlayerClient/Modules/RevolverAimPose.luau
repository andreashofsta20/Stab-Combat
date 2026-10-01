local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local Catalog = require(ReplicatedStorage.Modules.RevolversInfo)
local Math = require(ReplicatedStorage.Modules.RevolverPoseMath)
local Pose = {}
local localPlayer = Players.LocalPlayer
local states = {}
local initialized = false
local remote, localSession
local sequence, lastSent, lastSample = 0, 0, 0

local function time() return workspace:GetServerTimeNow() end
local function getTool(character)
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and Catalog[child.Name] then return child end
	end
	return nil
end

local function jointData(joint)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.Part1, joint.C0, joint.C1
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
			return a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
		end
	end
	return nil
end

local function restore(state)
	for _, entry in ipairs(state.joints or {}) do
		local joint = entry.joint
		if joint.Parent and entry.applied and joint.Transform == entry.applied then
			joint.Transform = entry.base
		end
		entry.applied = nil
	end
end

local function getState(player, character)
	local state = states[player]
	if not state or state.character ~= character then
		if state then restore(state) end
		state = { character = character, pitch = 0, yaw = 0, targetPitch = 0, targetYaw = 0,
			weight = 0, recoil = 0, updated = 0, joints = {}, nextBind = 0 }
		states[player] = state
	end
	return state
end

local function bindJoints(state)
	local first = state.joints[1]
	local complete = first and first.shoulder and (not first.r15 or #state.joints >= 3)
	for _, entry in ipairs(state.joints) do if not entry.joint.Parent then complete = false end end
	if complete then return end
	if time() < state.nextBind then return end
	state.nextBind = time() + 0.25
	state.joints = {}
	for _, joint in ipairs(state.character:GetDescendants()) do
		if not joint:IsA("Motor6D") and not joint:IsA("AnimationConstraint") then continue end
		local part0, part1 = jointData(joint)
		if not part0 or not part1 then continue end
		local shoulder = part1.Name == "Right Arm" or part1.Name == "RightUpperArm"
		if shoulder or part1.Name == "RightLowerArm" or part1.Name == "RightHand" then
			local entry = { joint = joint, base = joint.Transform, shoulder = shoulder, part0 = part0,
				r15 = part1.Name ~= "Right Arm" }
			if shoulder then table.insert(state.joints, 1, entry) else table.insert(state.joints, entry) end
		end
	end
end

function Pose.SetSession(session)
	if localSession == session then return end
	localSession, sequence, lastSent = session, 0, 0
end

function Pose.SetLocalAim(tool, aimPoint, reloading)
	local character = localPlayer.Character
	if not character then return end
	local state = getState(localPlayer, character)
	state.active, state.reloading = tool ~= nil, reloading == true
	if not tool then return end
	if state.tool ~= tool then
		state.tool, state.tuning = tool, Config.Get(tool.Name)
		state.nextBind = 0
	end
	bindJoints(state)
	local shoulder = state.joints[1]
	if aimPoint and shoulder and shoulder.shoulder then
		local _, _, c0 = jointData(shoulder.joint)
		local torso = shoulder.part0.CFrame
		local origin = torso:PointToWorldSpace(c0.Position)
		local direction = torso:VectorToObjectSpace(aimPoint - origin)
		state.targetPitch, state.targetYaw = Math.Angles(direction.X, direction.Y, direction.Z, state.tuning.Pose)
	end
	state.updated = time()
	if remote and localSession and state.tuning.Pose.Enabled and time() - lastSent >= 1 / Config.PoseReplication.SendHz then
		lastSent = time(); sequence += 1
		remote:FireServer(localSession, sequence, state.targetPitch, state.targetYaw)
	end
end

function Pose.SampleCursor(tool, ray, reloading)
	if not tool or not ray then Pose.SetLocalAim(nil); return end
	if time() - lastSample < 1 / Config.PoseReplication.SampleHz then return end
	lastSample = time()
	local ignore = { localPlayer.Character }
	for _, other in ipairs(Players:GetPlayers()) do
		local box = other.Character and other.Character:FindFirstChild("Hitbox")
		if box then table.insert(ignore, box) end
	end
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater = Enum.RaycastFilterType.Exclude, ignore, true
	local state = getState(localPlayer, localPlayer.Character)
	local tuning = state.tool == tool and state.tuning or Config.Get(tool.Name)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * tuning.Range, params)
	Pose.SetLocalAim(tool, hit and hit.Position or ray.Origin + ray.Direction * tuning.Range, reloading)
end

function Pose.Kick(player, character, weapon)
	if not character then return end
	local state = getState(player, character)
	local settings = Config.Get(weapon).Pose
	state.recoil = math.min(state.recoil + math.rad(settings.RecoilDegrees), math.rad(20))
end

function Pose.ResetLocal()
	local state = states[localPlayer]
	if state then restore(state); states[localPlayer] = nil end
	Pose.SetSession(nil)
	lastSample = 0
end

function Pose.Init(aimRemote)
	if initialized then return end
	initialized, remote = true, aimRemote
	remote.OnClientEvent:Connect(function(userId, character, session, packetSequence, pitch, yaw, reloading, timestamp)
		if userId == localPlayer.UserId then return end
		local player = Players:GetPlayerByUserId(userId)
		if not player or player.Character ~= character then return end
		local tool = getTool(character)
		if not tool then return end
		local state = getState(player, character)
		if state.remoteSession ~= session then state.remoteSession, state.poseSequence = session, 0 end
		local tuning = Config.Get(tool.Name)
		if not Math.AcceptPacket(state, packetSequence, pitch, yaw, tuning.Pose)
			or timestamp < state.updated then return end
		state.tool, state.tuning, state.reloading = tool, tuning, reloading
		state.targetPitch, state.targetYaw, state.updated = pitch, yaw, timestamp
	end)
	Players.PlayerRemoving:Connect(function(player)
		if states[player] then restore(states[player]); states[player] = nil end
	end)
	-- Remove last frame's layer before Animator evaluation. This also prevents
	-- accumulation if Animator skips an offscreen joint or an animation stops.
	RunService.PreAnimation:Connect(function()
		for _, state in pairs(states) do restore(state) end
	end)
	RunService.PreSimulation:Connect(function(dt)
		for player, state in pairs(states) do
			local character = state.character
			if player.Character ~= character or not character.Parent then
				restore(state); states[player] = nil; continue
			end
			local tool = getTool(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local tuning = state.tuning
			if not tuning then continue end
			local settings = tuning.Pose
			local alive = humanoid and humanoid.Health > 0
			local fresh = time() - state.updated <= Config.PoseReplication.TimeoutMs / 1000
			local authoredReload = state.reloading and tuning.Effects.ReloadAnimationId ~= ""
			local active = tool == state.tool and alive and settings.Enabled and fresh and not authoredReload
			if player == localPlayer then active = active and state.active end
			state.weight += ((active and 1 or 0) - state.weight) * Math.Alpha(settings.BlendSpeed, dt)
			state.pitch += (state.targetPitch - state.pitch) * Math.Alpha(settings.FollowSpeed, dt)
			state.yaw += (state.targetYaw - state.yaw) * Math.Alpha(settings.FollowSpeed, dt)
			state.recoil *= 1 - Math.Alpha(settings.RecoilRecovery, dt)
			if state.weight < 0.001 then continue end
			bindJoints(state)
			for _, entry in ipairs(state.joints) do
				local joint = entry.joint
				if not joint.Parent then continue end
				local _, _, c0, c1 = jointData(joint)
				if not c0 then continue end
				local target = CFrame.identity
				if entry.shoulder then
					local offset = entry.r15 and settings.R15RotationOffset or settings.R6RotationOffset
					local pitch = math.clamp(state.pitch + state.recoil, math.rad(-85), math.rad(85))
					target = Math.ShoulderTransform(c0, c1, pitch, state.yaw, offset)
				end
				entry.base = joint.Transform
				entry.applied = entry.base:Lerp(target, state.weight)
				joint.Transform = entry.applied
			end
		end
	end)
end

return Pose
