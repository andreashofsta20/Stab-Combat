-- Camera-only weapon geometry. Never clone live controllers, joints or effects.
local Geometry = {}
local PhysicsConfig = require(game:GetService("ReplicatedStorage").Modules.RevolverConfig).FirstPersonPhysics

local function skinEffect(item)
	return item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail")
		or item:IsA("Light") or item:IsA("Fire") or item:IsA("Smoke") or item:IsA("Sparkles")
end

local function renderable(item)
	return item:IsA("BasePart") or item:IsA("DataModelMesh") or item:IsA("FaceInstance")
		or item:IsA("SurfaceAppearance") or item:IsA("Attachment")
		or item:IsA("Model") or item:IsA("Folder") or item:IsA("Shirt")
		or item:IsA("BodyColors") or item:IsA("CharacterMesh")
end

local function cloneVisual(source, sourceMap, includeParts)
	local changed = {}
	local function include(item, allowed)
		if item.Archivable ~= allowed then changed[item] = item.Archivable; item.Archivable = allowed end
	end
	include(source, true)
	-- Copy one appearance object at a time so unsafe children are never cloned,
	-- including nonarchivable appearance and state held by live controllers.
	local children = source:GetChildren()
	for _, item in ipairs(children) do include(item, false) end
	local ok, clone = pcall(function() return source:Clone() end)
	for item, previous in pairs(changed) do item.Archivable = previous end
	if not ok or not clone then error("Cannot clone " .. source.Name) end
	if clone:IsA("Model") then clone.PrimaryPart = nil end
	sourceMap[source] = clone
	local copied, failure = pcall(function()
		for _, child in ipairs(children) do
			if renderable(child) and (includeParts or not child:IsA("BasePart")) then
				cloneVisual(child, sourceMap, includeParts).Parent = clone
			end
		end
	end)
	if not copied then clone:Destroy(); error(failure, 0) end
	return clone
end

local function prepare(part)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.CastShadow, part.LocalTransparencyModifier = false, 0
	part.Massless = true
	part.CollisionGroup = PhysicsConfig.CollisionGroup
	part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
end

local function thin(vector, scale)
	return Vector3.new(vector.X * scale, vector.Y, vector.Z * scale)
end

local function fileMesh(item)
	return item:IsA("SpecialMesh") and item.MeshType == Enum.MeshType.FileMesh
		or item:IsA("FileMesh") and not item:IsA("SpecialMesh")
end

local partAppearance = {
	Size = true, Color = true, BrickColor = true, Material = true, MaterialVariant = true,
	Transparency = true, Reflectance = true, Shape = true, UsePartColor = true,
	MeshId = true, MeshContent = true, TextureID = true, TextureContent = true,
	DoubleSided = true, RenderFidelity = true,
}
local ignoredAppearance = {
	Parent = true, Archivable = true, ClassName = true, Name = true,
	LocalTransparencyModifier = true, PrimaryPart = true, Attributes = true,
}

local function mirrorAppearance(source, copy, property, armScale)
	if ignoredAppearance[property] or not source.Parent or not copy.Parent then return end
	if source:IsA("BasePart") and not partAppearance[property] then return end
	if source:IsA("Model") or source:IsA("Folder") then return end
	-- Attachment.CFrame is local appearance data; BasePart.CFrame is placed below.
	-- Appearance classes contain values, never external part/joint references.
	local value = source[property]
	if armScale then
		if source:IsA("BasePart") and property == "Size" then value = thin(value, armScale)
		elseif source:IsA("DataModelMesh") and fileMesh(source)
			and (property == "Scale" or property == "Offset") then value = thin(value, armScale) end
	end
	-- Native read-only notifications and properties unsupported by an older
	-- renderer must not interrupt equip or the shared presentation loop.
	pcall(function() copy[property] = value end)
	if armScale and source:IsA("SpecialMesh") and property == "MeshType" then
		local scale = fileMesh(source) and armScale or 1
		copy.Scale, copy.Offset = thin(source.Scale, scale), thin(source.Offset, scale)
	end
