-- Paste into Studio's CLIENT Command Bar during Play, with a revolver or knife equipped
-- in first person. Samples real engine state for two seconds. Read-only: no
-- persistent connections, model changes, character forces or velocity changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "Run this in the Client Command Bar during a Play session.")
local modules = ReplicatedStorage:FindFirstChild("Modules")
assert(modules and modules:FindFirstChild("RevolverConfig") and modules:FindFirstChild("RevolversInfo"), "Game modules are unavailable.")
local settings = require(modules.RevolverConfig).FirstPersonPhysics
assert(settings, "FirstPersonPhysics config is missing; sync the updated code and start a new Play session.")
local catalog = require(modules.RevolversInfo)
local knifeCatalog = modules:FindFirstChild("KnivesInfo") and require(modules.KnivesInfo) or {}
local reported = {}
local renderHumanoids = {}
local failures, ticks, modelTicks, checks = 0, 0, 0, 0
local maximumSpeed, maximumIdleSpeed, maximumStepSpeed = 0, 0, 0
local previousRoot, previousPosition

local function path(item)
	return item and item:GetFullName() or "nil"
end

local function flags(part)
	return string.format("%s [group=%s, Anchored=%s, CanCollide=%s, CanTouch=%s, CanQuery=%s, Massless=%s]",
		path(part), part.CollisionGroup, tostring(part.Anchored), tostring(part.CanCollide),
		tostring(part.CanTouch), tostring(part.CanQuery), tostring(part.Massless))
end

local function fail(key, message)
	if reported[key] then return end
	reported[key] = true
	failures += 1
	warn("[FirstPersonPhysicsCheck] " .. message)
end

local function liveReference(item, property, character)
	local ok, reference = pcall(function() return item[property] end)
	if ok and typeof(reference) == "Instance" and reference:IsDescendantOf(character) then
		fail(path(item) .. ":" .. property, "Viewmodel reference to live character: " .. path(item) .. "." .. property .. " -> " .. path(reference))
	end
end

