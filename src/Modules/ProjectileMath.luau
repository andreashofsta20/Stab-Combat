-- Shared knife projectile rules. Keep this module free of Roblox services so the
-- client prediction and the server simulation use exactly the same numbers.
local ProjectileMath = {}
local Config = require(script.Parent.KnifeConfig).Throw

ProjectileMath.MAX_DISTANCE = Config.MaxDistance
ProjectileMath.MAX_FLIGHT_TIME = Config.MaxFlightTime
ProjectileMath.FIXED_STEP = 1 / 60 -- Legacy API; straight sweeps no longer need steps.
ProjectileMath.MIN_SPEED = Config.MinSpeed
ProjectileMath.MAX_SPEED = Config.MaxSpeed
ProjectileMath.DAMAGE = Config.Damage
ProjectileMath.HEADSHOT_KILLS = Config.HeadshotKills == true
ProjectileMath.COOLDOWN = Config.Cooldown
ProjectileMath.MAX_CHARGE = 1
ProjectileMath.MIN_ORIGIN_DISTANCE = 0
ProjectileMath.MAX_ORIGIN_DISTANCE = Config.MaxOriginDistance

function ProjectileMath.IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ProjectileMath.IsFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and ProjectileMath.IsFiniteNumber(value.X)
		and ProjectileMath.IsFiniteNumber(value.Y)
		and ProjectileMath.IsFiniteNumber(value.Z)
end

function ProjectileMath.ClampCharge(value: number): number
	return math.clamp(value, 0, ProjectileMath.MAX_CHARGE)
end

function ProjectileMath.GetSpeed(charge: number): number
	return ProjectileMath.MIN_SPEED + (ProjectileMath.MAX_SPEED - ProjectileMath.MIN_SPEED) * ProjectileMath.ClampCharge(charge)
end

function ProjectileMath.NormalizeDirection(direction: Vector3): Vector3?
	if not ProjectileMath.IsFiniteVector(direction) or not ProjectileMath.IsFiniteNumber(direction.Magnitude)
		or direction.Magnitude < 0.001 then
		return nil
	end
	local unit = direction.Unit
	return ProjectileMath.IsFiniteVector(unit) and unit or nil
end

function ProjectileMath.GetPosition(origin: Vector3, direction: Vector3, elapsed: number, charge: number): Vector3
	return origin + direction * math.min(ProjectileMath.MAX_DISTANCE, ProjectileMath.GetSpeed(charge) * elapsed)
end

return ProjectileMath
