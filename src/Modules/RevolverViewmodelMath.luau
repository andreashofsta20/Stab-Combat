-- Cosmetic camera-local motion. No raycasts, inputs, instances or shot authority.
local Motion = {}
local function alpha(speed, dt) return 1 - math.exp(-speed * dt) end

function Motion.New()
	return { aim = 0, reload = 0, raise = 0, swayX = 0, swayY = 0, bob = 0,
		phase = 0, recoil = 0, previous = nil, animation = CFrame.identity }
end

function Motion.FirstPerson(active, distance, settings)
	return distance < (active and settings.ExitDistance or settings.EnterDistance)
end

function Motion.Kick(state)
	state.recoil = math.min(state.recoil + 1, 2)
end

local function scaledRotation(frame, weight)
	local axis, angle = frame:ToAxisAngle()
	return CFrame.fromAxisAngle(axis, angle * weight)
end

local function animationTarget(body, arm, aim, settings)
	if not body and not arm then return CFrame.identity end
	body, arm = body or CFrame.identity, arm or CFrame.identity
	local scale = 1 + (settings.AnimationAimScale - 1) * aim
	local offset = body.Position * settings.BodyAnimationWeight + arm.Position * settings.ArmAnimationWeight
	if offset.Magnitude > settings.MaxAnimationOffset then offset = offset.Unit * settings.MaxAnimationOffset end
	local rotation = scaledRotation(body, settings.BodyAnimationWeight) * scaledRotation(arm, settings.ArmAnimationWeight)
	local axis, angle = rotation:ToAxisAngle()
	return CFrame.new(offset * scale) * CFrame.fromAxisAngle(axis, math.min(angle, math.rad(settings.MaxAnimationDegrees)) * scale)
end

function Motion.Step(state, camera, dt, aiming, reloading, speed, settings, bodyAnimation, armAnimation)
	dt = math.max(0, dt)
	local blend = alpha(settings.TransitionSpeed, dt)
	state.aim += ((aiming and 1 or 0) - state.aim) * blend
	state.reload += ((reloading and 1 or 0) - state.reload) * blend
	state.raise += (1 - state.raise) * blend
	-- Read the real Animator pose before procedural weapon aiming. Never animate
	-- a second rig or copy the live player's joints into the camera model.
	state.animation = state.animation:Lerp(animationTarget(bodyAnimation, armAnimation, state.aim, settings),
		alpha(settings.AnimationFollowSpeed, dt))
	local pitch, yaw = 0, 0
	if state.previous and dt > 1e-5 and dt < 0.25 then
		local look = state.previous:VectorToObjectSpace(camera.LookVector)
		pitch = math.asin(math.clamp(look.Y, -1, 1)) / dt
		yaw = math.atan2(-look.X, -look.Z) / dt
	end
	state.previous = camera.Rotation
	local sway = alpha(settings.SwaySpeed, dt)
	state.swayX += (math.clamp(pitch / settings.SwayMaxAngularSpeed, -1, 1) - state.swayX) * sway
	state.swayY += (math.clamp(yaw / settings.SwayMaxAngularSpeed, -1, 1) - state.swayY) * sway
	state.bob += (math.clamp(speed / 16, 0, 1.5) - state.bob) * blend
	state.phase = (state.phase + dt * settings.BobFrequency * math.min(state.bob, 1.5)) % (math.pi * 2)
	local scale = 1 + (settings.AimMotionScale - 1) * state.aim
	local bob = settings.BobAmount * state.bob * scale
	local base = Vector3.new(table.unpack(settings.ArmPosition))
	local offset = Vector3.new(table.unpack(settings.AimOffset)) * state.aim
		+ Vector3.new(table.unpack(settings.ReloadOffset)) * state.reload
		+ Vector3.new(math.sin(state.phase) * bob, math.sin(state.phase * 2) * bob * 0.5 - (1 - state.raise) * 0.35,
			state.recoil * settings.RecoilDistance)
	local rotation = settings.RotationDegrees
	local swayAngle = math.rad(settings.SwayAngleDegrees) * scale
	local frame = state.animation * CFrame.new(base + offset)
		* CFrame.Angles(math.rad(rotation[1]) - state.swayX * swayAngle + math.rad(settings.RecoilDegrees) * state.recoil,
			math.rad(rotation[2]) - state.swayY * swayAngle,
			math.rad(rotation[3] + settings.ReloadRollDegrees * state.reload))
	state.recoil *= math.exp(-settings.RecoilRecovery * dt)
	return frame, state.animation
end

return Motion
