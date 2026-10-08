-- Leaky displacement budget: tolerate packet bursts, limit sustained excess.
local Admission = {}
function Admission.Step(state, position, now, speed, ping, blocked)
	local finite = position.X == position.X and position.Y == position.Y and position.Z == position.Z
		and math.abs(position.X) < 1000000 and math.abs(position.Y) < 1000000 and math.abs(position.Z) < 1000000
	if not finite then return false, "NonFinite" end
	if not state.Position then state.Position, state.Time, state.Debt = position, now, 0; return true end
	local elapsed = math.clamp(now - state.Time, 0, 1)
	local dx, dz = position.X - state.Position.X, position.Z - state.Position.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local debt = math.max(0, (state.Debt or 0) + distance - speed * elapsed)
	local allowance = 4 + speed * math.clamp(ping or 0, 0, 0.5) * 2
	state.Time = now
	if blocked then return false, "SolidCover" end
	if debt > allowance then return false, "Displacement" end
	state.Position, state.Debt = position, debt
	return true
end
return Admission