local function sample(dt)
	ticks += 1
	local ready = ReplicatedStorage:GetAttribute(settings.ReadyAttribute)
	local groupExists = PhysicsService:IsCollisionGroupRegistered(settings.CollisionGroup)
	if ready ~= true then fail("ready", settings.ReadyAttribute .. "=" .. tostring(ready)) end
	if not groupExists then fail("group", "Collision group is missing: " .. settings.CollisionGroup) end
	if groupExists then
		for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
			if PhysicsService:CollisionGroupsAreCollidable(settings.CollisionGroup, group.name) then
				fail("group:" .. group.name, "Viewmodel collision mask still permits group " .. group.name)
			end
		end
	end

	local character, camera = player.Character, workspace.CurrentCamera
	if not character or not camera then fail("character", "Current character/camera unavailable"); return end
	local humanoid, root = character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
	local move = humanoid and humanoid.MoveDirection or Vector3.zero
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		local horizontal = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		maximumSpeed = math.max(maximumSpeed, horizontal)
		if move.Magnitude < 0.01 then maximumIdleSpeed = math.max(maximumIdleSpeed, horizontal) end
		if previousRoot == root and previousPosition and dt > 0 then
			local displacement = root.Position - previousPosition
			maximumStepSpeed = math.max(maximumStepSpeed, math.sqrt(displacement.X * displacement.X + displacement.Z * displacement.Z) / dt)
		end
		previousRoot, previousPosition = root, root.Position
		if ticks == 1 then
			print(string.format("[FirstPersonPhysicsCheck] start root=%s horizontalSpeed=%.3f MoveDirection=(%.3f, %.3f, %.3f) CameraSubject=%s",
				path(root), horizontal, move.X, move.Y, move.Z, path(camera.CameraSubject)))
		end
	end
	local characterParts = {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then table.insert(characterParts, item) end
	end
	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") and (catalog[tool.Name] or knifeCatalog[tool.Name]) then
			for _, part in ipairs(tool:GetDescendants()) do
				if part:IsA("BasePart") and (part.CanCollide or part.CanTouch or not part.Massless) then
					fail("tool:" .. path(part), "Live weapon has unsafe physics: " .. flags(part))
				end
				if part:IsA("FaceInstance") then
					local supported, modifier = pcall(function() return part.LocalTransparencyModifier end)
					if part.Transparency < 1 and (not supported or modifier < 1) then
						fail("face:" .. path(part), "Real weapon face remains visible in first person: " .. path(part))
					end
				end
			end
		end
	end
	local contents, modelCount = {}, 0
	for _, child in ipairs(camera:GetChildren()) do
		if (child.Name == "RevolverFirstPerson" or child.Name == "KnifeFirstPerson") and child:IsA("Model") then
			modelCount += 1
			for _, item in ipairs(child:GetDescendants()) do table.insert(contents, item) end
		end
	end
	if modelCount == 0 then fail("model", "Camera weapon model is absent; equip a revolver or knife and enter first person."); return end
	if modelCount > 1 then fail("duplicates", "Found " .. modelCount .. " camera viewmodels; old models may still be active.") end
	modelTicks += 1
	for _, item in ipairs(contents) do
		if item:IsA("BasePart") then
			if not item.Anchored or item.CanCollide or item.CanTouch or item.CanQuery or not item.Massless
				or item.CollisionGroup ~= settings.CollisionGroup then
				fail("visual:" .. path(item), "Unsafe viewmodel part: " .. flags(item))
			end
			local assembly = item.AssemblyRootPart
			if assembly and assembly:IsDescendantOf(character) then
				fail("assembly:" .. path(item), "Viewmodel belongs to live character assembly: " .. flags(item) .. " root=" .. path(assembly))
			end
			for _, actual in ipairs(characterParts) do
				checks += 1
				if item:CanCollideWith(actual) then
					fail("pair:" .. path(item) .. ":" .. path(actual), "Engine permits viewmodel/character contact: " .. flags(item) .. " <-> " .. flags(actual))
				end
			end
		elseif item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") or item:IsA("Light")
			or item:IsA("Fire") or item:IsA("Smoke") or item:IsA("Sparkles") then
			local muzzleFeedback = item:IsA("ParticleEmitter") and item:GetAttribute("FirstPersonShotEffect") == true
			if not muzzleFeedback then fail("effect:" .. path(item), "First-person weapon contains unwanted skin VFX: " .. path(item))
			elseif item.Enabled or item.Rate ~= 0 or item.Lifetime.Max > 0.15 then
				fail("shot:" .. path(item), "Camera muzzle feedback exceeds its bounded burst settings: " .. path(item))
			end
		elseif item:IsA("Humanoid") then
			if not renderHumanoids[item] then
				renderHumanoids[item] = true
				print("[FirstPersonPhysicsCheck] renderHumanoid=" .. path(item) .. " EvaluateStateMachine=" .. tostring(item.EvaluateStateMachine))
			end
			if item.EvaluateStateMachine then fail("humanoid:" .. path(item), "Viewmodel Humanoid can simulate: " .. path(item)) end
		elseif item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			for _, property in ipairs({"Part0", "Part1", "Attachment0", "Attachment1"}) do liveReference(item, property, character) end
		end
	end
end

print("[FirstPersonPhysicsCheck] Sampling for two seconds. Hold no movement keys to measure idle dragging.")
print("[FirstPersonPhysicsCheck] ready=" .. tostring(ReplicatedStorage:GetAttribute(settings.ReadyAttribute))
	.. " collisionGroup=" .. settings.CollisionGroup .. " registered=" .. tostring(PhysicsService:IsCollisionGroupRegistered(settings.CollisionGroup)))
local deadline = os.clock() + 2
repeat
	local dt = RunService.Heartbeat:Wait()
	sample(dt)
until os.clock() >= deadline
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local move = humanoid and humanoid.MoveDirection or Vector3.zero
print(string.format("[FirstPersonPhysicsCheck] Finished: %d ticks, %d model ticks, %d collision pairs checked, %d distinct failures. Max horizontalSpeed=%.3f, max idleSpeed=%.3f, max positionStepSpeed=%.3f; final MoveDirection=(%.3f, %.3f, %.3f)",
	ticks, modelTicks, checks, failures, maximumSpeed, maximumIdleSpeed, maximumStepSpeed, move.X, move.Y, move.Z))
if failures == 0 and modelTicks > 0 then
	print("[FirstPersonPhysicsCheck] PASS: viewmodel contacts/assembly references blocked, real weapon textures hidden, only bounded shot feedback present, and live weapon flags safe throughout this sample.")
end
