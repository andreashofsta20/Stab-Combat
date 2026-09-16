-- Shared knife projectile rules. Keep this module free of Roblox services so the
-- client prediction and the server simulation use exactly the same numbers.
local ProjectileMath = {}

ProjectileMath.MAX_DISTANCE = 350
ProjectileMath.MAX_FLIGHT_TIME = 2
ProjectileMath.FIXED_STEP = 1 / 60
ProjectileMath.MIN_SPEED = 90
ProjectileMath.MAX_SPEED = 180
ProjectileMath.DAMAGE = 50
ProjectileMath.COOLDOWN = 0.5
ProjectileMath.MAX_CHARGE = 1
ProjectileMath.MIN_ORIGIN_DISTANCE = 0
ProjectileMath.MAX_ORIGIN_DISTANCE = 8

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
	if not ProjectileMath.IsFiniteVector(direction) or direction.Magnitude < 0.001 then
		return nil
	end
	return direction.Unit
end

function ProjectileMath.GetPosition(origin: Vector3, direction: Vector3, elapsed: number, charge: number): Vector3
	return origin + direction * math.min(ProjectileMath.MAX_DISTANCE, ProjectileMath.GetSpeed(charge) * elapsed)
end

return ProjectileMath
