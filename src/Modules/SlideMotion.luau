-- Pure movement math shared with the deterministic slide tests.
local Motion = {}
local UP = Vector3.new(0, 1, 0)

function Motion.Horizontal(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return flat.Magnitude > 1e-4 and flat.Unit or fallback
end

function Motion.Tangent(direction, normal)
	local tangent = direction - normal * direction:Dot(normal)
	return tangent.Magnitude > 1e-4 and tangent.Unit or Motion.Horizontal(direction, Vector3.new(0, 0, -1))
end

function Motion.Steer(direction, desired, maxRadians)
	desired = Motion.Horizontal(desired, direction)
	local dot = math.clamp(direction:Dot(desired), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxRadians or angle < 1e-4 then return desired end
	local cross = direction:Cross(desired).Y
	local turn = math.max(maxRadians, 0) * (cross < 0 and -1 or 1)
	local cosine, sine = math.cos(turn), math.sin(turn)
	return Vector3.new(direction.X * cosine + direction.Z * sine, 0, -direction.X * sine + direction.Z * cosine)
end

local function smoothstep(value)
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

function Motion.Speed(initial, peak, final, elapsed, duration, boostSeconds)
	boostSeconds = math.clamp(boostSeconds, 1e-4, duration * 0.5)
	if elapsed < boostSeconds then
		return initial + (peak - initial) * smoothstep(elapsed / boostSeconds)
	end
	return peak + (final - peak) * smoothstep((elapsed - boostSeconds) / math.max(duration - boostSeconds, 1e-4))
end

function Motion.Walkable(normal, maxSlopeDegrees)
	return normal.Y >= math.cos(math.rad(maxSlopeDegrees))
end

function Motion.StepSpeed(height, gravity, margin, maxHeight)
	if height <= 0.04 or height > maxHeight or gravity <= 0 then return nil end
	-- An impulse with this speed can rise only height + margin, independent of
	-- frame rate. The controller checks body/head clearance before applying it.
	return math.sqrt(2 * gravity * (height + margin))
end

function Motion.SmoothNormal(current, desired, response, dt)
	local mixed = current:Lerp(desired, 1 - math.exp(-response * math.max(dt, 0)))
	return mixed.Magnitude > 1e-4 and mixed.Unit or UP
end

return Motion
