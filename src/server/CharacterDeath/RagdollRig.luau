-- Builds a script-free corpse while it is unparented; no live rig joints change.
local Rig = {}

local function limited(vector, maximum)
	local magnitude = vector.Magnitude
	if magnitude ~= magnitude or magnitude == math.huge then return Vector3.zero end
	return magnitude > maximum and vector.Unit * maximum or vector
end

local function jointSettings(name, config)
	for key, settings in pairs(config.Joints) do
		if key ~= "Default" and string.find(name, key, 1, true) then return settings end
	end
	return config.Joints.Default
end

local function strip(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("LuaSourceContainer") or item:IsA("Tool") or item:IsA("ForceField")
			or item:IsA("BillboardGui") or item:IsA("SurfaceGui") or item:IsA("Sound")
			or item:IsA("Animator") or item.Name == "Hitbox" or item.Name == "WeaponAttachments" then
			item:Destroy()
		elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
			item.Enabled = false
		end
	end
end

function Rig.Build(corpse, source, config)
	strip(corpse)
	local humanoid = corpse:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath, humanoid.RequiresNeck = false, false
		humanoid.EvaluateStateMachine, humanoid.AutoRotate = false, false
		humanoid.PlatformStand = true
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = corpse:FindFirstChild("HumanoidRootPart")
	local torso = corpse:FindFirstChild("Torso") or corpse:FindFirstChild("UpperTorso")
	if not root or not root:IsA("BasePart") or not torso or not torso:IsA("BasePart") then
		return nil -- unsupported/incomplete rig: leave the original death visible
	end
	local bodyParts, motion = {}, {}
	for _, item in ipairs(corpse:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored, item.CanTouch, item.CanQuery = false, false, false
			item.CollisionGroup = config.CollisionGroup
			item.CanCollide = item.Parent == corpse and item ~= root
			item.Massless = not item.CanCollide
			local original = source:FindFirstChild(item.Name)
			if item.Parent == corpse then
				bodyParts[item] = true
				motion[item] = {
					linear = limited(original and original:IsA("BasePart") and original.AssemblyLinearVelocity
						or Vector3.zero, config.MaxInheritedSpeed),
					angular = limited(original and original:IsA("BasePart") and original.AssemblyAngularVelocity
						or Vector3.zero, config.MaxInheritedAngularSpeed),
				}
			end
		end
	end
	local count = 0
	for _, joint in ipairs(corpse:GetDescendants()) do
		if joint:IsA("Motor6D") then
			local part0, part1 = joint.Part0, joint.Part1
			if bodyParts[part0] and bodyParts[part1] then
				if part0 == root or part1 == root then
					-- The invisible root follows the torso instead of becoming a loose weight.
					local weld = Instance.new("WeldConstraint")
					weld.Name, weld.Part0, weld.Part1, weld.Parent = "RagdollRoot", part0, part1, root
				else
					-- Coincident pivots preserve the death position, including posed arms.
					local pivot = ((part0.CFrame * joint.C0).Position + (part1.CFrame * joint.C1).Position) / 2
					local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
					a0.Name, a1.Name = "Ragdoll_" .. joint.Name .. "_0", "Ragdoll_" .. joint.Name .. "_1"
					a0.CFrame = CFrame.new(part0.CFrame:PointToObjectSpace(pivot)) * joint.C0.Rotation
					a1.CFrame = CFrame.new(part1.CFrame:PointToObjectSpace(pivot)) * joint.C1.Rotation
					a0.Parent, a1.Parent = part0, part1
					local settings = jointSettings(joint.Name, config)
					local socket = Instance.new("BallSocketConstraint")
					socket.Name, socket.Attachment0, socket.Attachment1 = "Ragdoll_" .. joint.Name, a0, a1
					socket.LimitsEnabled, socket.TwistLimitsEnabled = true, true
					socket.UpperAngle = settings.UpperAngle
					socket.TwistLowerAngle, socket.TwistUpperAngle = settings.TwistLowerAngle, settings.TwistUpperAngle
					socket.MaxFrictionTorque, socket.Restitution = settings.Friction, 0
					socket.Parent = part0
					count += 1
				end
			end
			joint:Destroy() -- also remove grips whose Tools were stripped
		end
	end
	if count == 0 then return nil end
	root.Transparency = 1
	corpse.PrimaryPart = root
	return torso, motion
end

function Rig.Start(corpse, torso, config, impact, motion)
	-- Ownership is assigned only after the finished mechanism enters Workspace.
	local canSet, reason = torso:CanSetNetworkOwnership()
	if canSet then torso:SetNetworkOwner(nil) else warn("[Ragdoll] Ownership: " .. tostring(reason)) end
	-- Assemblies become active in Workspace. Set velocities after splitting the
	-- motors; a welded accessory must not overwrite the body's inherited motion.
	local root = corpse.PrimaryPart
	for part, velocity in pairs(motion) do
		if part ~= root then
			part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = velocity.linear, velocity.angular
		end
	end
	local tuning = config.Impact[impact and impact.Kind] or config.Impact.Default
	local direction = impact and impact.Direction or torso.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.001 then
		local forward = torso.CFrame.LookVector
		direction = Vector3.new(forward.X, 0, forward.Z)
		if direction.Magnitude < 0.001 then direction = Vector3.new(0, 0, -1) end
	end
	direction = direction.Unit
	local up = Vector3.new(0, 1, 0)
	local velocity = direction * tuning.Speed + up * tuning.Lift
	local pushed = {}
	for part in pairs(motion) do
		if part ~= root then
			local assembly = part.AssemblyRootPart or part
			if not pushed[assembly] then
				pushed[assembly] = true
				-- Nudge each body assembly equally; a torso-only impulse gets
				-- diluted by the other limbs and barely moves an idle character.
				part:ApplyImpulse(velocity * part.AssemblyMass)
			end
		end
	end
	-- The world-space axis tips the top of the torso AWAY from the attacker:
	-- front/back hits pitch it, side hits roll it, with no added yaw spin.
	torso:ApplyAngularImpulse(up:Cross(direction) * tuning.TiltImpulse * torso.AssemblyMass)
end

function Rig.HideOriginal(character)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency, item.CanCollide, item.CanTouch, item.CanQuery = 1, false, false, false
		elseif item:IsA("Decal") or item:IsA("Texture") then item.Transparency = 1
		elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") or item:IsA("ParticleEmitter")
			or item:IsA("Trail") or item:IsA("Beam") then item.Enabled = false
		end
	end
end

return Rig
