-- Both prediction and authority use the same two-ray aiming algorithm.
local Math = require(script.Parent.RevolverMath)
local Raycast = {}

local function cast(origin, direction, length, candidates, size, worldCast)
	local worldHit = worldCast(origin, direction * length)
	local limit = worldHit and worldHit.Distance or length
	local victim, victimFrame = nil, nil
	for _, candidate in ipairs(candidates) do
		local distance = Math.RayBoxDistance(origin, direction, candidate.frame, size, limit)
		if distance and distance < limit then
			-- An enlarged box must not protrude through a wall and grant damage
			-- to a player whose actual center is hidden behind that wall.
			local centerVector = candidate.frame.Position - origin
			local cover = worldCast(origin, centerVector)
			if not cover or cover.Distance >= centerVector.Magnitude - 0.02 then
				limit, victim, victimFrame = distance, candidate, candidate.frame
			end
		end
	end
	return {
		position = origin + direction * limit,
		normal = not victim and worldHit and worldHit.Normal or nil,
		victim = victim,
		frame = victimFrame,
		distance = limit,
	}
end

function Raycast.GetAimOrigin(cameraOrigin, cameraDirection, referenceOrigin)
	-- A third-person camera can see ground/props between itself and the gun.
	-- Never converge the barrel toward an aim point behind its forward plane:
	-- that flips the shot backward/downward even when its forward path is clear.
	-- Advancing along the SAME camera ray keeps the cursor alignment intact.
	local offset = referenceOrigin - cameraOrigin
	local depth = math.max(0, offset:Dot(cameraDirection))
	local horizontalSquared = cameraDirection.X * cameraDirection.X + cameraDirection.Z * cameraDirection.Z
	if horizontalSquared > 1e-4 then
		-- An overhead camera's perpendicular plane can sit beyond an elevated
		-- target that is still in front of the character. Clip no farther than
		-- the character's horizontal forward plane; keep the exact cursor ray.
		local horizontalDepth = (offset.X * cameraDirection.X + offset.Z * cameraDirection.Z) / horizontalSquared
		depth = math.min(depth, math.max(0, horizontalDepth))
	end
	return cameraOrigin + cameraDirection * depth
end

function Raycast.Resolve(cameraOrigin, cameraDirection, muzzleOrigin, tuning, candidates, worldCast, referenceOrigin)
	local aimOrigin = Raycast.GetAimOrigin(cameraOrigin, cameraDirection, referenceOrigin or muzzleOrigin)
	local aim = cast(aimOrigin, cameraDirection,
		tuning.Range + (aimOrigin - muzzleOrigin).Magnitude, candidates, tuning.HitboxSize, worldCast)
	local vector = aim.position - muzzleOrigin
	if vector.Magnitude < 0.001 then return nil end
	-- Extend just past the picked box surface to avoid numeric boundary misses.
	local length = math.min(tuning.Range, vector.Magnitude + 0.05)
	return cast(muzzleOrigin, vector.Unit, length, candidates, tuning.HitboxSize, worldCast)
end

function Raycast.GetMuzzle(tool, head, tuning, maxDistance)
	local muzzle = tool:FindFirstChild(tuning.MuzzleAttachmentName, true)
	local origin
	if muzzle and muzzle:IsA("Attachment") then
		origin = muzzle.WorldPosition
	elseif muzzle and muzzle:IsA("BasePart") then
		origin = muzzle.Position
	else
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			origin = handle.CFrame:PointToWorldSpace(Vector3.new(table.unpack(tuning.MuzzleOffset)))
		end
	end
	if not origin or not Math.IsFiniteVector(origin, 1000000)
		or (origin - head.Position).Magnitude > maxDistance then
		return head.Position
	end
	return origin
end

return Raycast
