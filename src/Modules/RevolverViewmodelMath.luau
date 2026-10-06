-- Cosmetic camera-local motion. No raycasts, inputs, instances or shot authority.
local Motion = {}
local function alpha(speed, dt) return 1 - math.exp(-speed * dt) end

function Motion.New()
	return { aim = 0, reload = 0, raise = 0, swayX = 0, swayY = 0, bob = 0,
		phase = 0, recoil = 0, movement = 0, previous = nil, animation = CFrame.identity }
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

local function animationTarget(body, arm, aim, settings, context, movement)
	if not body and not arm then return CFrame.identity end
	body, arm = body or CFrame.identity, arm or CFrame.identity
	local scale = 1 + (settings.AnimationAimScale - 1) * aim
	-- Smoothly suppress the avatar's walk/sprint animation in camera space.
	-- Knife attacks, reload, recoil and inspect have separate deliberate poses.
	scale *= 1 + ((settings.MovementAnimationScale or 1) - 1) * movement
	local airborne = context and context.airborne
	if airborne then scale *= settings.AirAnimationScale or 0.15 end
	local inspecting = context and context.inspectBlend or 0
	scale *= 1 + ((settings.InspectAnimationScale or 0.15) - 1) * inspecting
	local offset = body.Position * settings.BodyAnimationWeight + arm.Position * settings.ArmAnimationWeight
	if offset.Magnitude > settings.MaxAnimationOffset then offset = offset.Unit * settings.MaxAnimationOffset end
	local rotation = scaledRotation(body, settings.BodyAnimationWeight) * scaledRotation(arm, settings.ArmAnimationWeight)
	local axis, angle = rotation:ToAxisAngle()
	local position = offset * scale
	position = Vector3.new(position.X, math.min(position.Y, settings.MaxUpwardAnimationOffset or 0.08), position.Z)
	local rotationAngle = math.min(angle, math.rad(settings.MaxAnimationDegrees)) * scale
	local maxOffset = settings.MaxAnimationOffset
	if settings.MaxMovementAnimationOffset then
		maxOffset += (settings.MaxMovementAnimationOffset - maxOffset) * movement
	end
	if position.Magnitude > maxOffset then position = position.Unit * maxOffset end
	if settings.MaxMovementAnimationDegrees then
		local maximum = settings.MaxAnimationDegrees + (settings.MaxMovementAnimationDegrees - settings.MaxAnimationDegrees) * movement
		rotationAngle = math.min(rotationAngle, math.rad(maximum))
	end
	if airborne then rotationAngle = math.min(rotationAngle, math.rad(settings.AirMaxAnimationDegrees or 5)) end
	return CFrame.new(position) * CFrame.fromAxisAngle(axis, rotationAngle)
end

function Motion.Step(state, camera, dt, aiming, reloading, speed, settings, bodyAnimation, armAnimation, _, context)
	dt = math.max(0, dt)
	if state.settings ~= settings then
		state.settings = settings
		state.base = Vector3.new(table.unpack(settings.ArmPosition))
		state.aimOffset = Vector3.new(table.unpack(settings.AimOffset))
		state.reloadOffset = Vector3.new(table.unpack(settings.ReloadOffset))
	end
	local blend = alpha(settings.TransitionSpeed, dt)
	state.movement += (math.clamp((speed - 0.5) / 7.5, 0, 1) - state.movement)
		* alpha(settings.MovementFollowSpeed or 12, dt)
	state.aim += ((aiming and 1 or 0) - state.aim) * blend
	state.reload += ((reloading and 1 or 0) - state.reload) * blend
	state.raise += (1 - state.raise) * blend
	-- Read the real Animator pose before procedural weapon aiming. Never animate
	-- a second rig or copy the live player's joints into the camera model.
	state.animation = state.animation:Lerp(animationTarget(bodyAnimation, armAnimation, state.aim, settings, context, state.movement),
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
	local maxBob = settings.MaxBobSpeedScale or 1.5
	state.bob += (math.clamp(speed / 16, 0, maxBob) - state.bob) * blend
	state.phase = (state.phase + dt * settings.BobFrequency * math.min(state.bob, maxBob)) % (math.pi * 2)
	local scale = 1 + (settings.AimMotionScale - 1) * state.aim
	local inspecting = context and context.inspectBlend or 0
	local bobScale = context and context.airborne and (settings.AirBobScale or 0.15) or 1
	bobScale *= 1 + ((settings.InspectBobScale or 0.2) - 1) * inspecting
	local bob = settings.BobAmount * state.bob * scale * bobScale
	local offset = state.aimOffset * state.aim
		+ state.reloadOffset * state.reload
		+ Vector3.new(math.sin(state.phase) * bob, math.sin(state.phase * 2) * bob * 0.5 - (1 - state.raise) * 0.35,
			state.recoil * settings.RecoilDistance)
	local rotation = settings.RotationDegrees
	local swayAngle = math.rad(settings.SwayAngleDegrees) * scale * (1 - inspecting * 0.55)
	local frame = state.animation * CFrame.new(state.base + offset)
		* CFrame.Angles(math.rad(rotation[1]) - state.swayX * swayAngle + math.rad(settings.RecoilDegrees) * state.recoil,
			math.rad(rotation[2]) - state.swayY * swayAngle,
			math.rad(rotation[3] + settings.ReloadRollDegrees * state.reload))
	state.recoil *= math.exp(-settings.RecoilRecovery * dt)
	return frame, state.animation
end

return Motion
