-- Shared sway/bob/posture with a local knife wind-up and release. This module
-- owns no input, character joints, damage or projectile origins.
local Shared = require(script.Parent.RevolverViewmodelMath)
local Motion = {}

function Motion.New()
	local state = Shared.New()
	state.actionFrame = CFrame.identity
	return state
end

Motion.FirstPerson = Shared.FirstPerson
Motion.Kick = Shared.Kick

local function actionFrame(offset, rotation, weight)
	return CFrame.new(Vector3.new(table.unpack(offset)) * weight)
		* CFrame.Angles(math.rad(rotation[1]) * weight, math.rad(rotation[2]) * weight, math.rad(rotation[3]) * weight)
end

local function pulse(elapsed, duration)
	if type(elapsed) ~= "number" or elapsed < 0 or elapsed >= duration then return 0 end
	return math.sin(elapsed / duration * math.pi)
end

function Motion.Step(state, camera, dt, aiming, reloading, speed, settings, body, arm, action)
	local frame, animationFrame = Shared.Step(state, camera, dt, aiming, reloading, speed, settings, body, arm)
	action = action or {}
	local charge = action.charging and 0.35 + math.clamp(action.charge or 0, 0, 1) * 0.65 or 0
	local target = actionFrame(settings.ChargeOffset, settings.ChargeRotationDegrees, charge)
		* actionFrame(settings.StabOffset, settings.StabRotationDegrees, pulse(action.stabElapsed, settings.StabSeconds))
		* actionFrame(settings.ThrowOffset, settings.ThrowRotationDegrees, pulse(action.throwElapsed, settings.ThrowSeconds))
	state.actionFrame = state.actionFrame:Lerp(target, 1 - math.exp(-settings.ActionFollowSpeed * math.max(dt, 0)))
	return frame * state.actionFrame, animationFrame
end

return Motion