end

function Geometry.Create(character, tool, settings, modelName)
	local right, left, torso = character:FindFirstChild("Right Arm"), character:FindFirstChild("Left Arm"), character:FindFirstChild("Torso")
	local humanoid, handle = character:FindFirstChildOfClass("Humanoid"), tool:FindFirstChild("Handle")
	if not right or not left or not torso or not humanoid or not handle or not handle:IsA("BasePart") then return nil end
	local model = Instance.new("Model")
	model.Name = modelName or "RevolverFirstPerson"
	local appearanceConnections = {}
	local ok, result = pcall(function()
		local originals, effects = {}, {}
		for _, item in ipairs(tool:GetDescendants()) do
			if item:IsA("BasePart") then table.insert(originals, item) end
			if skinEffect(item) then table.insert(effects, {source = item}) end
		end
		if #originals > settings.MaxWeaponParts then error("Weapon exceeds first-person part budget") end
		table.insert(originals, right); table.insert(originals, left)
		local weapon = Instance.new("Model"); weapon.Name, weapon.Parent = "Weapon", model
		local sourceMap, armScales = {}, {}
		-- Never clone the equipped Tool itself or its owner/equip controller state.
		for _, item in ipairs(tool:GetChildren()) do
			if renderable(item) then
				cloneVisual(item, sourceMap, true).Parent = weapon
			end
		end
		local root = weapon:FindFirstChild("Handle")
		if not root or not root:IsA("BasePart") then error("Weapon has no cloned Handle") end
		local pieces, base = {}, handle.CFrame:Inverse()
		for source, copy in pairs(sourceMap) do
			if copy:IsA("BasePart") then
				prepare(copy)
				table.insert(pieces, {part = copy, source = source, offset = base * source.CFrame})
			end
		end
		local arms = {}
		for _, original in ipairs({right, left}) do
			local armMap = {}
			local arm = cloneVisual(original, armMap, false); arm.Parent = model; prepare(arm)
			local scale = settings.ArmThicknessScale
			arm.Size = thin(original.Size, scale)
			for source, copy in pairs(armMap) do
				sourceMap[source], armScales[source] = copy, scale
				if source:IsA("DataModelMesh") and fileMesh(source) then
					copy.Scale, copy.Offset = thin(source.Scale, scale), thin(source.Offset, scale)
				end
			end
			table.insert(arms, arm)
		end
		-- A minimal hidden R6 shell lets classic shirts and body meshes render.
		local shell = {}
		for _, name in ipairs({"Torso", "Head", "HumanoidRootPart"}) do
			local original = character:FindFirstChild(name)
			if original and original:IsA("BasePart") then
				local part = Instance.new("Part")
				part.Name, part.Size, part.Transparency = name, original.Size, 1
				prepare(part); part.Parent = model
				table.insert(shell, part)
			end
		end
		-- A live Humanoid clone can keep Torso/RootPart references to the player.
		-- Create a fresh, inert clothing renderer and configure it before parenting.
		local hum = Instance.new("Humanoid")
		hum.RigType = Enum.HumanoidRigType.R6
		hum.BreakJointsOnDeath, hum.RequiresNeck, hum.EvaluateStateMachine, hum.AutoRotate = false, false, false, false
		hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0
		hum.DisplayDistanceType, hum.Parent = Enum.HumanoidDisplayDistanceType.None, model
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Shirt") or item:IsA("BodyColors") or item:IsA("CharacterMesh") then
				cloneVisual(item, sourceMap, false).Parent = model
			end
		end
		local grip = right:FindFirstChild("RightGrip")
		local gripFrame = grip and grip:IsA("JointInstance") and grip.Part0 == right and grip.Part1 == handle
			and grip.C0 * grip.C1:Inverse() or CFrame.new(0, -right.Size.Y / 2, 0) * tool.Grip:Inverse()
		local safeParts = {}
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") then prepare(item); table.insert(safeParts, item) end
		end
		arms[2].LocalTransparencyModifier = settings.SupportArmEnabled == false and 1 or 0
		for source, copy in pairs(sourceMap) do
			if not source:IsA("Model") and not source:IsA("Folder") then
				table.insert(appearanceConnections, source.Changed:Connect(function(property)
					mirrorAppearance(source, copy, property, armScales[source])
				end))
			end
		end
		return {model = model, weapon = weapon, right = arms[1], left = arms[2], pieces = pieces, shell = shell,
			grip = gripFrame, sourceHandle = handle, originals = originals, humanoid = humanoid,
			renderHumanoid = hum, safeParts = safeParts, effects = effects,
			sourceMap = sourceMap, copyMap = sourceMap, appearanceConnections = appearanceConnections}
	end)
	if not ok then
		for _, connection in ipairs(appearanceConnections) do connection:Disconnect() end
		model:Destroy(); error(result)
	end
	return result
