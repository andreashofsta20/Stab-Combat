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

function Raycast.Resolve(cameraOrigin, cameraDirection, muzzleOrigin, tuning, candidates, worldCast)
	local aim = cast(cameraOrigin, cameraDirection,
		tuning.Range + (cameraOrigin - muzzleOrigin).Magnitude, candidates, tuning.HitboxSize, worldCast)
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
