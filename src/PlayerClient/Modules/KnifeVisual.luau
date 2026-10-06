-- Clone the whole weapon: many skins keep their blade beside a transparent
-- Handle, rather than inside it. Every part retains its relative transform.
local Visual = {}

local function lookAlong(position, direction)
	local up = math.abs(direction.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return CFrame.lookAt(position, position + direction, up)
end

local function cloneAll(template)
	local changed = {}
	local function include(item)
		if item.Archivable == false then changed[item] = true; item.Archivable = true end
	end
	include(template)
	for _, item in ipairs(template:GetDescendants()) do include(item) end
	local ok, clone = pcall(function() return template:Clone() end)
	for item in pairs(changed) do item.Archivable = false end
	return ok and clone or nil
end

function Visual.Create(template, settings)
	local clone = cloneAll(template)
	if not clone then return nil end
	local all = clone:GetDescendants()
	if clone:IsA("BasePart") then table.insert(all, clone) end
	local parts, visibleCount = {}, 0
	for _, item in ipairs(all) do
		if item:IsA("BaseScript") or item:IsA("JointInstance") or item:IsA("Constraint")
			or item:IsA("WeldConstraint") or item:IsA("Trail") or item:IsA("Beam")
			or item:IsA("ParticleEmitter") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery = true, false, false, false
			item.LocalTransparencyModifier = 0 -- held-weapon hiding must not hide its projectile
			table.insert(parts, item)
			if item.Transparency < 1 then visibleCount += 1 end
		end
	end
	if #parts == 0 then clone:Destroy(); return nil end
	local root = clone:IsA("BasePart") and clone or clone:FindFirstChild("Handle", true)
	if not root or not root:IsA("BasePart") then root = parts[1] end
	-- Some templates rely on an equip script to reveal a mesh. The projectile
	-- strips scripts, so reveal the mesh if otherwise the whole clone is invisible.
	if visibleCount == 0 then
		for _, part in ipairs(parts) do
			if part:IsA("MeshPart") or part:FindFirstChildOfClass("SpecialMesh") then
				part.Transparency = 0; visibleCount += 1
			end
		end
		if visibleCount == 0 then root.Transparency = 0 end
	end
	local base = root.CFrame
	local minimum, maximum = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local records, corners = {}, {}
	for _, part in ipairs(parts) do
		local offset = base:Inverse() * part.CFrame
		table.insert(records, {part = part, offset = offset})
		if part.Transparency < 1 then
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			local meshOffset = mesh and mesh.Offset or Vector3.zero
			for _, x in ipairs({-1, 1}) do for _, y in ipairs({-1, 1}) do for _, z in ipairs({-1, 1}) do
				local point = offset:PointToWorldSpace(Vector3.new(x * part.Size.X / 2, y * part.Size.Y / 2, z * part.Size.Z / 2) + meshOffset)
				table.insert(corners, point)
				minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
				maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
			end end end
		end
	end
	local center, size = (minimum + maximum) / 2, maximum - minimum
	local axis = settings.BladeAxis
	if axis == "Auto" then
		axis = size.X > size.Y and size.X > size.Z and "+X" or (size.Z > size.Y and "-Z" or "+Y")
	end
	local rotations = {
		["+X"] = CFrame.Angles(0, math.pi / 2, 0), ["-X"] = CFrame.Angles(0, -math.pi / 2, 0),
		["+Y"] = CFrame.Angles(-math.pi / 2, 0, 0), ["-Y"] = CFrame.Angles(math.pi / 2, 0, 0),
		["+Z"] = CFrame.Angles(0, math.pi, 0), ["-Z"] = CFrame.new(),
	}
	local angles = settings.RotationDegrees
	local rotation = assert(rotations[axis], "Invalid knife BladeAxis") * CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
	local tipDistance, tailDistance = 0, 0
	for _, corner in ipairs(corners) do
		local forward = -rotation:VectorToWorldSpace(corner - center).Z
		tipDistance, tailDistance = math.max(tipDistance, forward), math.max(tailDistance, -forward)
	end
	-- FileMesh bounds cannot be read from SpecialMesh. Its existing tip override
	-- describes the visible half-length when the physical Part.Size differs.
	if settings.TipDistance > 0 then tipDistance, tailDistance = settings.TipDistance, settings.TipDistance end
	local visibleLength = tipDistance + tailDistance
	local stickDepth = math.clamp(math.max(settings.StickDepth,
		visibleLength * (settings.StickFraction or 0)), 0, visibleLength * 0.8)
	for _, record in ipairs(records) do record.offset = CFrame.new(-center) * record.offset end
	local model = Instance.new("Model")
	model.Name = "KnifeProjectile_" .. template.Name
	if clone:IsA("BasePart") then clone.Parent = model
	else
		for _, item in ipairs(clone:GetChildren()) do item.Parent = model end
		clone:Destroy()
	end
	local trailAnchor = Instance.new("Part")
	trailAnchor.Name, trailAnchor.Size, trailAnchor.Transparency = "KnifeTrailAnchor", Vector3.one * 0.05, 1
	trailAnchor.Anchored, trailAnchor.CanCollide, trailAnchor.CanTouch, trailAnchor.CanQuery = true, false, false, false
	trailAnchor.CastShadow, trailAnchor.Parent = false, model
	return {model = model, root = root, trailAnchor = trailAnchor, parts = records, rotation = rotation,
		tipDistance = tipDistance, stickDepth = stickDepth}
end

local function place(visual, frame)
	for _, record in ipairs(visual.parts) do record.part.CFrame = frame * record.offset end
end

function Visual.Fly(visual, position, direction)
	place(visual, lookAlong(position, direction) * visual.rotation)
	visual.trailAnchor.CFrame = lookAlong(position, direction)
end

function Visual.Stick(visual, position, direction, normal)
	-- Raycast normals point out of the impacted face. Aim into that face so
	-- walls, floors and slopes embed the same visible fraction of every skin.
	local into = typeof(normal) == "Vector3" and normal.Magnitude > 0.5 and -normal.Unit or direction
	local center = position - into * (visual.tipDistance - visual.stickDepth)
	place(visual, lookAlong(center, into) * visual.rotation)
	visual.trailAnchor.CFrame = lookAlong(center, into)
end

return Visual
