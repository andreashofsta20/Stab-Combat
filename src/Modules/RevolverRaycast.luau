-- Both prediction and authority use the same two-ray aiming algorithm.
local Math = require(script.Parent.RevolverMath)
local Raycast = {}

local function geometry(part)
	if not part or not part:IsA("BasePart") or not Math.IsFiniteVector(part.Position, 1000000)
		or not Math.IsFiniteVector(part.Size, 1000) or part.Size.X <= 0 or part.Size.Y <= 0 or part.Size.Z <= 0 then return nil end
	return {part = part, frame = part.CFrame, size = {part.Size.X, part.Size.Y, part.Size.Z}}
end

-- Only direct character body parts count. Accessories, held tools and the
-- enlarged Hitbox never turn a near miss or a hat hit into a headshot.
function Raycast.GetCharacterGeometry(character)
	local result = {bodyParts = {}}
	local head = geometry(character:FindFirstChild("Head"))
	if head then result.headFrame, result.headSize, result.headPart = head.frame, head.size, head.part end
	for _, part in ipairs(character:GetChildren()) do
		if part.Name ~= "Head" and part.Name ~= "HumanoidRootPart" and part.Name ~= "Hitbox" then
			local body = geometry(part)
			if body then table.insert(result.bodyParts, body) end
		end
	end
	return result
end

function Raycast.GetHeadshotDistance(origin, direction, length, candidate, worldCast)
	if not candidate.headFrame or not candidate.headSize then return nil end
	local distance = Math.RayBoxDistance(origin, direction, candidate.headFrame, candidate.headSize, length)
	if not distance then return nil end
	-- An arm/torso in front of the head must remain a body hit, including
	-- shots from below. The forgiving proxy is deliberately not tested here.
	for _, body in ipairs(candidate.bodyParts or {}) do
		local bodyDistance = Math.RayBoxDistance(origin, direction, body.frame, body.size, distance)
		if bodyDistance and bodyDistance < distance - 1e-4 then return nil end
	end
	if worldCast then
		local cover = worldCast(origin, direction * (distance + 0.001))
		if cover and cover.Distance <= distance then return nil end
	end
	return distance
end

local function cast(origin, direction, length, candidates, size, worldCast)
	local worldHit = worldCast(origin, direction * length)
	local limit = worldHit and worldHit.Distance or length
	local victim, victimFrame, headshot = nil, nil, false
	for _, candidate in ipairs(candidates) do
		local headDistance = Raycast.GetHeadshotDistance(origin, direction, limit, candidate)
		local distance = headDistance or Math.RayBoxDistance(origin, direction, candidate.frame, size, limit)
		if distance and distance < limit then
			-- An enlarged box must not protrude through a wall and grant damage
			-- to a player whose actual center is hidden behind that wall.
			local centerVector = candidate.frame.Position - origin
			local cover = not headDistance and worldCast(origin, centerVector) or nil
			-- A directly intersected head may be exposed above covered shoulders.
			-- The full shot ray above already bounds it against world geometry.
			if headDistance or not cover or cover.Distance >= centerVector.Magnitude - 0.02 then
				limit, victim, victimFrame = distance, candidate, candidate.frame
				headshot = headDistance ~= nil
			end
		end
	end
	return {
		position = origin + direction * limit,
		normal = not victim and worldHit and worldHit.Normal or nil,
		surface = not victim and worldHit and worldHit.Instance or nil,
		victim = victim,
		frame = victimFrame,
		distance = limit,
		headshot = headshot,
	}
end

function Raycast.GetAimOrigin(cameraOrigin)
	-- Visible cursor targets can lie between the camera and character.
	-- Keep the entire camera ray, including targets behind the avatar.
	return cameraOrigin
end

function Raycast.Resolve(cameraOrigin, cameraDirection, firingOrigin, tuning, candidates, worldCast)
	local aimOrigin = Raycast.GetAimOrigin(cameraOrigin)
	local aim = cast(aimOrigin, cameraDirection,
		tuning.Range + (aimOrigin - firingOrigin).Magnitude, candidates, tuning.HitboxSize, worldCast)
	local vector = aim.position - firingOrigin
	if vector.Magnitude < 0.001 then
		-- Only a coincident endpoint needs a direction fallback. A camera
		-- inside a rear proxy must still aim from the head toward that proxy.
		if aim.victim then return cast(firingOrigin, cameraDirection, tuning.Range, candidates, tuning.HitboxSize, worldCast) end
		return aim
	end
	-- The head-to-cursor vector can oppose the camera ray for a close rear
	-- target. Avatar facing and camera facing do not restrict legal shots.
	-- Extend just past the picked box surface to avoid numeric boundary misses.
	local length = math.min(tuning.Range, vector.Magnitude + 0.05)
	return cast(firingOrigin, vector.Unit, length, candidates, tuning.HitboxSize, worldCast)
end

-- Keep one segment ending at the already resolved shot endpoint. A decorative
-- muzzle is usable only when reaching it and firing from it respect the same
-- cover. This helper never selects a target or modifies gameplay geometry.
function Raycast.GetVisualShotOrigin(physicalOrigin, cosmeticOrigin, destination, worldCast)
	if not Math.IsFiniteVector(physicalOrigin, 1000000) or not Math.IsFiniteVector(cosmeticOrigin, 1000000)
		or not Math.IsFiniteVector(destination, 1000000) or type(worldCast) ~= "function" then return physicalOrigin end
	local accepted = destination - physicalOrigin
	if accepted.Magnitude < 0.001 then return physicalOrigin end
	local visible = destination - cosmeticOrigin
	if visible:Dot(accepted.Unit) <= 0 then return physicalOrigin end
	local offset = cosmeticOrigin - physicalOrigin
	if offset.Magnitude > 1e-8 and worldCast(physicalOrigin, offset) then return physicalOrigin end
	local obstruction = worldCast(cosmeticOrigin, visible)
	if obstruction and obstruction.Distance < visible.Magnitude - 0.02 then return physicalOrigin end
	return cosmeticOrigin
end

-- Authored muzzle geometry for visual effects and positional audio only.
-- Gameplay resolves from the character's head, independent of weapon animation.
function Raycast.GetMuzzlePosition(tool, tuning)
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
	if not origin or not Math.IsFiniteVector(origin, 1000000) then return nil, muzzle end
	return origin, muzzle
end

function Raycast.GetMuzzle(tool, head, tuning, maxDistance)
	local origin = Raycast.GetMuzzlePosition(tool, tuning)
	if not origin or (origin - head.Position).Magnitude > maxDistance then
		return head.Position
	end
	return origin
end

-- Visual effects use their own offset, including skins with an authored Muzzle.
-- Neither this offset nor the animated muzzle changes the authoritative ray.
function Raycast.GetVisualMuzzleFrame(tool, tuning)
	local physical, muzzle = Raycast.GetMuzzlePosition(tool, tuning)
	if not physical then return nil, muzzle end
	local frame
	if muzzle and muzzle:IsA("Attachment") then frame = muzzle.WorldCFrame
	elseif muzzle and muzzle:IsA("BasePart") then frame = muzzle.CFrame
	else
		local handle = tool:FindFirstChild("Handle")
		frame = handle.CFrame * CFrame.new(table.unpack(tuning.MuzzleOffset))
	end
	local settings = tuning.Effects
	local visual = frame * CFrame.new(settings.MuzzleVisualRight, settings.MuzzleVisualUp, -settings.MuzzleVisualForward)
	if not Math.IsFiniteVector(visual.Position, 1000000) then return nil, muzzle end
	return visual, muzzle
end

return Raycast
