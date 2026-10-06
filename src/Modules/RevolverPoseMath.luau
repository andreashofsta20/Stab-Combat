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
	-- Horizontal direction becomes ill-conditioned while aiming almost straight
	-- down/up. Fade only that narrow cone so tiny cursor movement cannot flip yaw.
	local length = math.sqrt(horizontal * horizontal + y * y)
	local fadeStart, fadeEnd = settings.VerticalYawFadeStart or 0.08, settings.VerticalYawFadeEnd or 0.25
	local stability = math.clamp((horizontal / length - fadeStart) / (fadeEnd - fadeStart), 0, 1)
	yaw *= stability * stability * (3 - 2 * stability)
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
	-- R6 has no elbow/wrist joints. Orient the rigid arm's palm toward the
	-- support point, accounting for the shoulder's offset from the arm centre.
	local palm = Vector3.new(0, -armLength / 2, 0) - c1.Position
	-- A shortest-arc rotation has no arbitrary up-vector switch near vertical.
	-- The former lookAt basis changed at Y=0.98 and could visibly snap the arm.
	local from, to = palm.Unit, direction.Unit
	local axis, dot = from:Cross(to), math.clamp(from:Dot(to), -1, 1)
	local rotation
	if axis.Magnitude > 1e-6 then rotation = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
	elseif dot < 0 then
		axis = from:Cross(Vector3.new(0, 0, 1))
		if axis.Magnitude < 1e-6 then axis = from:Cross(Vector3.new(1, 0, 0)) end
		rotation = CFrame.fromAxisAngle(axis.Unit, math.pi)
	else rotation = CFrame.identity end
	return c0:Inverse() * CFrame.new(c0.Position) * rotation * c1.Rotation
end

return PoseMath
