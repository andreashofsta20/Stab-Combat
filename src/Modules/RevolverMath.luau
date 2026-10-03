local Math = {}

function Math.IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function Math.IsFiniteVector(value: any, bound: number): boolean
	return typeof(value) == "Vector3"
		and Math.IsFiniteNumber(value.X) and Math.IsFiniteNumber(value.Y) and Math.IsFiniteNumber(value.Z)
		and math.abs(value.X) <= bound and math.abs(value.Y) <= bound and math.abs(value.Z) <= bound
end

-- Slab intersection in box-local coordinates. Direction is a unit vector,
-- so the result is a distance in studs. Numeric core is testable outside Studio.
function Math.RayAabbDistance(ox, oy, oz, dx, dy, dz, hx, hy, hz, maxDistance)
	local near, far = 0, maxDistance
	local function axis(origin, direction, halfExtent)
		if math.abs(direction) < 1e-8 then
			return math.abs(origin) <= halfExtent
		end
		local first, last = (-halfExtent - origin) / direction, (halfExtent - origin) / direction
		if first > last then first, last = last, first end
		near, far = math.max(near, first), math.min(far, last)
		return near <= far
	end
	if axis(ox, dx, hx) and axis(oy, dy, hy) and axis(oz, dz, hz) then return near end
	return nil
end

function Math.RayBoxDistance(origin, direction, frame, size, maxDistance)
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	return Math.RayAabbDistance(o.X, o.Y, o.Z, d.X, d.Y, d.Z,
		size[1] / 2, size[2] / 2, size[3] / 2, maxDistance)
end

function Math.TimestampAllowed(now, timestamp, ping, security)
	if not Math.IsFiniteNumber(timestamp) or not Math.IsFiniteNumber(ping) then return false end
	local maxAge = math.min(security.MaxPacketAgeMs / 1000,
		math.max(0, ping) + security.TimestampJitterMs / 1000)
	return timestamp <= now + security.FutureTimestampToleranceMs / 1000
		and timestamp >= now - maxAge
end

function Math.RewindTime(now, timestamp, ping, lag)
	if not lag.Enabled then return now end
	-- The client cannot choose an arbitrarily old target pose. Both timestamp
	-- age and the measured network ping bound this query.
	local maxRewind = math.min(lag.MaxRewindMs / 1000,
		math.max(0, ping) + lag.InterpolationMs / 1000)
	return math.clamp(timestamp - lag.InterpolationMs / 1000, now - maxRewind, now)
end

return Math
