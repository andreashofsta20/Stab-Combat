-- Pure angle/protocol helpers; posing never decides a shot or damage.
local PoseMath = {}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function PoseMath.Angles(x, y, z, settings)
	local horizontal = math.sqrt(x * x + z * z)
	if horizontal < 1e-6 and math.abs(y) < 1e-6 then return 0, 0 end
	local pitch = math.atan2(y, horizontal)
	local yaw = horizontal < 1e-6 and 0 or math.atan2(-x, -z)
	return math.clamp(pitch, math.rad(settings.MinPitchDegrees), math.rad(settings.MaxPitchDegrees)),
		math.clamp(yaw, -math.rad(settings.MaxYawDegrees), math.rad(settings.MaxYawDegrees))
end

function PoseMath.Alpha(speed, dt)
	return 1 - math.exp(-speed * math.max(0, dt))
end

function PoseMath.AcceptPacket(state, sequence, pitch, yaw, settings)
	if not finite(sequence) or sequence % 1 ~= 0 or sequence <= (state.poseSequence or 0)
		or sequence > 2147483647 or not finite(pitch) or not finite(yaw)
		or pitch < math.rad(settings.MinPitchDegrees) - 1e-5
		or pitch > math.rad(settings.MaxPitchDegrees) + 1e-5
		or math.abs(yaw) > math.rad(settings.MaxYawDegrees) + 1e-5 then return false end
	state.poseSequence = sequence
	return true
end

function PoseMath.ShoulderTransform(c0, c1, pitch, yaw, offset)
	-- Part0 * C0 * Transform = Part1 * C1. Preserve the original shoulder
	-- anchor and aim the arm's -Y axis forward, independent of idle/walk tracks.
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.pi / 2 + pitch, 0, 0)
		* CFrame.Angles(math.rad(offset[1]), math.rad(offset[2]), math.rad(offset[3]))
	return c0:Inverse() * CFrame.new(c0.Position) * rotation * c1.Rotation
end

return PoseMath
