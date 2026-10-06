-- Shared sway/bob/posture with a local knife wind-up and release. This module
-- owns no input, character joints, damage or projectile origins.
local Shared = require(script.Parent.RevolverViewmodelMath)
local Motion = {}

function Motion.New()
	local state = Shared.New()
	state.actionFrame = CFrame.identity
	state.followFrame = CFrame.identity
	state.chargeBlend = 0
	return state
end

Motion.FirstPerson = Shared.FirstPerson
Motion.Kick = Shared.Kick

local function radians(rotation)
	return Vector3.new(math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3]))
end

local function rotationFrame(rotation, weight)
	return CFrame.Angles(rotation.X * weight, rotation.Y * weight, rotation.Z * weight)
end

local function validElapsed(elapsed)
	return type(elapsed) == "number" and elapsed == elapsed and elapsed >= 0 and elapsed < math.huge
end

local function pulse(elapsed, duration)
	if not validElapsed(elapsed) or elapsed >= duration then return 0 end
	return math.sin(elapsed / duration * math.pi)
end

local function eased(value)
	return value * value * (3 - 2 * value)
end

local function stabPose(state, elapsed, settings)
	if not validElapsed(elapsed) or elapsed >= settings.StabSeconds then
		return CFrame.identity, 0
	end
	local phase = elapsed / settings.StabSeconds
	local windup, thrust, hold = settings.StabWindupFraction, settings.StabThrustFraction, settings.StabHoldFraction
	if phase < windup then
		local weight = eased(phase / windup)
		return CFrame.identity:Lerp(state.stabWindup, weight), weight
	elseif phase < thrust then
		return state.stabWindup:Lerp(state.stabThrust, eased((phase - windup) / (thrust - windup))), 1
	elseif phase < hold then
		return state.stabThrust, 1
	end
	local recover = eased((phase - hold) / (1 - hold))
	return state.stabThrust:Lerp(CFrame.identity, recover), 1 - recover
end

function Motion.Step(state, camera, dt, aiming, reloading, speed, settings, body, arm, action, context)
	local frame, animationFrame = Shared.Step(state, camera, dt, aiming, reloading, speed, settings, body, arm, action, context)
	if state.actionSettings ~= settings then
		state.actionSettings = settings
		state.chargeOffset, state.stabOffset, state.throwOffset = Vector3.new(table.unpack(settings.ChargeOffset)),
			Vector3.new(table.unpack(settings.StabOffset)), Vector3.new(table.unpack(settings.ThrowOffset))
		state.chargeRotation, state.stabRotation, state.throwRotation = radians(settings.ChargeRotationDegrees),
			radians(settings.StabRotationDegrees), radians(settings.ThrowRotationDegrees)
		state.stabWindup = CFrame.new(Vector3.new(table.unpack(settings.StabWindupOffset)))
			* rotationFrame(radians(settings.StabWindupRotationDegrees), 1)
		state.stabThrust = CFrame.new(state.stabOffset) * rotationFrame(state.stabRotation, 1)
		state.chargeBase = CFrame.new(Vector3.new(table.unpack(settings.ArmPosition)))
			* rotationFrame(radians(settings.RotationDegrees), 1)
	end
	local amount = action and action.charge or 0
	if type(amount) ~= "number" or amount ~= amount then amount = 0 end
	local stabElapsed, throwElapsed = action and action.stabElapsed, action and action.throwElapsed
	-- A tap can be followed immediately by another held input. Input/gameplay
	-- still charge normally; visual actions take turns instead of adding poses.
	-- A newer released throw retires the old stab even after its pulse expires.
	local newerThrow = validElapsed(throwElapsed)
		and (not validElapsed(stabElapsed) or throwElapsed <= stabElapsed)
	local throwing = newerThrow and throwElapsed < settings.ThrowSeconds
	local stabbing = validElapsed(stabElapsed) and stabElapsed < settings.StabSeconds and not newerThrow
	local charging = action ~= nil and action.charging == true and not stabbing and not throwing
	local charge = charging and 0.35 + math.clamp(amount, 0, 1) * 0.65 or 0
	local throw = throwing and pulse(throwElapsed, settings.ThrowSeconds) or 0
	local target = CFrame.new(state.chargeOffset * charge + state.throwOffset * throw)
		* rotationFrame(state.chargeRotation, charge) * rotationFrame(state.throwRotation, throw)
	local blend = 1 - math.exp(-settings.ActionFollowSpeed * math.max(dt, 0))
	-- A fresh stab also cancels any remaining charge/throw follow-through, so
	-- the planted grip cannot inherit the previous cosmetic action's rotation.
	state.followFrame = stabbing and CFrame.identity or state.followFrame:Lerp(target, blend)
	-- Attack uses its elapsed time directly: a second low-pass filter would hide
	-- the short thrust at low FPS and drag its return beyond the action duration.
	local stab, stabBlend = stabPose(state, stabbing and stabElapsed or nil, settings)
	-- The live stab clip continues on the real character for other players.
	-- Its shoulder/root motion must not fight this deliberate camera-hand pose.
	-- Blend it out during preparation and back in during recovery; the whole
	-- extended hand stays planted while the knife is visibly driven forward.
	if stabBlend > 0 then frame = frame:Lerp(state.chargeBase, stabBlend) end
	state.actionFrame = CFrame.new(state.followFrame.Position + stab.Position) * state.followFrame.Rotation * stab.Rotation
	if stabbing then state.chargeBlend = 0
	else state.chargeBlend += ((charging and 1 or 0) - state.chargeBlend) * blend end
	if state.chargeBlend < 1e-5 then state.chargeBlend = 0
	elseif state.chargeBlend > 1 - 1e-5 then state.chargeBlend = 1 end
	-- The real Animator changes from Charge to ChargeHold when the wind-up ends.
	-- Fade into a fixed camera-local base so that change cannot lower the hand.
	-- Native camera posture still lowers both the view and hands during crouch/slide.
	if state.chargeBlend == 1 then frame = state.chargeBase
	elseif state.chargeBlend > 0 then frame = frame:Lerp(state.chargeBase, state.chargeBlend) end
	-- Translate in camera space before the animated arm, so crouch/slide or an
	-- unusual grip cannot rotate an upward charge into a downward/sideways move.
	return CFrame.new(state.actionFrame.Position) * frame * state.actionFrame.Rotation, animationFrame
end

return Motion
