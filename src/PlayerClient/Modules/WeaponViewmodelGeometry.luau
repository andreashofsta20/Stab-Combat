-- Camera-only weapon geometry. Never clone live controllers, joints or effects.
local Geometry = {}
local Visibility = require(script.Parent.WeaponViewmodelVisibility)
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

function Geometry.IsVisual(item)
	return renderable(item) and not item:IsA("Model") and not item:IsA("Folder")
		or skinEffect(item)
end

local function gripFrame(right, handle)
	local grip = right:FindFirstChild("RightGrip")
	if not grip or not grip:IsA("JointInstance") or grip.Part0 ~= right or grip.Part1 ~= handle then return nil end
	local transform = grip:IsA("Motor6D") and grip.Transform or CFrame.identity
	return grip.C0 * transform * grip.C1:Inverse()
end

local function cloneVisual(source, sourceMap, includeParts, budget)
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
		if budget then budget(source) end
		for _, child in ipairs(children) do
			if renderable(child) and (includeParts or not child:IsA("BasePart")) then
				cloneVisual(child, sourceMap, includeParts, budget).Parent = clone
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

function Geometry.IsAppearanceProperty(source, property)
	return not ignoredAppearance[property] and (not source:IsA("BasePart") or partAppearance[property] == true)
		and not source:IsA("Model") and not source:IsA("Folder")
end

local function mirrorAppearance(source, copy, property, armScale, visibility)
	if ignoredAppearance[property] or not source.Parent or not copy.Parent then return end
	if source:IsA("BasePart") and not partAppearance[property] then return end
	if source:IsA("Model") or source:IsA("Folder") then return end
	-- Attachment.CFrame is local appearance data; BasePart.CFrame is placed below.
	-- Appearance classes contain values, never external part/joint references.
	local readable, value = pcall(function()
		return property == "Transparency" and source:IsA("FaceInstance") and visibility.GetTransparency(source) or source[property]
	end)
	if not readable then return end
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