end

function Geometry.Guard(visual)
	-- Use the cached parts, never a render-time descendant scan. The group mask
	-- remains non-colliding even if native rig initialization toggles CanCollide.
	for _, part in ipairs(visual.safeParts) do
		if not part.Anchored then part.Anchored = true end
		if part.CanCollide then part.CanCollide = false end
		if part.CanTouch then part.CanTouch = false end
		if part.CanQuery then part.CanQuery = false end
		if not part.Massless then part.Massless = true end
		if part.CollisionGroup ~= PhysicsConfig.CollisionGroup then part.CollisionGroup = PhysicsConfig.CollisionGroup end
	end
	if visual.renderHumanoid.EvaluateStateMachine then visual.renderHumanoid.EvaluateStateMachine = false end
end

function Geometry.Place(visual, camera, frame, settings, pose, animationFrame, weaponVisible)
	local right = camera * frame * CFrame.Angles(math.pi / 2, 0, 0)
		* CFrame.Angles(math.rad(pose[1]), math.rad(pose[2]), math.rad(pose[3]))
	visual.right.CFrame = right
	local gun = right * visual.grip
	local sourceBase = visual.sourceHandle.Parent and visual.sourceHandle.CFrame:Inverse()
	local hidden = weaponVisible == false and 1 or 0
	for _, entry in ipairs(visual.pieces) do
		-- Skin scripts can settle/animate parts after equip. Refresh their actual
		-- Handle-relative frame so the clone does not retain a stale snapshot.
		if sourceBase and entry.source.Parent then entry.offset = sourceBase * entry.source.CFrame end
		entry.part.CFrame = gun * entry.offset
		if entry.part.LocalTransparencyModifier ~= hidden then entry.part.LocalTransparencyModifier = hidden end
	end
	local supportVisible = settings.SupportArmEnabled ~= false
	visual.left.LocalTransparencyModifier = supportVisible and 0 or 1
	if supportVisible then
		local shoulder = (camera * (animationFrame or CFrame.identity)):PointToWorldSpace(Vector3.new(table.unpack(settings.LeftShoulder)))
		local hand = right:PointToWorldSpace(Vector3.new(table.unpack(settings.SupportHandOffset)))
		local vector = hand - shoulder
		if vector.Magnitude > 1e-5 then
			local up = camera:VectorToWorldSpace(Vector3.new(0, 1, 0))
			if math.abs(vector.Unit:Dot(up)) > 0.98 then up = camera:VectorToWorldSpace(Vector3.new(1, 0, 0)) end
			local center = hand - vector.Unit * visual.left.Size.Y / 2
			visual.left.CFrame = CFrame.lookAt(center, hand, up) * CFrame.Angles(math.pi / 2, 0, 0)
		end
	end
	for _, part in ipairs(visual.shell) do part.CFrame = camera end
end

function Geometry.Destroy(visual)
	for _, connection in ipairs(visual.appearanceConnections) do connection:Disconnect() end
	table.clear(visual.appearanceConnections)
	visual.model:Destroy()
end

return Geometry
