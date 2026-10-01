-- Pure angle/protocol helpers; posing never decides a shot or damage.
local PoseMath = {}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function PoseMath.Angles(x, y, z, settings)
	local horizontal = math.sqrt(x * x + z * z)
	if horizontal < 1e-6 and math.abs(y) < 1e-6 then return 0, 0 end
	local pitch = math.atan2(y, horizontal)
	-- Fold the rear hemisphere toward the neutral pose. R6 shoulders cannot
	-- point backwards; asin is continuous at the rear instead of jumping +/-pi.
	-- This changes only the arm pose; the camera ray still decides shot aim.
	local yaw = horizontal < 1e-6 and 0 or math.asin(math.clamp(-x / horizontal, -1, 1))
	return math.clamp(pitch, math.rad(settings.MinPitchDegrees), math.rad(settings.MaxPitchDegrees)),
		math.clamp(yaw, -math.rad(settings.MaxYawDegrees), math.rad(settings.MaxYawDegrees))
end

function PoseMath.Alpha(speed, dt)
	return 1 - math.exp(-speed * math.max(0, dt))
end

function PoseMath.WrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function PoseMath.AcceptPacket(state, sequence, pitch, yaw, settings, aiming)
	if aiming ~= nil and type(aiming) ~= "boolean" then return false end
	if not finite(sequence) or sequence % 1 ~= 0 or sequence <= (state.poseSequence or 0)
		or sequence > 2147483647 or not finite(pitch) or not finite(yaw)
		or pitch < math.rad(settings.MinPitchDegrees) - 1e-5
		or pitch > math.rad(settings.MaxPitchDegrees) + 1e-5
		or math.abs(yaw) > math.rad(settings.MaxYawDegrees) + 1e-5 then return false end
	state.poseSequence = sequence
	return true
end

function PoseMath.ShoulderTransform(c0, c1, pitch, yaw, offset, positionOffset)
	-- Part0 * C0 * Transform = Part1 * C1. Preserve the original shoulder
	-- anchor and aim the arm's -Y axis forward, independent of idle/walk tracks.
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.pi / 2 + pitch, 0, 0)
		* CFrame.Angles(math.rad(offset[1]), math.rad(offset[2]), math.rad(offset[3]))
	return c0:Inverse() * CFrame.new(c0.Position + (positionOffset or Vector3.zero)) * rotation * c1.Rotation
end

function PoseMath.SupportTransform(c0, c1, handPosition, armLength)
	local direction = handPosition - c0.Position
	if direction.Magnitude < 1e-5 then return CFrame.identity end
	local up = math.abs(direction.Unit.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	-- R6 has no elbow/wrist joints. Orient the rigid arm's palm toward the
	-- support point, accounting for the shoulder's offset from the arm centre.
	local palm = Vector3.new(0, -armLength / 2, 0) - c1.Position
	local roll = math.atan2(-palm.X, -palm.Y)
	local rotation = CFrame.lookAt(Vector3.zero, direction, up).Rotation
		* CFrame.Angles(math.pi / 2, 0, roll)
	return c0:Inverse() * CFrame.new(c0.Position) * rotation * c1.Rotation
end

return PoseMath