function Geometry.Create(character, tool, settings, modelName, budget)
	local right, left, torso = character:FindFirstChild("Right Arm"), character:FindFirstChild("Left Arm"), character:FindFirstChild("Torso")
	local humanoid, handle = character:FindFirstChildOfClass("Humanoid"), tool:FindFirstChild("Handle")
	if not right or not left or not torso or not humanoid or not handle or not handle:IsA("BasePart") then return nil end
	-- The Tool/RightGrip parent can arrive before its joint references. Guessing
	-- from Tool.Grip alone omits the actual hand-side joint frame.
	local grip = gripFrame(right, handle)
	if not grip then return nil end
	local model = Instance.new("Model")
	model.Name = modelName or "RevolverFirstPerson"
	local appearanceConnections = {}
	local buildAppearanceConnections = {}
	local pendingAppearance = {}
	local visibility
	local weaponVisibility
	local ok, result = pcall(function()
		local originals, effects, faces = {}, {}, {}
		for _, item in ipairs(tool:GetDescendants()) do
			if item:IsA("BasePart") then table.insert(originals, item) end
			if skinEffect(item) then table.insert(effects, {source = item}) end
			if item:IsA("FaceInstance") then table.insert(faces, item) end
		end
		if #originals > settings.MaxWeaponParts then error("Weapon exceeds first-person part budget") end
		table.insert(originals, right); table.insert(originals, left)
		local weapon = Instance.new("Model"); weapon.Name, weapon.Parent = "Weapon", model
		local sourceMap, armScales = {}, {}
		local function snapshotBudget(source)
			-- Animated skin properties may change every frame. Keep the latest
			-- values instead of restarting a multi-frame build forever.
			table.insert(buildAppearanceConnections, source.Changed:Connect(function(property)
				if Geometry.IsAppearanceProperty(source, property) then
					local properties = pendingAppearance[source]
					if not properties then properties = {}; pendingAppearance[source] = properties end
					properties[property] = true
				end
			end))
			budget(source)
		end
		local cloneBudget = budget and snapshotBudget or nil
		-- Never clone the equipped Tool itself or its owner/equip controller state.
		for _, item in ipairs(tool:GetChildren()) do
			if renderable(item) then
				cloneVisual(item, sourceMap, true, cloneBudget).Parent = weapon
			end
		end
		local root = weapon:FindFirstChild("Handle")
		if not root or not root:IsA("BasePart") then error("Weapon has no cloned Handle") end
		local pieces, copiedFaces, base = {}, {}, handle.CFrame:Inverse()
		for source, copy in pairs(sourceMap) do
			if copy:IsA("BasePart") then
				prepare(copy)
				table.insert(pieces, {part = copy, source = source, offset = base * source.CFrame})
			end
			if copy:IsA("FaceInstance") then table.insert(copiedFaces, copy) end
		end
		local arms = {}
		for _, original in ipairs({right, left}) do
			local armMap = {}
			local arm = cloneVisual(original, armMap, false, cloneBudget); arm.Parent = model; prepare(arm)
			local scale = settings.ArmThicknessScale
			arm.Size = thin(original.Size, scale)
			for source, copy in pairs(armMap) do
				sourceMap[source], armScales[source] = copy, scale
				if source:IsA("FaceInstance") then table.insert(faces, source) end
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
				cloneVisual(item, sourceMap, false, cloneBudget).Parent = model
			end
		end
		local safeParts = {}
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") then prepare(item); table.insert(safeParts, item) end
			if item:IsA("FaceInstance") then pcall(function() item.LocalTransparencyModifier = 0 end) end
		end
		visibility = Visibility.New(faces)
		weaponVisibility = Visibility.New(copiedFaces)
		for source, properties in pairs(pendingAppearance) do
			local copy = sourceMap[source]
			if copy then
				for property in pairs(properties) do mirrorAppearance(source, copy, property, armScales[source], visibility) end
			end
		end
		arms[2].LocalTransparencyModifier = settings.SupportArmEnabled == false and 1 or 0
		for source, copy in pairs(sourceMap) do
			if not source:IsA("Model") and not source:IsA("Folder") then
				table.insert(appearanceConnections, source.Changed:Connect(function(property)
					mirrorAppearance(source, copy, property, armScales[source], visibility)
				end))
			end
		end
		return {model = model, weapon = weapon, right = arms[1], left = arms[2], pieces = pieces, shell = shell,
			grip = grip, sourceRight = right, sourceHandle = handle, originals = originals, humanoid = humanoid,
			renderHumanoid = hum, safeParts = safeParts, effects = effects,
			sourceMap = sourceMap, copyMap = sourceMap, appearanceConnections = appearanceConnections,
			visibility = visibility, weaponVisibility = weaponVisibility,
			leftShoulder = Vector3.new(table.unpack(settings.LeftShoulder)),
			supportHandOffset = Vector3.new(table.unpack(settings.SupportHandOffset))}
	end)
	for _, connection in ipairs(buildAppearanceConnections) do connection:Disconnect() end
	if not ok then
		if visibility then visibility.Destroy() end
		if weaponVisibility then weaponVisibility.Destroy() end
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
	-- Resolve the live joint's local frame, never the animated arm/Handle world
	-- pose. C0/C1 and Part0/Part1 can settle without any descendant event, and a
	-- replaced or temporarily unbound joint must not retain an old camera hold.
	local grip = gripFrame(visual.sourceRight, visual.sourceHandle)
	if not grip then return false end
	visual.grip = grip
	local right = camera * frame * CFrame.Angles(math.pi / 2, 0, 0)
		* CFrame.Angles(math.rad(pose[1]), math.rad(pose[2]), math.rad(pose[3]))
	visual.right.CFrame = right
	local gun = right * visual.grip
	local sourceBase = visual.sourceHandle.Parent and visual.sourceHandle.CFrame:Inverse()
	local hidden = weaponVisible == false and 1 or 0
	visual.weaponVisibility.SetActive(weaponVisible == false)
	visual.weaponVisibility.Guard()
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
		local shoulder = (camera * (animationFrame or CFrame.identity)):PointToWorldSpace(visual.leftShoulder)
		local hand = right:PointToWorldSpace(visual.supportHandOffset)
		local vector = hand - shoulder
		if vector.Magnitude > 1e-5 then
			-- Solve in camera space with a shortest-arc rotation. Changing lookAt's
			-- up vector at a threshold caused an abrupt roll in the camera arm.
			local direction = camera:VectorToObjectSpace(vector).Unit
			local down = Vector3.new(0, -1, 0)
			local axis, dot = down:Cross(direction), math.clamp(down:Dot(direction), -1, 1)
			local rotation = CFrame.identity
			if axis.Magnitude > 1e-6 then rotation = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
			elseif dot < 0 then rotation = CFrame.Angles(math.pi, 0, 0) end
			local center = hand - vector.Unit * visual.left.Size.Y / 2
			visual.left.CFrame = CFrame.new(center) * camera.Rotation * rotation
		end
	end
	for _, part in ipairs(visual.shell) do part.CFrame = camera end
	return true
end

function Geometry.Destroy(visual)
	visual.visibility.Destroy()
	visual.weaponVisibility.Destroy()
	for _, connection in ipairs(visual.appearanceConnections) do connection:Disconnect() end
	table.clear(visual.appearanceConnections)
	visual.model:Destroy()
end

return Geometry
